// test/ui_smoke.test.mjs — end-to-end UI smoke test for the browser build.
//
// Runs the real index.html + app.js inside jsdom with canvas/media stubs, then
// drives the three tabs exactly like a user would:
//   mock photo -> audit -> scrub -> cover -> embed -> detect -> reveal -> wrong pw
//
// Requires `npm install` (jsdom). Skips cleanly when jsdom is absent so the
// plain `node --test` engine suite still runs on a bare checkout.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const previewDir = path.join(root, 'preview');

let JSDOM;
let VirtualConsole;
try {
  ({ JSDOM, VirtualConsole } = await import('jsdom'));
} catch {
  JSDOM = null;
}

function fakeContext(canvas, ImageDataCtor) {
  const gradient = { addColorStop() {} };
  return {
    canvas,
    fillStyle: '',
    strokeStyle: '',
    lineWidth: 1,
    font: '',
    textAlign: '',
    globalAlpha: 1,
    createRadialGradient: () => gradient,
    createLinearGradient: () => gradient,
    createConicGradient: () => gradient,
    measureText: (text) => ({ width: String(text).length * 7 }),
    getImageData: (x, y, w, h) => {
      const data = new Uint8ClampedArray(w * h * 4);
      for (let i = 0; i < w * h; i++) {
        data[i * 4] = (i * 37) & 0xff;
        data[i * 4 + 1] = (i * 73) & 0xff;
        data[i * 4 + 2] = (i * 11) & 0xff;
        data[i * 4 + 3] = 255;
      }
      return new ImageDataCtor(data, w, h);
    },
    putImageData() {},
    drawImage() {},
    clearRect() {},
    fillRect() {},
    strokeRect() {},
    beginPath() {},
    closePath() {},
    moveTo() {},
    lineTo() {},
    quadraticCurveTo() {},
    bezierCurveTo() {},
    arc() {},
    arcTo() {},
    rect() {},
    roundRect() {},
    fill() {},
    stroke() {},
    save() {},
    restore() {},
    translate() {},
    rotate() {},
    scale() {},
    setLineDash() {},
    clip() {},
    fillText() {},
    strokeText() {},
    createPattern: () => null,
  };
}

async function boot() {
  const html = fs.readFileSync(path.join(previewDir, 'index.html'), 'utf8');
  const errors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', (error) => errors.push(`jsdomError: ${error.message}`));
  virtualConsole.on('error', (...args) => errors.push(`console.error: ${args.join(' ')}`));

  const dom = new JSDOM(html, {
    runScripts: 'outside-only',
    pretendToBeVisual: true,
    virtualConsole,
    url: 'http://localhost:8080/',
  });
  const { window } = dom;

  // jsdom does not expose TextEncoder/TextDecoder on the window object while
  // every real browser does (the engine prefers them over Buffer).
  window.TextEncoder = globalThis.TextEncoder;
  window.TextDecoder = globalThis.TextDecoder;

  // jsdom's Blob has no arrayBuffer(); real browsers do. Minimal stand-in.
  class FakeBlob {
    constructor(parts = [], options = {}) {
      this.chunks = parts.map((part) =>
        typeof part === 'string'
          ? new TextEncoder().encode(part)
          : new Uint8Array(part.buffer ?? part, part.byteOffset ?? 0, part.byteLength ?? part.length)
      );
      this.type = options.type ?? '';
    }

    get size() {
      return this.chunks.reduce((total, chunk) => total + chunk.length, 0);
    }

    async arrayBuffer() {
      const out = new Uint8Array(this.size);
      let offset = 0;
      for (const chunk of this.chunks) {
        out.set(chunk, offset);
        offset += chunk.length;
      }
      return out.buffer;
    }
  }
  window.Blob = FakeBlob;

  window.HTMLCanvasElement.prototype.getContext = function getContext() {
    return fakeContext(this, window.ImageData);
  };
  window.HTMLCanvasElement.prototype.toBlob = function toBlob(cb) {
    // A structurally valid (if empty) JPEG shell: SOI + EOI.
    cb(new window.Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xd9])], { type: 'image/jpeg' }));
  };
  window.HTMLCanvasElement.prototype.toDataURL = () => 'data:image/png;base64,iVBORw0KGgo=';
  window.createImageBitmap = async () => ({ width: 640, height: 420, close() {} });
  window.URL.createObjectURL = () => 'blob:stub';
  window.URL.revokeObjectURL = () => {};
  // Use the *window's* timers so window.close() really stops the radar animation
  // loop; a Node-native timer would outlive the DOM and hang the test runner.
  window.requestAnimationFrame = (cb) => window.setTimeout(() => cb(16), 0);
  window.cancelAnimationFrame = (id) => window.clearTimeout(id);
  window.HTMLAnchorElement.prototype.click = function noop() {};
  Object.defineProperty(window.navigator, 'clipboard', {
    value: { writeText: async () => {} },
    configurable: true,
  });

  for (const file of ['crypto-core.js', 'png.js', 'jpeg-meta.js', 'mock.js', 'stego-engine.js', 'app.js']) {
    window.eval(fs.readFileSync(path.join(previewDir, 'js', file), 'utf8'));
  }

  const doc = window.document;
  const $ = (selector) => doc.querySelector(selector);
  const $$ = (selector) => Array.from(doc.querySelectorAll(selector));
  const click = (element) => element.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  const type = (element, value) => {
    element.value = value;
    element.dispatchEvent(new window.Event('input', { bubbles: true }));
  };
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  return { window, dom, doc, $, $$, click, type, wait, errors };
}

