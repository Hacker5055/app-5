/* eslint-disable */
// png.js — lossless PNG writer (own deflate: LZ77 + fixed Huffman) and a PNG
// chunk reader used by the metadata audit. Decoding of *input* images is left to
// the browser's own codec via canvas, which is fast and format-complete.
//
// Why write our own encoder? The stego output container must be byte-exact and
// reproducible, free of every ancillary chunk (no tEXt/eXIf/iTXt sneaking back
// in), and it must run identically under Node for the test suite.

(function () {
  const SGV = (globalThis.SGV = globalThis.SGV || {});

  const CRC_TABLE = (() => {
    const table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
    return table;
  })();

  function crc32(bytes, start = 0, end = bytes.length) {
    let c = 0xffffffff;
    for (let i = start; i < end; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  function adler32(bytes) {
    let a = 1;
    let b = 0;
    for (let i = 0; i < bytes.length; i++) {
      a = (a + bytes[i]) % 65521;
      b = (b + a) % 65521;
    }
    return ((b << 16) | a) >>> 0;
  }

  // ------------------------------------------------------- bit writer (LSB-1st)
  function BitWriter(sizeHint) {
    this.buf = new Uint8Array(Math.max(1024, sizeHint | 0));
    this.len = 0;
    this.bitPos = 0;
  }
  BitWriter.prototype._ensure = function (bytes) {
    if (this.len + bytes <= this.buf.length) return;
    let cap = this.buf.length;
    while (cap < this.len + bytes) cap *= 2;
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  };
  BitWriter.prototype.writeBits = function (value, count) {
    for (let i = 0; i < count; i++) {
      this._ensure(2);
      if (this.bitPos === 0) this.buf[this.len] = 0;
      this.buf[this.len] |= ((value >>> i) & 1) << this.bitPos;
      this.bitPos++;
      if (this.bitPos === 8) {
        this.bitPos = 0;
        this.len++;
      }
    }
  };
  // Huffman codes are packed most-significant-bit first.
  BitWriter.prototype.writeCode = function (code, count) {
    for (let i = count - 1; i >= 0; i--) this.writeBits((code >>> i) & 1, 1);
  };
  BitWriter.prototype.align = function () {
    if (this.bitPos !== 0) {
      this.bitPos = 0;
      this.len++;
    }
  };
  BitWriter.prototype.toBytes = function () {
    const out = new Uint8Array(this.len + (this.bitPos ? 1 : 0));
    out.set(this.buf.subarray(0, out.length));
    return out;
  };

  // ------------------------------------------------------------- deflate
  const LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  const LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  const DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
  const DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

  function litCode(sym) {
    if (sym <= 143) return { code: 0x30 + sym, bits: 8 };
    if (sym <= 255) return { code: 0x190 + (sym - 144), bits: 9 };
    if (sym <= 279) return { code: sym - 256, bits: 7 };
    return { code: 0xc0 + (sym - 280), bits: 8 };
  }

  function lengthCode(len) {
    let i = 28;
    while (i > 0 && LEN_BASE[i] > len) i--;
    return { sym: 257 + i, extra: len - LEN_BASE[i], extraBits: LEN_EXTRA[i] };
  }

  function distCode(dist) {
    let i = 29;
    while (i > 0 && DIST_BASE[i] > dist) i--;
    return { sym: i, extra: dist - DIST_BASE[i], extraBits: DIST_EXTRA[i] };
  }

  /** Raw deflate, single fixed-Huffman block. */
  function deflateFixed(raw) {
    const bw = new BitWriter(raw.length >> 1);
    bw.writeBits(1, 1); // BFINAL
    bw.writeBits(1, 2); // BTYPE = fixed Huffman

    const WINDOW = 32768;
    const MAX_MATCH = 258;
    const MIN_MATCH = 3;
    const HASH_SIZE = 1 << 15;
    const head = new Int32Array(HASH_SIZE).fill(-1);
    const prev = new Int32Array(WINDOW).fill(-1);
    const hash = (i) => ((raw[i] << 10) ^ (raw[i + 1] << 5) ^ raw[i + 2]) & (HASH_SIZE - 1);

    let i = 0;
    while (i < raw.length) {
      let bestLen = 0;
      let bestDist = 0;
      if (i + MIN_MATCH <= raw.length) {
        const h = hash(i);
        let candidate = head[h];
        let chain = 0;
        while (candidate >= 0 && chain++ < 32) {
          const dist = i - candidate;
          if (dist <= 0 || dist > WINDOW) break;
          let len = 0;
          const maxLen = Math.min(MAX_MATCH, raw.length - i);
          while (len < maxLen && raw[candidate + len] === raw[i + len]) len++;
          if (len > bestLen) {
            bestLen = len;
            bestDist = dist;
            if (len === maxLen) break;
          }
          candidate = prev[candidate & (WINDOW - 1)];
        }
        prev[i & (WINDOW - 1)] = head[h];
        head[h] = i;
      }

      if (bestLen >= MIN_MATCH) {
        const lc = lengthCode(bestLen);
        const l = litCode(lc.sym);
        bw.writeCode(l.code, l.bits);
        if (lc.extraBits) bw.writeBits(lc.extra, lc.extraBits);
        const dc = distCode(bestDist);
        bw.writeCode(dc.sym, 5);
        if (dc.extraBits) bw.writeBits(dc.extra, dc.extraBits);
        // Insert hash entries for the skipped positions for better matches.
        const end = i + bestLen;
        i++;
        while (i < end) {
          if (i + MIN_MATCH <= raw.length) {
            const h = hash(i);
            prev[i & (WINDOW - 1)] = head[h];
            head[h] = i;
          }
          i++;
        }
        i = end;
      } else {
        const l = litCode(raw[i] & 0xff);
        bw.writeCode(l.code, l.bits);
        i++;
      }
    }
    const eob = litCode(256);
    bw.writeCode(eob.code, eob.bits);
    return bw.toBytes();
  }

  function zlibCompress(raw) {
    const body = deflateFixed(raw);
    const out = new Uint8Array(body.length + 6);
    out[0] = 0x78;
    out[1] = 0x01;
    out.set(body, 2);
    const ad = adler32(raw);
    out[out.length - 4] = (ad >>> 24) & 0xff;
    out[out.length - 3] = (ad >>> 16) & 0xff;
    out[out.length - 2] = (ad >>> 8) & 0xff;
    out[out.length - 1] = ad & 0xff;
    return out;
  }

  // ------------------------------------------------------------ PNG writing
  function chunk(type, data) {
    const out = new Uint8Array(12 + data.length);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, data.length);
    for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
    out.set(data, 8);
    dv.setUint32(8 + data.length, crc32(out, 4, 8 + data.length));
    return out;
  }

  /**
   * @param {{data:Uint8ClampedArray|Uint8Array,width:number,height:number}} imageData
   * @returns {Uint8Array} PNG bytes (8-bit RGBA, no ancillary chunks)
   */
  function encodePng(imageData) {
    const { width, height, data } = imageData;
    const stride = width * 4;
    const raw = new Uint8Array((stride + 1) * height);
    for (let y = 0; y < height; y++) {
      raw[y * (stride + 1)] = 0; // filter: None
      raw.set(data.subarray(y * stride, y * stride + stride), y * (stride + 1) + 1);
    }
    const ihdr = new Uint8Array(13);
    const dv = new DataView(ihdr.buffer);
    dv.setUint32(0, width);
    dv.setUint32(4, height);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // colour type: truecolour + alpha
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;

    const parts = [
      new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk('IHDR', ihdr),
      chunk('IDAT', zlibCompress(raw)),
      chunk('IEND', new Uint8Array(0)),
    ];
    let total = 0;
    for (const p of parts) total += p.length;
    const out = new Uint8Array(total);
    let o = 0;
    for (const p of parts) {
      out.set(p, o);
      o += p.length;
    }
    return out;
  }

  // -------------------------------------------------------- PNG chunk reader
  function readPngMeta(bytes) {
    const entries = [];
    let width = 0;
    let height = 0;
    let i = 8;
    while (i + 8 <= bytes.length) {
      const len = (bytes[i] << 24) | (bytes[i + 1] << 16) | (bytes[i + 2] << 8) | bytes[i + 3];
      if (len < 0 || i + 12 + len > bytes.length) break;
      const type = SGV.Meta.ascii(bytes, i + 4, i + 8);
      const data = bytes.subarray(i + 8, i + 8 + len);
      if (type === 'IHDR') {
        width = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
        height = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
      } else if (type === 'tEXt' || type === 'iTXt') {
        let sep = data.indexOf(0);
        if (sep < 0) sep = data.length;
        const key = SGV.Meta.ascii(data, 0, sep);
        const raw = SGV.Meta.ascii(data, Math.min(sep + 1, data.length), data.length).replace(/\0/g, '');
        entries.push({
          group: 'PNG',
          tag: key || type,
          value: raw.length > 120 ? raw.slice(0, 120) + '…' : raw,
          sensitive: true,
        });
      } else if (type === 'zTXt') {
        entries.push({ group: 'PNG', tag: 'zTXt', value: 'Compressed text chunk (stripped)', sensitive: true });
      } else if (type === 'eXIf') {
        const parsed = SGV.ExifTiff.read(data);
        entries.push(...parsed.entries);
      } else if (type === 'tIME') {
        entries.push({ group: 'PNG', tag: 'tIME', value: 'Last-modification timestamp', sensitive: true });
      } else if (type === 'IEND') break;
      i += 12 + len;
    }
    return { format: 'PNG', width, height, sizeBytes: bytes.length, entries, gps: null };
  }

  SGV.Png = { encodePng, readPngMeta, crc32, adler32, zlibCompress, deflateFixed };
})();
