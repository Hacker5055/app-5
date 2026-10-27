/* eslint-disable */
// stego-engine.js — SGV-1 container engine (LSB embed/extract), browser port.
// Bit-compatible with lib/core/LSBStegoEngine.dart — see docs/STEGO_FORMAT.md.

(function () {
  const SGV = (globalThis.SGV = globalThis.SGV || {});
  const MAGIC = [0x53, 0x47, 0x56, 0x31]; // "SGV1"
  const VERSION = 0x01;
  const HEADER_LEN = 38;
  const SALT_OFF = 10;
  const IV_OFF = 26;
  const SALT_LEN = 16;
  const IV_LEN = 12;
  const TAG_LEN = 16;
  const AAD_LEN = 10;
  const FLAG_FILE = 0x01;
  const FLAG_2BIT = 0x02;

  const DEFAULT_ITERATIONS = 100000;

  // crypto.getRandomValues() refuses buffers larger than 65 536 bytes, so large
  // requests (the random LSB padding can be hundreds of kilobytes) are chunked.
  const RANDOM_CHUNK = 65536;

  function randomBytes(n) {
    const out = new Uint8Array(n);
    const webCrypto = globalThis.crypto;
    if (webCrypto && webCrypto.getRandomValues) {
      for (let offset = 0; offset < n; offset += RANDOM_CHUNK) {
        webCrypto.getRandomValues(out.subarray(offset, Math.min(n, offset + RANDOM_CHUNK)));
      }
      return out;
    }
    for (let i = 0; i < n; i++) out[i] = (Math.random() * 256) | 0;
    return out;
  }

  function capacityBytes(width, height, depth) {
    return Math.floor((width * height * 3 * depth) / 8);
  }

  function usableBytes(width, height, depth) {
    const cap = capacityBytes(width, height, depth);
    const usable = cap - HEADER_LEN - TAG_LEN;
    return usable < 0 ? 0 : usable;
  }

  function utf8Frame(fileName, mimeType, fileBytes) {
    const name = SGV.utf8(fileName);
    const mime = SGV.utf8(mimeType);
    const out = new Uint8Array(4 + name.length + mime.length + fileBytes.length);
    out[0] = (name.length >> 8) & 0xff;
    out[1] = name.length & 0xff;
    out.set(name, 2);
    out[2 + name.length] = (mime.length >> 8) & 0xff;
    out[3 + name.length] = mime.length & 0xff;
    out.set(mime, 4 + name.length);
    out.set(fileBytes, 4 + name.length + mime.length);
    return out;
  }

  function unframeFile(bytes) {
    const nameLen = (bytes[0] << 8) | bytes[1];
    const name = SGV.fromUtf8(bytes.subarray(2, 2 + nameLen));
    let c = 2 + nameLen;
    const mimeLen = (bytes[c] << 8) | bytes[c + 1];
    c += 2;
    const mime = SGV.fromUtf8(bytes.subarray(c, c + mimeLen));
    c += mimeLen;
    return { fileName: name, mimeType: mime, data: bytes.subarray(c) };
  }

  function buildHeader(flags, cipherLen, salt, iv) {
    const header = new Uint8Array(HEADER_LEN);
    header.set(MAGIC, 0);
    header[4] = VERSION;
    header[5] = flags;
    header[6] = (cipherLen >>> 24) & 0xff;
    header[7] = (cipherLen >>> 16) & 0xff;
    header[8] = (cipherLen >>> 8) & 0xff;
    header[9] = cipherLen & 0xff;
    header.set(salt, SALT_OFF);
    header.set(iv, IV_OFF);
    return header;
  }

  function hasMagic(bytes, offset) {
    if (bytes.length < offset + 4) return false;
    for (let i = 0; i < 4; i++) if (bytes[offset + i] !== MAGIC[i]) return false;
    return true;
  }

  function parseHeader(bytes) {
    return {
      version: bytes[4],
      flags: bytes[5],
      cipherLen: ((bytes[6] << 24) | (bytes[7] << 16) | (bytes[8] << 8) | bytes[9]) >>> 0,
      salt: bytes.slice(SALT_OFF, SALT_OFF + SALT_LEN),
      iv: bytes.slice(IV_OFF, IV_OFF + IV_LEN),
      aad: bytes.slice(0, AAD_LEN),
      isFile: (bytes[5] & FLAG_FILE) !== 0,
      depth: (bytes[5] & FLAG_2BIT) !== 0 ? 2 : 1,
    };
  }

  // ------------------------------------------------------------------ bit io
  function writeBits(data, depth, stream, bitOffset) {
    let pos = bitOffset;
    for (let i = 0; i < stream.length; i++) {
      const byte = stream[i];
      for (let b = 7; b >= 0; b--) {
        const bit = (byte >> b) & 1;
        const pixel = Math.floor(pos / (3 * depth));
        const rem = pos % (3 * depth);
        const channel = Math.floor(rem / depth);
        const inChannel = depth - 1 - (rem % depth);
        const idx = pixel * 4 + channel;
        if (idx >= data.length) return;
        data[idx] = (data[idx] & ~(1 << inChannel)) | (bit << inChannel);
        pos++;
      }
    }
  }

  function readBits(data, depth, bitOffset, byteLength) {
    const out = new Uint8Array(byteLength);
    let pos = bitOffset;
    for (let i = 0; i < byteLength; i++) {
      let value = 0;
      for (let b = 7; b >= 0; b--) {
        const pixel = Math.floor(pos / (3 * depth));
        const rem = pos % (3 * depth);
        const channel = Math.floor(rem / depth);
        const inChannel = depth - 1 - (rem % depth);
        const idx = pixel * 4 + channel;
        if (idx >= data.length) return out;
        const bit = (data[idx] >> inChannel) & 1;
        value = (value << 1) | bit;
        pos++;
      }
      out[i] = value;
    }
    return out;
  }

  // --------------------------------------------------------------- embed API
  /**
   * @param {ImageData|{data:Uint8ClampedArray,width:number,height:number}} cover
   * @param {{password:string, text?:string, fileBytes?:Uint8Array,
   *          fileName?:string, mimeType?:string, depth?:number,
   *          iterations?:number, onStage?:(s:string)=>void}} opts
   * @returns {{imageData:object, depth:number, capacity:number, usedBytes:number,
   *            iterations:number, psnr:number, elapsed:number}}
   */
  function embed(cover, opts) {
    const t0 = performance.now();
    const depth = opts.depth === 2 ? 2 : 1;
    const iterations = opts.iterations || DEFAULT_ITERATIONS;
    const isFile = !!opts.fileBytes;
    const plaintext = isFile
      ? utf8Frame(opts.fileName || 'payload.bin', opts.mimeType || 'application/octet-stream', opts.fileBytes)
      : SGV.utf8(opts.text || '');

    const cap = capacityBytes(cover.width, cover.height, depth);
    const maxPlain = usableBytes(cover.width, cover.height, depth);
    if (plaintext.length > maxPlain) {
      throw new Error(
        `Payload is ${plaintext.length.toLocaleString()} B but this image holds only ${maxPlain.toLocaleString()} B at ${depth}-bit.`
      );
    }
    if (!opts.password) throw new Error('A password is required.');

    const flags = (isFile ? FLAG_FILE : 0) | (depth === 2 ? FLAG_2BIT : 0);
    const salt = randomBytes(SALT_LEN);
    const iv = randomBytes(IV_LEN);
    const aad = new Uint8Array(AAD_LEN);
    aad.set(MAGIC, 0);
    aad[4] = VERSION;
    aad[5] = flags;
    const cipherLen = plaintext.length + TAG_LEN;
    aad[6] = (cipherLen >>> 24) & 0xff;
    aad[7] = (cipherLen >>> 16) & 0xff;
    aad[8] = (cipherLen >>> 8) & 0xff;
    aad[9] = cipherLen & 0xff;

    opts.onStage && opts.onStage('Deriving key (PBKDF2 100k)');
    const key = SGV.pbkdf2(SGV.utf8(opts.password), salt, iterations, 32);
    opts.onStage && opts.onStage('Encrypting (AES-256-GCM)');
    const cipher = SGV.gcmEncrypt(key, iv, plaintext, aad);

    const header = buildHeader(flags, cipherLen, salt, iv);
    const stream = SGV.concat(header, cipher);

    const out = new Uint8ClampedArray(cover.data);
    opts.onStage && opts.onStage('Embedding LSB plane');
    writeBits(out, depth, stream, 0);
    // Random padding hides where the ciphertext ends.
    const padBytes = Math.floor((cap * 8 - stream.length * 8) / 8);
    if (padBytes > 0) {
      const pad = randomBytes(padBytes);
      writeBits(out, depth, pad, stream.length * 8);
    }

    const psnr = estimatePsnr(stream.length, cap);
    return {
      imageData: { data: out, width: cover.width, height: cover.height },
      depth,
      capacity: cap,
      usable: maxPlain,
      usedBytes: stream.length,
      payloadBytes: plaintext.length,
      iterations,
      psnr,
      elapsed: performance.now() - t0,
      salt,
      iv,
      flags,
    };
  }

  function estimatePsnr(usedBytes, capacity) {
    if (!capacity) return 99;
    const fill = usedBytes / capacity;
    return 60 - 10 * Math.min(1, fill * 2.2);
  }

  /**
   * Tries 1-bit then 2-bit planes.
   * @returns {{text?:string, file?:{fileName:string,mimeType:string,data:Uint8Array},
   *            header:object, depth:number, iterations:number, elapsed:number}}
   */
  function extract(cover, opts) {
    const t0 = performance.now();
    const iterations = opts.iterations || DEFAULT_ITERATIONS;
    for (const depth of [1, 2]) {
      const head = readBits(cover.data, depth, 0, HEADER_LEN);
      if (!hasMagic(head, 0)) continue;
      const header = parseHeader(head);
      const cap = capacityBytes(cover.width, cover.height, depth);
      if (header.cipherLen <= 0 || header.cipherLen > cap - HEADER_LEN) {
        throw new Error('Container header is inconsistent (length out of range).');
      }
      opts.onStage && opts.onStage('Deriving key (PBKDF2 100k)');
      const key = SGV.pbkdf2(SGV.utf8(opts.password || ''), header.salt, iterations, 32);
      opts.onStage && opts.onStage('Verifying GCM tag');
      const cipher = readBits(cover.data, depth, HEADER_LEN * 8, header.cipherLen);
      let plain;
      try {
        plain = SGV.gcmDecrypt(key, header.iv, cipher, header.aad);
      } catch (e) {
        const err = new Error('Wrong password — the authentication tag did not verify.');
        err.code = 'AUTH_FAILED';
        throw err;
      }
      const result = {
        header,
        depth,
        iterations,
        elapsed: performance.now() - t0,
        raw: plain,
      };
      if (header.isFile) {
        result.file = unframeFile(plain);
      } else {
        result.text = SGV.fromUtf8(plain);
      }
      return result;
    }
    const err = new Error('No SGV1 container found in this image.');
    err.code = 'NO_CONTAINER';
    throw err;
  }

  function detect(cover) {
    for (const depth of [1, 2]) {
      const head = readBits(cover.data, depth, 0, HEADER_LEN);
      if (!hasMagic(head, 0)) continue;
      try {
        return { present: true, header: parseHeader(head), depth };
      } catch (_) {}
    }
    return { present: false, header: null, depth: 0 };
  }

  /** Pixel-level difference between cover and stego image (for the slider HUD). */
  function diff(a, b) {
    let sumSq = 0;
    let changed = 0;
    let maxDelta = 0;
    const n = Math.min(a.data.length, b.data.length);
    for (let i = 0; i < n; i++) {
      if (i % 4 === 3) continue; // alpha
      const d = Math.abs(a.data[i] - b.data[i]);
      sumSq += d * d;
      if (d) changed++;
      if (d > maxDelta) maxDelta = d;
    }
    const channels = Math.floor(n / 4) * 3;
    const mse = channels ? sumSq / channels : 0;
    return {
      psnr: mse === 0 ? 99 : 10 * Math.log10((255 * 255) / mse),
      changed,
      channels,
      maxDelta,
      changedRatio: channels ? changed / channels : 0,
    };
  }

  SGV.Stego = {
    MAGIC,
    VERSION,
    HEADER_LEN,
    TAG_LEN,
    DEFAULT_ITERATIONS,
    capacityBytes,
    usableBytes,
    embed,
    extract,
    detect,
    diff,
    readBits,
    writeBits,
    parseHeader,
    utf8Frame,
    unframeFile,
  };
})();