test('browser UI: three tabs, scrub, embed, reveal, wrong password', { skip: !JSDOM && 'jsdom not installed (npm install)' }, async () => {
  const { window, $, $$, click, type, wait, errors } = await boot();
  await wait(60);

  // ---- tabs
  for (const [tab, title] of [
    ['encode', 'Stego Encoder'],
    ['decode', 'Stego Decoder'],
    ['exif', 'Exif Scrub & Share'],
  ]) {
    click(window.document.querySelector(`.tab[data-tab="${tab}"]`));
    assert.equal($('#crumbTitle').textContent.trim(), title);
    assert.ok($(`#panel-${tab}`).classList.contains('is-active'));
  }

  // ---- mock photo audit
  click($('#exifMock'));
  await wait(500);
  const rows = $$('#metaTableBody tr');
  assert.ok(rows.length >= 30, `expected a rich metadata table, got ${rows.length} rows`);
  assert.match($('#gpsCoords').textContent, /^30\.04440°, 31\.23570°$/);
  assert.equal($('#gpsStatus').textContent.trim(), 'located');
  assert.ok($('#exifStats').textContent.includes('sensitive'));

  // ---- scrub
  click($('#btnScrub'));
  await wait(500);
  assert.equal($$('.stripped-chip').length, rows.length, 'every row must be marked STRIPPED');
  assert.equal($('#scrubVerdict').textContent.trim(), 'verified clean');
  assert.equal($('#gpsStatus').textContent.trim(), 'pin destroyed');
  assert.ok($$('#scrubReportList li').length >= 5, 'scrub report must list what was removed');
  assert.equal($('#btnDownloadClean').disabled, false, 'export must unlock after a scrub');

  // ---- encoder
  click(window.document.querySelector('.tab[data-tab="encode"]'));
  click($('#coverMock'));
  await wait(250);
  assert.match($('#coverDims').textContent, /1024×768/);
  assert.ok($('#capMax').textContent.includes('B'));

  type($('#payloadText'), 'Meet at 30.0444, 31.2357 — bring the drive.');
  type($('#encodePassword'), 'correct horse battery staple');
  await wait(30);
  assert.equal($('#btnEmbed').disabled, false);

  click($('#btnEmbed'));
  await wait(4000);
  assert.equal($('#embedResult').hidden, false, 'embed result panel must open');
  const stego = window.SGVApp.state.stego;
  assert.ok(stego && stego.bytes.length > 1000);
  assert.ok(!Number.isNaN(stego.diff.psnr));
  assert.ok(stego.diff.maxDelta <= 1, '1-bit mode may not deviate by more than 1/255');

  // ---- decoder with a real container
  click(window.document.querySelector('.tab[data-tab="decode"]'));
  click($('#decodeMock'));
  await wait(4000);
  assert.ok($('#detectBadge').textContent.includes('SGV1'));
  assert.equal($('#decodePassword').value, 'stegovault');

  click($('#btnReveal'));
  await wait(4000);
  assert.equal($('#authChip').textContent.trim(), 'tag verified');
  assert.equal($('#decodeOutput').hidden, false);
  assert.ok($('#outText').textContent.includes('Vault note'));

  // ---- wrong password must be rejected deterministically
  type($('#decodePassword'), 'definitely-wrong');
  click($('#btnReveal'));
  await wait(4000);
  assert.equal($('#authChip').textContent.trim(), 'wrong passphrase');
  assert.equal($('#decodeOutput').hidden, true);
  assert.match($('#statusText').textContent, /rejected/i);

  assert.deepEqual(errors, [], 'the UI must not raise any runtime error');

  // Tear the DOM down: jsdom timers (map animation, toasts) would otherwise keep
  // the test process alive.
  window.close();
});

test('preview assets: stylesheet parses and every script loads', { skip: !JSDOM && 'jsdom not installed (npm install)' }, async () => {
  const css = fs.readFileSync(path.join(previewDir, 'css', 'style.css'), 'utf8');
  assert.equal((css.match(/{/g) ?? []).length, (css.match(/}/g) ?? []).length, 'unbalanced CSS braces');
  assert.ok(css.includes('#0b0d12') || css.includes('#0B0D12'), 'obsidian canvas colour missing');
  assert.ok(css.includes('#14b8a6'), 'neon teal accent missing');
  assert.ok(css.includes('#f59e0b'), 'security amber accent missing');

  const { errors, window } = await boot();
  assert.deepEqual(errors, []);
  window.close();
});

test('every element id referenced by app.js exists in index.html', async () => {
  const html = fs.readFileSync(path.join(previewDir, 'index.html'), 'utf8');
  const js = fs.readFileSync(path.join(previewDir, 'js', 'app.js'), 'utf8');
  const ids = new Set(Array.from(html.matchAll(/id="([^"]+)"/g)).map((m) => m[1]));
  const used = new Set(Array.from(js.matchAll(/\$\('#([A-Za-z0-9_-]+)'\)/g)).map((m) => m[1]));
  const missing = [...used].filter((id) => !ids.has(id));
  assert.deepEqual(missing, [], `app.js references unknown ids: ${missing.join(', ')}`);
});
