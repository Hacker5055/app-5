/* eslint-disable */
// crypto-core.js — dependency-free crypto for the browser preview.
//
// Implements SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256 and AES-256-GCM in plain
// JavaScript so the preview works from file:// with no CDN and no network. The
// test suite (test/preview_engine.test.mjs) cross-validates every primitive
// against Node's native WebCrypto implementation.

(function () {
  const SGV = (globalThis.SGV = globalThis.SGV || {});

  // ------------------------------------------------------------------ utils
  const hex = (bytes) =>
    Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');

  function fromHex(s) {
    const out = new Uint8Array(s.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
    return out;
  }

  function concat(...arrays) {
    let len = 0;
    for (const a of arrays) len += a.length;
    const out = new Uint8Array(len);
    let o = 0;
    for (const a of arrays) {
      out.set(a, o);
      o += a.length;
    }
    return out;
  }

  function utf8(str) {
    if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(str);
    return new Uint8Array(Buffer.from(str, 'utf8'));
  }

  function fromUtf8(bytes) {
    if (typeof TextDecoder !== 'undefined') return new TextDecoder().decode(bytes);
    return Buffer.from(bytes).toString('utf8');
  }

  // ---------------------------------------------------------------- SHA-256
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);

  function sha256(bytes) {
    const H = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
      0x1f83d9ab, 0x5be0cd19,
    ]);
    const bitLen = bytes.length * 8;
    const padded = new Uint8Array(((bytes.length + 9 + 63) >> 6) << 6);
    padded.set(bytes);
    padded[bytes.length] = 0x80;
    const dv = new DataView(padded.buffer);
    dv.setUint32(padded.length - 8, Math.floor(bitLen / 0x100000000));
    dv.setUint32(padded.length - 4, bitLen >>> 0);

    const w = new Uint32Array(64);
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
      for (let i = 16; i < 64; i++) {
        const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let [a, b, c, d, e, f, g, h] = H;
      for (let i = 0; i < 64; i++) {
        const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const t1 = (h + S1 + ch + K[i] + w[i]) >>> 0;
        const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (S0 + maj) >>> 0;
        h = g;
        g = f;
        f = e;
        e = (d + t1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) >>> 0;
      }
      H[0] = (H[0] + a) >>> 0;
      H[1] = (H[1] + b) >>> 0;
      H[2] = (H[2] + c) >>> 0;
      H[3] = (H[3] + d) >>> 0;
      H[4] = (H[4] + e) >>> 0;
      H[5] = (H[5] + f) >>> 0;
      H[6] = (H[6] + g) >>> 0;
      H[7] = (H[7] + h) >>> 0;
    }
    const out = new Uint8Array(32);
    const odv = new DataView(out.buffer);
    for (let i = 0; i < 8; i++) odv.setUint32(i * 4, H[i]);
    return out;
  }

  const rotr = (x, n) => (x >>> n) | (x << (32 - n));

  function hmacSha256(key, msg) {
    let k = key.length > 64 ? sha256(key) : key;
    const block = new Uint8Array(64);
    block.set(k);
    const ipad = new Uint8Array(64);
    const opad = new Uint8Array(64);
    for (let i = 0; i < 64; i++) {
      ipad[i] = block[i] ^ 0x36;
      opad[i] = block[i] ^ 0x5c;
    }
    const inner = sha256(concat(ipad, msg));
    return sha256(concat(opad, inner));
  }

  function pbkdf2(passwordBytes, salt, iterations, dkLen) {
    const blocks = Math.ceil(dkLen / 32);
    const out = new Uint8Array(blocks * 32);
    for (let i = 1; i <= blocks; i++) {
      const idx = new Uint8Array([(i >>> 24) & 0xff, (i >>> 16) & 0xff, (i >>> 8) & 0xff, i & 0xff]);
      let u = hmacSha256(passwordBytes, concat(salt, idx));
      const t = u.slice();
      for (let j = 1; j < iterations; j++) {
        u = hmacSha256(passwordBytes, u);
        for (let b = 0; b < 32; b++) t[b] ^= u[b];
      }
      out.set(t, (i - 1) * 32);
    }
    return out.subarray(0, dkLen);
  }

  // -------------------------------------------------------------------- AES
  const SBOX = new Uint8Array(256);
  const INV_SBOX = new Uint8Array(256);
  (function buildSBox() {
    const exp = new Uint8Array(255);
    const log = new Uint8Array(256);
    let a = 1;
    for (let i = 0; i < 255; i++) {
      exp[i] = a;
      log[a] = i;
      a ^= ((a << 1) ^ (a & 0x80 ? 0x11b : 0)) & 0xff;
    }
    const rotl8 = (v, n) => ((v << n) | (v >>> (8 - n))) & 0xff;
    for (let x = 0; x < 256; x++) {
      const inv = x === 0 ? 0 : exp[(255 - log[x]) % 255];
      const s = inv ^ rotl8(inv, 1) ^ rotl8(inv, 2) ^ rotl8(inv, 3) ^ rotl8(inv, 4) ^ 0x63;
      SBOX[x] = s;
      INV_SBOX[s] = x;
    }
  })();

  const xtime = (b) => ((b << 1) ^ (b & 0x80 ? 0x1b : 0)) & 0xff;
  function mul(a, b) {
    // GF(2^8) multiply, used by MixColumns.
    let p = 0;
    for (let i = 0; i < 8; i++) {
      if (b & 1) p ^= a;
      b >>= 1;
      a = xtime(a);
    }
    return p;
  }

  function expandKey256(key) {
    // AES-256: Nk=8, Nr=14 => 60 words
    const w = new Uint8Array(240);
    w.set(key);
    let rcon = 1;
    for (let i = 32; i < 240; i += 4) {
      let t = w.slice(i - 4, i);
      if (i % 32 === 0) {
        t = new Uint8Array([SBOX[t[1]] ^ rcon, SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]]);
        rcon = xtime(rcon);
      } else if (i % 32 === 16) {
        t = new Uint8Array([SBOX[t[0]], SBOX[t[1]], SBOX[t[2]], SBOX[t[3]]]);
      }
      for (let j = 0; j < 4; j++) w[i + j] = w[i - 32 + j] ^ t[j];
    }
    return w;
  }

  function encryptBlock(w, input) {
    const s = new Uint8Array(input); // state: column-major like the spec
    addRoundKey(s, w, 0);
    for (let round = 1; round < 14; round++) {
      subBytes(s);
      shiftRows(s, false);
      mixColumns(s, false);
      addRoundKey(s, w, round * 16);
    }
    subBytes(s);
    shiftRows(s, false);
    addRoundKey(s, w, 14 * 16);
    return s;
  }

  function decryptBlock(w, input) {
    const s = new Uint8Array(input);
    addRoundKey(s, w, 14 * 16);
    for (let round = 13; round >= 1; round--) {
      shiftRows(s, true);
      subBytes(s, true);
      addRoundKey(s, w, round * 16);
      mixColumns(s, true);
    }
    shiftRows(s, true);
    subBytes(s, true);
    addRoundKey(s, w, 0);
    return s;
  }

  function addRoundKey(s, w, off) {
    for (let i = 0; i < 16; i++) s[i] ^= w[off + i];
  }

  function subBytes(s, inverse) {
    const box = inverse ? INV_SBOX : SBOX;
    for (let i = 0; i < 16; i++) s[i] = box[s[i]];
  }

  function shiftRows(s, inverse) {
    const t = s.slice();
    for (let r = 0; r < 4; r++) {
      for (let c = 0; c < 4; c++) {
        const src = inverse ? (c - r + 4) % 4 : (c + r) % 4;
        s[r + 4 * c] = t[r + 4 * src];
      }
    }
  }

  function mixColumns(s, inverse) {
    const m = inverse
      ? [0x0e, 0x0b, 0x0d, 0x09]
      : [0x02, 0x03, 0x01, 0x01];
    for (let c = 0; c < 4; c++) {
      const col = [s[4 * c], s[4 * c + 1], s[4 * c + 2], s[4 * c + 3]];
      for (let r = 0; r < 4; r++) {
        s[4 * c + r] =
          mul(col[0], m[(4 - r) % 4]) ^
          mul(col[1], m[(5 - r) % 4]) ^
          mul(col[2], m[(6 - r) % 4]) ^
          mul(col[3], m[(7 - r) % 4]);
      }
    }
  }

  function aesCtr(w, counterBlock, input) {
    const out = new Uint8Array(input.length);
    const counter = counterBlock.slice();
    for (let off = 0; off < input.length; off += 16) {
      const ks = encryptBlock(w, counter);
      for (let i = 0; i < 16 && off + i < input.length; i++) out[off + i] = input[off + i] ^ ks[i];
      // increment last 4 bytes big-endian
      for (let i = 15; i >= 12; i--) {
        counter[i] = (counter[i] + 1) & 0xff;
        if (counter[i] !== 0) break;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- GHASH
  function gmul(x, y) {
    // 128-bit carry-less multiply mod GCM polynomial; x,y are Uint32Array(4).
    const z = new Uint32Array(4);
    const v = Uint32Array.from(y);
    for (let i = 0; i < 128; i++) {
      if ((x[i >> 5] >>> (31 - (i & 31))) & 1) {
        z[0] ^= v[0];
        z[1] ^= v[1];
        z[2] ^= v[2];
        z[3] ^= v[3];
      }
      const lsb = v[3] & 1;
      v[3] = (v[3] >>> 1) | ((v[2] & 1) << 31);
      v[2] = (v[2] >>> 1) | ((v[1] & 1) << 31);
      v[1] = (v[1] >>> 1) | ((v[0] & 1) << 31);
      v[0] = v[0] >>> 1;
      if (lsb) v[0] ^= 0xe1000000;
    }
    return z;
  }

  function bytesToWords(b) {
    const dv = new DataView(b.buffer, b.byteOffset, 16);
    return new Uint32Array([dv.getUint32(0), dv.getUint32(4), dv.getUint32(8), dv.getUint32(12)]);
  }

  function wordsToBytes(w) {
    const out = new Uint8Array(16);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, w[0]);
    dv.setUint32(4, w[1]);
    dv.setUint32(8, w[2]);
    dv.setUint32(12, w[3]);
    return out;
  }

  function ghash(hBytes, aad, ct) {
    const H = bytesToWords(hBytes);
    let y = new Uint32Array(4);
    const feed = (block) => {
      const x = bytesToWords(block);
      y = gmul(new Uint32Array([y[0] ^ x[0], y[1] ^ x[1], y[2] ^ x[2], y[3] ^ x[3]]), H);
    };
    for (let i = 0; i < aad.length; i += 16) {
      const block = new Uint8Array(16);
      block.set(aad.subarray(i, i + 16));
      feed(block);
    }
    for (let i = 0; i < ct.length; i += 16) {
      const block = new Uint8Array(16);
      block.set(ct.subarray(i, i + 16));
      feed(block);
    }
    const lenBlock = new Uint8Array(16);
    const dv = new DataView(lenBlock.buffer);
    dv.setUint32(0, Math.floor((aad.length * 8) / 0x100000000));
    dv.setUint32(4, (aad.length * 8) >>> 0);
    dv.setUint32(8, Math.floor((ct.length * 8) / 0x100000000));
    dv.setUint32(12, (ct.length * 8) >>> 0);
    feed(lenBlock);
    return wordsToBytes(y);
  }

  function gcmCounter(iv) {
    const j0 = new Uint8Array(16);
    j0.set(iv.subarray(0, 12));
    j0[15] = 1;
    const counter = j0.slice();
    for (let i = 15; i >= 12; i--) {
      counter[i] = (counter[i] + 1) & 0xff;
      if (counter[i] !== 0) break;
    }
    return counter;
  }

  function gcmEncrypt(key, iv, plaintext, aad) {
    const w = expandKey256(key);
    const ct = aesCtr(w, gcmCounter(iv), plaintext);
    const j0 = new Uint8Array(16);
    j0.set(iv.subarray(0, 12));
    j0[15] = 1;
    const h = encryptBlock(w, new Uint8Array(16));
    const s = ghash(h, aad || new Uint8Array(0), ct);
    const tag = aesCtr(w, j0, s);
    return concat(ct, tag);
  }

  function gcmDecrypt(key, iv, ctWithTag, aad) {
    if (ctWithTag.length < 16) throw new Error('Ciphertext too short');
    const ct = ctWithTag.subarray(0, ctWithTag.length - 16);
    const tag = ctWithTag.subarray(ctWithTag.length - 16);
    const w = expandKey256(key);
    const h = encryptBlock(w, new Uint8Array(16));
    const s = ghash(h, aad || new Uint8Array(0), ct);
    const j0 = new Uint8Array(16);
    j0.set(iv.subarray(0, 12));
    j0[15] = 1;
    const expected = aesCtr(w, j0, s);
    let diff = 0;
    for (let i = 0; i < 16; i++) diff |= expected[i] ^ tag[i];
    if (diff !== 0) throw new Error('AUTH_FAILED');
    return aesCtr(w, gcmCounter(iv), ct);
  }

  Object.assign(SGV, {
    hex,
    fromHex,
    concat,
    utf8,
    fromUtf8,
    sha256,
    hmacSha256,
    pbkdf2,
    expandKey256,
    encryptBlock,
    decryptBlock,
    aesCtr,
    gcmEncrypt,
    gcmDecrypt,
    SBOX,
  });
})();
