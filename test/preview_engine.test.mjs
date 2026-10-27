// Engine test-suite for the browser build (also serves as a spec for the Dart
// port). Run with:  node --test test/
//
// Cross-checks:
//   * crypto primitives  -> Node's native WebCrypto
//   * PNG encoder        -> Node's zlib + ImageMagick pixel comparison
//   * JPEG scrubber      -> ImageMagick pixel comparison (lossless proof)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import nodeCrypto from 'node:crypto';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

for (const file of ['crypto-core.js', 'png.js', 'jpeg-meta.js', 'mock.js', 'stego-engine.js']) {
  require(path.join(root, 'preview', 'js', file));
}
const SGV = globalThis.SGV;

const hasMagick = spawnSync('convert', ['-version']).status === 0;
const FAST = 1000; // PBKDF2 rounds for tests (production = 100_000, fixed by spec)

const hex = (b) => SGV.hex(b);
// JFIF/ICC describe colour handling, not a person or device: they are kept so
// that colours render identically after the scrub.
const isHarmless = (e) => e.group === 'JFIF' || e.group === 'ICC';
const bytes = (b) => Buffer.from(b);

// ---------------------------------------------------------------------------
// 1. crypto primitives
// ---------------------------------------------------------------------------
test('AES S-box matches FIPS-197 table', () => {
  assert.equal(SGV.SBOX[0x00], 0x63);
  assert.equal(SGV.SBOX[0x01], 0x7c);
  assert.equal(SGV.SBOX[0x53], 0xed);
  assert.equal(SGV.SBOX[0xff], 0x16);
});

test('SHA-256 matches Node', () => {
  for (const msg of ['', 'abc', 'a'.repeat(1000), 'منظف البصمات الرقمية والتشفير المخفي']) {
    const mine = hex(SGV.sha256(SGV.utf8(msg)));
    const ref = nodeCrypto.createHash('sha256').update(msg, 'utf8').digest('hex');
    assert.equal(mine, ref);
  }
});

test('AES-256 block encryption matches the FIPS-197 C.3 vector', () => {
  const key = SGV.fromHex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
  const pt = SGV.fromHex('00112233445566778899aabbccddeeff');
  const w = SGV.expandKey256(key);
  assert.equal(hex(SGV.encryptBlock(w, pt)), '8ea2b7ca516745bfeafc49904b496089');
  assert.equal(hex(SGV.decryptBlock(w, SGV.fromHex('8ea2b7ca516745bfeafc49904b496089'))), '00112233445566778899aabbccddeeff');
});

test('AES-256-GCM interoperates with Node in both directions', () => {
  const key = nodeCrypto.randomBytes(32);
  const iv = nodeCrypto.randomBytes(12);
  const aad = Buffer.from('SGV1-header');
  const msg = Buffer.from('stego vault payload '.repeat(37));

  const nodeCipher = nodeCrypto.createCipheriv('aes-256-gcm', key, iv);
  nodeCipher.setAAD(aad);
  const nodeOut = Buffer.concat([nodeCipher.update(msg), nodeCipher.final(), nodeCipher.getAuthTag()]);

  const mine = SGV.gcmEncrypt(new Uint8Array(key), new Uint8Array(iv), new Uint8Array(msg), new Uint8Array(aad));
  assert.equal(hex(mine), nodeOut.toString('hex'), 'our ciphertext+tag must equal OpenSSL/Node');

  const nodeDecipher = nodeCrypto.createDecipheriv('aes-256-gcm', key, iv);
  nodeDecipher.setAAD(aad);
  nodeDecipher.setAuthTag(nodeOut.subarray(-16));
  const nodePlain = Buffer.concat([nodeDecipher.update(nodeOut.subarray(0, -16)), nodeDecipher.final()]);
  assert.equal(nodePlain.toString(), msg.toString(), 'Node must decrypt our output');

  assert.equal(bytes(SGV.gcmDecrypt(new Uint8Array(key), new Uint8Array(iv), mine, new Uint8Array(aad))).toString(), msg.toString());
});

test('GBM tag rejects tampered ciphertext and AAD', () => {
  const key = nodeCrypto.randomBytes(32);
  const iv = nodeCrypto.randomBytes(12);
  const aad = new Uint8Array([1, 2, 3]);
  const ct = SGV.gcmEncrypt(new Uint8Array(key), new Uint8Array(iv), SGV.utf8('payload'), aad);
  const flipped = ct.slice();
  flipped[3] ^= 0x01;
  assert.throws(() => SGV.gcmDecrypt(new Uint8Array(key), new Uint8Array(iv), flipped, aad), /AUTH_FAILED/);
  assert.throws(() => SGV.gcmDecrypt(new Uint8Array(key), new Uint8Array(iv), ct, new Uint8Array([1, 2, 4])), /AUTH_FAILED/);
});

test('PBKDF2-HMAC-SHA256 (100k) matches Node', () => {
  const salt = SGV.fromHex('00112233445566778899aabbccddeeff');
  const mine = hex(SGV.pbkdf2(SGV.utf8('correct horse battery staple'), salt, 100000, 32));
  const ref = nodeCrypto.pbkdf2Sync('correct horse battery staple', salt, 100000, 32, 'sha256').toString('hex');
  assert.equal(mine, ref);
});

// ---------------------------------------------------------------------------
// 2. PNG encoder
// ---------------------------------------------------------------------------
test('PNG encoder emits a valid zlib stream and is pixel-exact', () => {
  const scene = SGV.Mock.scene(64, 48, 1);
  const png = SGV.Png.encodePng(scene);
  assert.equal(hex(png.subarray(0, 8)), '89504e470d0a1a0a');

  // pull IDAT and verify Node's zlib can inflate it
  let idat = [];
  let i = 8;
  while (i < png.length) {
    const len = (png[i] << 24) | (png[i + 1] << 16) | (png[i + 2] << 8) | png[i + 3];
    const type = SGV.Meta.ascii(png, i + 4, i + 8);
    if (type === 'IDAT') idat.push(bytes(png.subarray(i + 8, i + 8 + len)));
    i += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  assert.equal(raw.length, (64 * 4 + 1) * 48);
  for (let y = 0; y < 48; y++) {
    assert.equal(raw[y * (64 * 4 + 1)], 0, 'filter byte must be None');
    const row = raw.subarray(y * (64 * 4 + 1) + 1, y * (64 * 4 + 1) + 1 + 64 * 4);
    assert.equal(hex(row), hex(scene.data.subarray(y * 64 * 4, (y + 1) * 64 * 4)), `row ${y} mismatch`);
  }
});

test('PNG encoder output decodes identically in ImageMagick', { skip: !hasMagick && 'ImageMagick not available' }, () => {
  const scene = SGV.Mock.scene(96, 64, 2);
  const png = SGV.Png.encodePng(scene);
  const res = spawnSync('convert', ['png:-', '-depth', '8', 'rgba:-'], { input: Buffer.from(png), maxBuffer: 64 * 1024 * 1024 });
  assert.equal(res.status, 0, res.stderr.toString());
  assert.equal(res.stdout.length, 96 * 64 * 4);
  assert.equal(hex(res.stdout), hex(scene.data), 'pixels must survive the encode/decode round-trip');
});

// ---------------------------------------------------------------------------
// 3. LSB steganography
// ---------------------------------------------------------------------------
const cover = () => SGV.Mock.scene(320, 240, 0);

test('text payload survives 1-bit embed → extract', () => {
  const secret = 'Meet at 30.0444, 31.2357 — bring the drive.';
  const res = SGV.Stego.embed(cover(), { password: 'pw-123456', text: secret, depth: 1, iterations: FAST });
  assert.equal(res.depth, 1);
  assert.ok(res.usedBytes > secret.length);
  const out = SGV.Stego.extract(res.imageData, { password: 'pw-123456', iterations: FAST });
  assert.equal(out.text, secret);
  assert.equal(out.depth, 1);
  assert.equal(out.header.isFile, false);
});

test('2-bit mode doubles capacity and round-trips', () => {
  const c = cover();
  const cap1 = SGV.Stego.capacityBytes(c.width, c.height, 1);
  const cap2 = SGV.Stego.capacityBytes(c.width, c.height, 2);
  assert.equal(cap2, cap1 * 2);

  const secret = 'x'.repeat(4000);
  const res = SGV.Stego.embed(c, { password: 'pw-2bit-mode', text: secret, depth: 2, iterations: FAST });
  assert.equal(res.depth, 2);
  const out = SGV.Stego.extract(res.imageData, { password: 'pw-2bit-mode', iterations: FAST });
  assert.equal(out.text, secret);
  assert.equal(out.depth, 2);
});

test('file payload keeps name, mime type and bytes', () => {
  const fileBytes = SGV.concat(SGV.utf8('%PDF-1.7\n'), new Uint8Array([0, 1, 2, 3, 255, 254, 0]));
  const res = SGV.Stego.embed(cover(), {
    password: 'pw-files',
    fileBytes,
    fileName: 'blueprint.pdf',
    mimeType: 'application/pdf',
    depth: 1,
    iterations: FAST,
  });
  const out = SGV.Stego.extract(res.imageData, { password: 'pw-files', iterations: FAST });
  assert.equal(out.header.isFile, true);
  assert.equal(out.file.fileName, 'blueprint.pdf');
  assert.equal(out.file.mimeType, 'application/pdf');
  assert.equal(hex(out.file.data), hex(fileBytes));
});

test('wrong password is rejected by the GCM tag', () => {
  const res = SGV.Stego.embed(cover(), { password: 'right-password', text: 'classified', iterations: FAST });
  assert.throws(
    () => SGV.Stego.extract(res.imageData, { password: 'wrong-password', iterations: FAST }),
    (err) => err.code === 'AUTH_FAILED'
  );
});

test('a single flipped payload bit fails authentication', () => {
  const res = SGV.Stego.embed(cover(), { password: 'pw-tamper', text: 'integrity matters', iterations: FAST });
  // flip one bit inside the ciphertext region (after the 38-byte header)
  const bitIndex = SGV.Stego.HEADER_LEN * 8 + 64;
  const pixel = Math.floor(bitIndex / 3);
  res.imageData.data[pixel * 4] ^= 0x01;
  assert.throws(
    () => SGV.Stego.extract(res.imageData, { password: 'pw-tamper', iterations: FAST }),
    (err) => err.code === 'AUTH_FAILED'
  );
});

test('a plain image reports "no container"', () => {
  assert.equal(SGV.Stego.detect(cover()).present, false);
  assert.throws(() => SGV.Stego.extract(cover(), { password: 'x', iterations: FAST }), (err) => err.code === 'NO_CONTAINER');
});

test('detect() reports the depth and ciphertext size without the password', () => {
  const res = SGV.Stego.embed(cover(), { password: 'pw-detect', text: 'hello', depth: 2, iterations: FAST });
  const presence = SGV.Stego.detect(res.imageData);
  assert.equal(presence.present, true);
  assert.equal(presence.depth, 2);
  assert.equal(presence.header.cipherLen, 'hello'.length + SGV.Stego.TAG_LEN);
});

test('oversized payload is refused before any pixel is touched', () => {
  const c = cover();
  const usable = SGV.Stego.usableBytes(c.width, c.height, 1);
  assert.throws(
    () => SGV.Stego.embed(c, { password: 'pw', text: 'a'.repeat(usable + 10), iterations: FAST }),
    /exceeds|holds only/
  );
});

test('alpha channel is never modified', () => {
  const c = cover();
  const res = SGV.Stego.embed(c, { password: 'pw-alpha', text: 'alpha safe', iterations: FAST });
  for (let i = 3; i < c.data.length; i += 4) {
    if (c.data[i] !== res.imageData.data[i]) assert.fail(`alpha changed at ${i}`);
  }
});

test('imperceptibility: max channel delta ≤ 1 at 1-bit and ≤ 3 at 2-bit', () => {
  const c = cover();
  const one = SGV.Stego.embed(c, { password: 'pw-visual', text: 'visual check', depth: 1, iterations: FAST });
  assert.ok(Math.max(1, SGV.Stego.diff(c, one.imageData).maxDelta) <= 1);
  const two = SGV.Stego.embed(c, { password: 'pw-visual', text: 'visual check', depth: 2, iterations: FAST });
  assert.ok(SGV.Stego.diff(c, two.imageData).maxDelta <= 3);
  assert.ok(SGV.Stego.diff(c, one.imageData).psnr > 45);
});

test('stego PNG extracts after a full PNG encode → ImageMagick decode → re-read', { skip: !hasMagick && 'ImageMagick not available' }, () => {
  const secret = 'survives png encoding';
  const res = SGV.Stego.embed(cover(), { password: 'pw-png', text: secret, iterations: FAST });
  const png = SGV.Png.encodePng(res.imageData);
  const raw = spawnSync('convert', ['png:-', '-depth', '8', 'rgba:-'], { input: Buffer.from(png), maxBuffer: 64 * 1024 * 1024 });
  assert.equal(raw.status, 0, raw.stderr.toString());
  const roundTripped = { data: new Uint8ClampedArray(raw.stdout), width: res.imageData.width, height: res.imageData.height };
  const out = SGV.Stego.extract(roundTripped, { password: 'pw-png', iterations: FAST });
  assert.equal(out.text, secret);
});

test('random padding fills the remaining capacity (ciphertext is not detectable by histogram)', () => {
  const c = cover();
  const res = SGV.Stego.embed(c, { password: 'pw-pad', text: 'tiny', iterations: FAST });
  const cap = SGV.Stego.capacityBytes(c.width, c.height, 1);
  // Every byte beyond the container must be pseudo-random: check the LSB plane's
  // overall balance stays near 50%.
  let ones = 0;
  for (let i = 0; i < c.data.length; i++) if (i % 4 !== 3) ones += res.imageData.data[i] & 1;
  const ratio = ones / (c.width * c.height * 3);
  assert.ok(ratio > 0.45 && ratio < 0.55, `LSB balance was ${ratio}`);
  assert.ok(res.usedBytes <= cap);
});

// ---------------------------------------------------------------------------
// 4. metadata scrubbing
// ---------------------------------------------------------------------------
test('mock EXIF segment parses into IFD0 / Exif / GPS / XMP / IPTC rows', () => {
  const seg = SGV.Mock.metadataSegments(1024, 768);
  const jpeg = SGV.concat(new Uint8Array([0xff, 0xd8]), seg, new Uint8Array([0xff, 0xda, 0, 8, 1, 1, 0, 0, 0, 0, 0xff, 0xd9]));
  const audit = SGV.Meta.inspectJpeg(jpeg);
  const groups = new Set(audit.entries.map((e) => e.group));
  for (const g of ['IFD0', 'Exif', 'GPS', 'XMP', 'IPTC', 'COMMENT']) assert.ok(groups.has(g), `missing ${g}`);
  assert.equal(audit.gps.latitude.toFixed(4), '30.0444');
  assert.equal(audit.gps.longitude.toFixed(4), '31.2357');
  assert.ok(audit.entries.some((e) => e.tag === 'BodySerialNumber'));
  assert.ok(audit.entries.some((e) => e.tag === 'CameraOwnerName'));
  assert.ok(audit.entries.filter((e) => e.sensitive).length >= 25);
});

test('stripJpeg removes every metadata segment', () => {
  const seg = SGV.Mock.metadataSegments(640, 480);
  const jpeg = SGV.concat(new Uint8Array([0xff, 0xd8]), seg, new Uint8Array([0xff, 0xda, 0, 8, 1, 1, 0, 0, 0, 0, 0xff, 0xd9]));
  const stripped = SGV.Meta.stripJpeg(jpeg);
  const after = SGV.Meta.inspectJpeg(stripped);
  assert.equal(after.entries.length, 0);
  assert.equal(after.gps, null);
  assert.equal(hex(stripped.subarray(0, 2)), 'ffd8');
  assert.equal(hex(stripped.subarray(-2)), 'ffd9');
  assert.ok(stripped.length < jpeg.length);
});

test('JPEG scrub is lossless: ImageMagick decodes identical pixels before and after', { skip: !hasMagick && 'ImageMagick not available' }, () => {
  // Real JPEG from ImageMagick, then inject genuine EXIF/XMP/IPTC segments.
  const scene = SGV.Mock.scene(200, 150, 3);
  const png = Buffer.from(SGV.Png.encodePng(scene));
  const jpgRes = spawnSync('convert', ['png:-', '-quality', '93', 'jpg:-'], { input: png, maxBuffer: 64 * 1024 * 1024 });
  assert.equal(jpgRes.status, 0, jpgRes.stderr.toString());
  const jpeg = SGV.Mock.injectSegments(new Uint8Array(jpgRes.stdout), SGV.Mock.metadataSegments(200, 150));

  const before = SGV.Meta.inspectJpeg(jpeg);
  assert.ok(before.entries.length > 30, `expected rich metadata, got ${before.entries.length}`);

  const stripped = SGV.Meta.stripJpeg(jpeg);
  const remaining = SGV.Meta.inspectJpeg(stripped).entries.filter((e) => !isHarmless(e));
  assert.deepEqual(remaining, [], 'no identity-bearing tag may survive');

  const px = (buf) => {
    const r = spawnSync('convert', ['jpg:-', '-depth', '8', 'rgb:-'], { input: Buffer.from(buf), maxBuffer: 64 * 1024 * 1024 });
    assert.equal(r.status, 0, r.stderr.toString());
    return r.stdout;
  };
  assert.equal(hex(px(jpeg)), hex(px(stripped)), 'pixels must be bit-identical after stripping');
  assert.ok(stripped.length < jpeg.length);
});

test('PNG tEXt chunks are detected by the audit', () => {
  // hand-build a PNG with a tEXt chunk
  const scene = SGV.Mock.scene(40, 30, 3);
  const base = SGV.Png.encodePng(scene);
  const text = SGV.concat(SGV.utf8('Author'), new Uint8Array([0]), SGV.utf8('Layla Hassan'));
  const chunk = (type, data) => {
    const out = new Uint8Array(12 + data.length);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, data.length);
    for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
    out.set(data, 8);
    dv.setUint32(8 + data.length, SGV.Png.crc32(out, 4, 8 + data.length));
    return out;
  };
  // insert before IEND
  const iendStart = base.length - 12;
  const withText = SGV.concat(base.subarray(0, iendStart), chunk('tEXt', text), base.subarray(iendStart));
  const audit = SGV.Png.readPngMeta(withText);
  assert.equal(audit.format, 'PNG');
  assert.equal(audit.width, 40);
  assert.ok(audit.entries.some((e) => e.tag === 'Author' && e.value === 'Layla Hassan'));
});

test('scene generator is deterministic per seed', () => {
  const a = SGV.Mock.scene(64, 64, 0);
  const b = SGV.Mock.scene(64, 64, 0);
  assert.equal(hex(a.data), hex(b.data));
  const c = SGV.Mock.scene(64, 64, 1);
  assert.notEqual(hex(a.data), hex(c.data));
});
