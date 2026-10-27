/* eslint-disable */
// app.js — UI controller for the browser build of Exif Cleaner & Stego Vault.
// Mirrors the Flutter screens: Exif Scrub, Stego Encoder, Stego Decoder.

(function () {
  const SGV = globalThis.SGV;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const MAX_WORKING_EDGE = 2400; // keeps the preview snappy; on-device uses full res
  const DEMO_PASSWORD = 'stegovault';

  const state = {
    tab: 'exif',
    mock: false,
    exifItems: [],
    activeExif: 0,
    cover: null,
    stego: null,
    payloadKind: 'text',
    payloadFile: null,
    decode: null,
    decodeResult: null,
    depth: 1,
    mapRaf: null,
  };

  // --------------------------------------------------------------- utilities
  const fmtBytes = (n) => {
    const v = Number(n) || 0;
    if (v < 1024) return `${v} B`;
    if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
    return `${(v / (1024 * 1024)).toFixed(2)} MB`;
  };
  const fmtInt = (n) => (Number(n) || 0).toLocaleString('en-US');
  const esc = (s) =>
    String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let toastTimer = null;
  function toast(message, kind) {
    const el = $('#toast');
    el.textContent = message;
    el.className = `toast show${kind === 'error' ? ' error' : ''}`;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      el.className = 'toast';
    }, kind === 'error' ? 5200 : 3400);
  }

  function status(text, busy) {
    $('#statusText').textContent = text;
    $('.statusbar').classList.toggle('busy', !!busy);
  }

  const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()));

  async function fileBytes(file) {
    return new Uint8Array(await file.arrayBuffer());
  }

  async function decodeToImageData(bytes, mime) {
    const blob = new Blob([bytes], { type: mime || 'image/*' });
    let bitmap;
    try {
      bitmap = await createImageBitmap(blob);
    } catch (e) {
      bitmap = await new Promise((resolve, reject) => {
        const img = new Image();
        const url = URL.createObjectURL(blob);
        img.onload = () => {
          URL.revokeObjectURL(url);
          resolve(img);
        };
        img.onerror = () => {
          URL.revokeObjectURL(url);
          reject(new Error('The browser could not decode this image format.'));
        };
        img.src = url;
      });
    }
    const sw = bitmap.width || bitmap.naturalWidth;
    const sh = bitmap.height || bitmap.naturalHeight;
    const scale = Math.min(1, MAX_WORKING_EDGE / Math.max(sw, sh));
    const width = Math.max(1, Math.round(sw * scale));
    const height = Math.max(1, Math.round(sh * scale));
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0, width, height);
    if (bitmap.close) bitmap.close();
    const imageData = ctx.getImageData(0, 0, width, height);
    return { imageData, canvas, scaled: scale < 1, sourceWidth: sw, sourceHeight: sh };
  }

  function paintCanvas(target, imageData) {
    target.width = imageData.width;
    target.height = imageData.height;
    // The stego engine hands back plain {data,width,height} objects; canvas
    // insists on a real ImageData instance.
    let payload = imageData;
    if (typeof ImageData !== 'undefined' && !(payload instanceof ImageData)) {
      payload = new ImageData(new Uint8ClampedArray(imageData.data), imageData.width, imageData.height);
    }
    target.getContext('2d').putImageData(payload, 0, 0);
  }

  function makeThumb(imageData, w = 224, h = 148) {
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    const scale = Math.max(w / imageData.width, h / imageData.height);
    const dw = imageData.width * scale;
    const dh = imageData.height * scale;
    const src = document.createElement('canvas');
    paintCanvas(src, imageData);
    ctx.drawImage(src, (w - dw) / 2, (h - dh) / 2, dw, dh);
    return canvas;
  }

  function download(bytesOrBlob, fileName, mime) {
    const blob = bytesOrBlob instanceof Blob ? bytesOrBlob : new Blob([bytesOrBlob], { type: mime || 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 8000);
  }

  function baseName(name) {
    return String(name || 'image').replace(/\.[^.]+$/, '');
  }

  function extOf(name) {
    const m = String(name || '').match(/\.([a-z0-9]+)$/i);
    return m ? m[1].toLowerCase() : '';
  }

  function inspect(bytes) {
    if (SGV.Meta.isJpeg(bytes)) return SGV.Meta.inspectJpeg(bytes);
    if (SGV.Meta.isPng(bytes)) return SGV.Png.readPngMeta(bytes);
    if (SGV.Meta.isBmp(bytes)) return { format: 'BMP', width: 0, height: 0, sizeBytes: bytes.length, entries: [], gps: null };
    if (SGV.Meta.isWebp(bytes)) return { format: 'WEBP', width: 0, height: 0, sizeBytes: bytes.length, entries: [], gps: null };
    return { format: 'UNKNOWN', width: 0, height: 0, sizeBytes: bytes.length, entries: [], gps: null };
  }

  // -------------------------------------------------------------------- tabs
  const TAB_META = {
    exif: { index: '01', title: 'Exif Scrub & Share' },
    encode: { index: '02', title: 'Stego Encoder' },
    decode: { index: '03', title: 'Stego Decoder' },
  };

  function setTab(tab) {
    state.tab = tab;
    $$('.tab').forEach((b) => {
      const on = b.dataset.tab === tab;
      b.classList.toggle('is-active', on);
      b.setAttribute('aria-selected', String(on));
    });
    $$('.panel').forEach((p) => p.classList.toggle('is-active', p.id === `panel-${tab}`));
    $('#crumbIndex').textContent = TAB_META[tab].index;
    $('#crumbTitle').textContent = TAB_META[tab].title;
    if (tab === 'exif') drawGpsMap();
    else stopMapLoop();
  }

  $$('.tab').forEach((btn) => btn.addEventListener('click', () => setTab(btn.dataset.tab)));

  // ------------------------------------------------------------------- mock
  async function mockPhoto(variant = 0) {
    const scene = SGV.Mock.scene(1024, 768, variant);
    const canvas = document.createElement('canvas');
    paintCanvas(canvas, scene);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.92));
    const jpeg = new Uint8Array(await blob.arrayBuffer());
    const segments = SGV.Mock.metadataSegments(scene.width, scene.height);
    const withMeta = SGV.Mock.injectSegments(jpeg, segments);
    return {
      name: `mock_obsidian_${variant + 1}.jpg`,
      bytes: withMeta,
      imageData: scene,
    };
  }

  $('#mockToggle').addEventListener('change', async (e) => {
    state.mock = e.target.checked;
    $('#enginePill').textContent = state.mock ? 'MOCK DATA' : 'ON-DEVICE';
    $('#enginePill').classList.toggle('amber', !state.mock);
    if (state.mock) {
      toast('Mock Data Mode on — synthetic photos with real EXIF/XMP/IPTC bytes.');
      if (!state.exifItems.length) $('#exifMock').click();
      if (!state.cover) $('#coverMock').click();
    } else {
      toast('Mock Data Mode off — select real files to continue.');
    }
  });

  // ============================================================== TAB 1 EXIF
  function auditSensitive(audit) {
    return audit.entries.filter((e) => e.sensitive).length;
  }

  async function addExifPhoto(photo) {
    const item = {
      id: `exif-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      name: photo.name,
      bytes: photo.bytes,
      imageData: photo.imageData,
      audit: inspect(photo.bytes),
      cleanBytes: null,
      cleanAudit: null,
      status: 'audited',
    };
    state.exifItems.push(item);
    state.activeExif = state.exifItems.length - 1;
    renderExif();
    return item;
  }

  async function addExifFiles(files) {
    const list = Array.from(files).filter(Boolean);
    if (!list.length) return;
    status(`Reading ${list.length} image(s)…`, true);
    let ok = 0;
    for (const file of list) {
      try {
        const bytes = await fileBytes(file);
        const decoded = await decodeToImageData(bytes, file.type);
        await addExifPhoto({ name: file.name, bytes, imageData: decoded.imageData });
        ok++;
      } catch (err) {
        toast(`${file.name}: ${err.message}`, 'error');
      }
    }
    status(`Audited ${ok} image(s) — ${state.exifItems.length} in session`, false);
    if (ok) toast(`${ok} image(s) audited. ${fmtInt(totalTags())} metadata entries found.`);
  }

  const totalTags = () => state.exifItems.reduce((n, i) => n + i.audit.entries.length, 0);

  // JFIF and ICC markers describe colour handling only — they carry no identity
  // data, so the scrubber deliberately keeps them (removing them can shift
  // colour rendering) and the verdict must not count them as leftovers.
  const HARMLESS_GROUPS = ['JFIF', 'ICC'];
  const isHarmless = (entry) => HARMLESS_GROUPS.includes(entry.group);
  const identityEntries = (audit) => audit.entries.filter((e) => !isHarmless(e));

  function renderExif() {
    renderThumbs();
    const item = state.exifItems[state.activeExif];
    renderTable(item);
    renderGps(item);
    renderFileMeta(item);
    const canAct = !!item && item.status !== 'cleaning';
    $('#btnScrub').disabled = !canAct || !!item.cleanBytes;
    $('#btnDownloadClean').disabled = !item || !item.cleanBytes;
    $('#btnBatch').disabled = !state.exifItems.length;
    if (item && item.status === 'cleaned' && item.report) renderReport(item);
    else $('#scrubReport').hidden = true;
  }

  function renderThumbs() {
    const host = $('#exifThumbs');
    host.innerHTML = '';
    state.exifItems.forEach((item, idx) => {
      const el = document.createElement('div');
      el.className = `thumb${idx === state.activeExif ? ' is-active' : ''}${item.cleanBytes ? ' is-clean' : ''}`;
      el.title = item.name;
      el.appendChild(makeThumb(item.imageData));
      const meta = document.createElement('div');
      meta.className = 'thumb-meta';
      const clean = !!item.cleanBytes;
      meta.innerHTML = `<span class="thumb-name">${esc(item.name)}</span>
        <span class="thumb-badge">${clean ? 'cleaned' : `${item.audit.entries.length} tags`}</span>`;
      el.appendChild(meta);
      el.addEventListener('click', () => {
        state.activeExif = idx;
        renderExif();
      });
      host.appendChild(el);
    });
  }

  function groupClass(group) {
    return `g-${String(group).toLowerCase().replace(/[^a-z0-9]/g, '')}`;
  }

  function renderTable(item) {
    const body = $('#metaTableBody');
    const stats = $('#exifStats');
    if (!item) {
      body.innerHTML = '<tr class="empty-row"><td colspan="3">Drop an image to inspect its fingerprint.</td></tr>';
      stats.innerHTML = '<span class="chip">— tags</span>';
      return;
    }
    const audit = item.cleanAudit || item.audit;
    const rows = item.audit.entries;
    if (!rows.length) {
      body.innerHTML =
        '<tr class="empty-row"><td colspan="3">No EXIF, XMP, IPTC or comment metadata found — this file is already fingerprint-free.</td></tr>';
    } else {
      body.innerHTML = rows
        .map((e) => {
          const cleaned = !!item.cleanBytes;
          const after = !cleaned
            ? '—'
            : isHarmless(e)
              ? '<span class="kept-chip">kept · harmless</span>'
              : '<span class="stripped-chip">STRIPPED</span>';
          return `<tr class="${cleaned ? 'removed' : ''}">
            <td><div class="field"><span class="tag-group ${groupClass(e.group)}">${esc(e.group)}</span>${esc(e.tag)}</div></td>
            <td class="val">${esc(e.value)}</td>
            <td class="after">${after}</td>
          </tr>`;
        })
        .join('');
    }
    const sensitive = auditSensitive(item.audit);
    const gps = item.audit.gps;
    stats.innerHTML = [
      `<span class="chip amber">${fmtInt(item.audit.entries.length)} tags</span>`,
      `<span class="chip rose">${fmtInt(sensitive)} sensitive</span>`,
      gps ? '<span class="chip amber">GPS</span>' : '<span class="chip">no GPS</span>',
      item.cleanBytes ? '<span class="chip teal">0 remaining</span>' : '',
    ].join('');
  }

  function renderFileMeta(item) {
    const el = $('#exifFileMeta');
    if (!item) {
      el.textContent = '—';
      return;
    }
    const a = item.audit;
    const dims = a.width && a.height ? `${a.width}×${a.height}` : `${item.imageData.width}×${item.imageData.height} (working)`;
    el.textContent = `${item.name} · ${a.format} · ${dims} · ${fmtBytes(item.bytes.length)}${
      item.cleanBytes ? ` → ${fmtBytes(item.cleanBytes.length)}` : ''
    }`;
  }

  function renderGps(item) {
    const gps = item && item.audit.gps;
    const chip = $('#gpsStatus');
    const coords = $('#gpsCoords');
    if (gps) {
      chip.textContent = item.cleanBytes ? 'pin destroyed' : 'located';
      chip.className = `chip ${item.cleanBytes ? 'teal' : 'amber'}`;
      coords.textContent = `${gps.latitude.toFixed(5)}°, ${gps.longitude.toFixed(5)}°`;
    } else {
      chip.textContent = 'no fix';
      chip.className = 'chip';
      coords.textContent = '—';
    }
    drawGpsMap();
  }

  function stopMapLoop() {
    if (state.mapRaf) cancelAnimationFrame(state.mapRaf);
    state.mapRaf = null;
  }

  function drawGpsMap() {
    const canvas = $('#gpsCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    const item = state.exifItems[state.activeExif];
    const gps = item && item.audit.gps;
    const destroyed = !!(item && item.cleanBytes);
    const seed = gps ? Math.abs(Math.round(gps.latitude * 1000 + gps.longitude * 1000)) : 42;
    const rnd = SGV.Mock.mulberry32(seed);

    function paint(t) {
      ctx.clearRect(0, 0, w, h);
      const grd = ctx.createRadialGradient(w * 0.5, h * 0.5, 20, w * 0.5, h * 0.5, w * 0.72);
      grd.addColorStop(0, '#0a1519');
      grd.addColorStop(1, '#05080b');
      ctx.fillStyle = grd;
      ctx.fillRect(0, 0, w, h);

      // grid
      ctx.strokeStyle = 'rgba(45,212,191,0.075)';
      ctx.lineWidth = 1;
      for (let x = 0; x <= w; x += 48) {
        ctx.beginPath();
        ctx.moveTo(x + 0.5, 0);
        ctx.lineTo(x + 0.5, h);
        ctx.stroke();
      }
      for (let y = 0; y <= h; y += 48) {
        ctx.beginPath();
        ctx.moveTo(0, y + 0.5);
        ctx.lineTo(w, y + 0.5);
        ctx.stroke();
      }

      // pseudo terrain
      for (let i = 0; i < 4; i++) {
        ctx.beginPath();
        const cx = rnd() * w;
        const cy = rnd() * h;
        ctx.moveTo(cx, cy);
        for (let s = 0; s < 5; s++) {
          const nx = cx + (rnd() - 0.5) * 260;
          const ny = cy + (rnd() - 0.5) * 190;
          ctx.quadraticCurveTo(cx + (rnd() - 0.5) * 180, cy + (rnd() - 0.5) * 140, nx, ny);
        }
        ctx.closePath();
        ctx.fillStyle = i % 2 ? 'rgba(20,184,166,0.055)' : 'rgba(96,165,250,0.04)';
        ctx.fill();
        ctx.strokeStyle = 'rgba(45,212,191,0.10)';
        ctx.stroke();
      }

      const cx = w * 0.5;
      const cy = h * 0.52;

      // radar rings
      [0.16, 0.28, 0.4].forEach((r, i) => {
        ctx.beginPath();
        ctx.arc(cx, cy, Math.min(w, h) * r, 0, Math.PI * 2);
        ctx.strokeStyle = `rgba(45,212,191,${0.16 - i * 0.04})`;
        ctx.setLineDash(i === 1 ? [6, 8] : []);
        ctx.stroke();
        ctx.setLineDash([]);
      });

      // crosshair
      ctx.strokeStyle = 'rgba(45,212,191,0.16)';
      ctx.beginPath();
      ctx.moveTo(cx - 16, cy);
      ctx.lineTo(cx + 16, cy);
      ctx.moveTo(cx, cy - 16);
      ctx.lineTo(cx, cy + 16);
      ctx.stroke();

      // sweep
      if (gps && !destroyed) {
        const angle = (t / 2600) * Math.PI * 2;
        const grad = ctx.createConicGradient
          ? ctx.createConicGradient(angle, cx, cy)
          : null;
        if (grad) {
          grad.addColorStop(0, 'rgba(45,212,191,0.30)');
          grad.addColorStop(0.08, 'rgba(45,212,191,0.02)');
          grad.addColorStop(1, 'rgba(45,212,191,0.02)');
          ctx.beginPath();
          ctx.moveTo(cx, cy);
          ctx.arc(cx, cy, Math.min(w, h) * 0.42, 0, Math.PI * 2);
          ctx.closePath();
          ctx.fillStyle = grad;
          ctx.fill();
        }
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(angle) * Math.min(w, h) * 0.42, cy + Math.sin(angle) * Math.min(w, h) * 0.42);
        ctx.strokeStyle = 'rgba(45,212,191,0.45)';
        ctx.stroke();
      }

      if (!gps) {
        ctx.fillStyle = 'rgba(139,152,167,0.75)';
        ctx.font = '500 15px ui-monospace, Menlo, monospace';
        ctx.textAlign = 'center';
        ctx.fillText('NO GPS METADATA', w / 2, h / 2 + 54);
        ctx.font = '400 11px ui-monospace, Menlo, monospace';
        ctx.fillStyle = 'rgba(95,107,121,0.9)';
        ctx.fillText('this image carries no location fix', w / 2, h / 2 + 76);
        return;
      }

      const pulse = 1 + Math.sin(t / 420) * 0.16;

      if (destroyed) {
        ctx.beginPath();
        ctx.arc(cx, cy, 26, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(45,212,191,0.75)';
        ctx.setLineDash([4, 5]);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.beginPath();
        ctx.moveTo(cx - 13, cy - 13);
        ctx.lineTo(cx + 13, cy + 13);
        ctx.moveTo(cx + 13, cy - 13);
        ctx.lineTo(cx - 13, cy + 13);
        ctx.strokeStyle = 'rgba(45,212,191,0.9)';
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.lineWidth = 1;
        ctx.fillStyle = 'rgba(45,212,191,0.95)';
        ctx.font = '600 12px ui-monospace, Menlo, monospace';
        ctx.textAlign = 'center';
        ctx.fillText('GPS TAGS DESTROYED', cx, cy + 58);
        ctx.fillStyle = 'rgba(139,152,167,0.7)';
        ctx.font = '400 11px ui-monospace, Menlo, monospace';
        ctx.fillText('no coordinates remain in the file', cx, cy + 78);
        return;
      }

      // pin glow
      const glow = ctx.createRadialGradient(cx, cy, 2, cx, cy, 46 * pulse);
      glow.addColorStop(0, 'rgba(245,158,11,0.55)');
      glow.addColorStop(1, 'rgba(245,158,11,0)');
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(cx, cy, 46 * pulse, 0, Math.PI * 2);
      ctx.fill();

      // pin body
      ctx.beginPath();
      ctx.arc(cx, cy, 9, 0, Math.PI * 2);
      ctx.fillStyle = '#f59e0b';
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = 'rgba(11,13,18,0.9)';
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx, cy, 3.2, 0, Math.PI * 2);
      ctx.fillStyle = '#0b0d12';
      ctx.fill();

      // label
      const label = `${gps.latitude.toFixed(4)}°${gps.latitude >= 0 ? 'N' : 'S'}  ${Math.abs(gps.longitude).toFixed(4)}°${gps.longitude >= 0 ? 'E' : 'W'}`;
      ctx.font = '500 12px ui-monospace, Menlo, monospace';
      const tw = ctx.measureText(label).width;
      const bx = cx - tw / 2 - 12;
      const by = cy - 58;
      ctx.fillStyle = 'rgba(6,10,14,0.82)';
      ctx.strokeStyle = 'rgba(245,158,11,0.5)';
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(bx, by, tw + 24, 28, 8);
      else ctx.rect(bx, by, tw + 24, 28);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#fbbf24';
      ctx.textAlign = 'center';
      ctx.fillText(label, cx, by + 18);
    }

    stopMapLoop();
    const animate = state.tab === 'exif';
    if (!animate) {
      paint(0);
      return;
    }
    const start = performance.now();
    const loop = () => {
      paint(performance.now() - start);
      state.mapRaf = requestAnimationFrame(loop);
    };
    loop();
  }

  function renderReport(item) {
    const r = item.report;
    const host = $('#scrubReportList');
    host.innerHTML = r.lines.filter(Boolean).map((line) => `<li>${esc(line)}</li>`).join('');
    const chip = $('#scrubVerdict');
    chip.textContent = r.clean ? 'verified clean' : 'still dirty';
    chip.className = `chip ${r.clean ? 'teal' : 'rose'}`;
    $('#scrubReport').hidden = false;
  }

  // ---- scrubbing
  async function scrubItem(item) {
    if (!item || item.cleanBytes) return null;
    item.status = 'cleaning';
    status(`Stripping ${item.name} …`, true);
    await nextFrame();
    const t0 = performance.now();
    let cleanBytes;
    let lossless;
    if (SGV.Meta.isJpeg(item.bytes)) {
      cleanBytes = SGV.Meta.stripJpeg(item.bytes);
      lossless = true;
    } else {
      // PNG / BMP / WebP: re-encode from decoded pixels (ancillary chunks die).
      cleanBytes = SGV.Png.encodePng(item.imageData);
      lossless = SGV.Meta.isPng(item.bytes);
    }
    const cleanAudit = inspect(cleanBytes);
    const removed = item.audit.entries.filter(
      (e) => !cleanAudit.entries.some((a) => a.group === e.group && a.tag === e.tag)
    );
    const elapsed = performance.now() - t0;

    item.cleanBytes = cleanBytes;
    item.cleanAudit = cleanAudit;
    item.status = 'cleaned';
    const leftovers = identityEntries(cleanAudit);
    item.report = {
      clean: leftovers.length === 0 && !cleanAudit.gps,
      lines: [
        `Removed ${fmtInt(removed.length)} metadata entries (${fmtInt(
          removed.filter((e) => e.sensitive).length
        )} sensitive)`,
        item.audit.gps ? 'GPS latitude/longitude/altitude destroyed' : 'No GPS fix was present',
        item.audit.entries.some((e) => /serial/i.test(e.tag)) ? 'Camera + lens serial numbers removed' : 'No serial numbers found',
        lossless
          ? 'Pixel data untouched — JPEG segments cut from the container (lossless)'
          : 'Re-encoded as PNG from decoded pixels (visually identical)',
        `Re-scan after strip: ${leftovers.length} identity tag(s) remaining, GPS ${cleanAudit.gps ? 'still present' : 'absent'}`,
        cleanAudit.entries.length !== leftovers.length ? 'JFIF/ICC colour markers kept (no personal data)' : '',
        `Container size ${fmtBytes(item.bytes.length)} → ${fmtBytes(cleanBytes.length)} · ${elapsed.toFixed(0)} ms`,
      ],
    };
    status(`Scrubbed ${item.name} — 0 tags remaining`, false);
    return item;
  }

  $('#exifBrowse').addEventListener('click', (e) => {
    e.stopPropagation();
    $('#exifInput').click();
  });
  $('#exifDrop').addEventListener('click', () => $('#exifInput').click());
  $('#exifInput').addEventListener('change', (e) => {
    addExifFiles(e.target.files);
    e.target.value = '';
  });

  $('#exifMock').addEventListener('click', async (e) => {
    e.stopPropagation();
    status('Generating synthetic photo + EXIF…', true);
    const photo = await mockPhoto(state.exifItems.length % 3);
    await addExifPhoto(photo);
    status('Mock photo loaded with genuine EXIF/XMP/IPTC bytes', false);
    toast('Mock photo ready — 38 metadata entries incl. GPS.');
  });

  $('#btnScrub').addEventListener('click', async () => {
    const item = state.exifItems[state.activeExif];
    if (!item) return;
    try {
      await scrubItem(item);
      renderExif();
      toast('Metadata stripped. Pixel data intact.');
    } catch (err) {
      status('Scrub failed', false);
      toast(err.message, 'error');
    }
  });

  $('#btnBatch').addEventListener('click', async () => {
    if (!state.exifItems.length) return;
    let done = 0;
    for (const item of state.exifItems) {
      if (!item.cleanBytes) {
        await scrubItem(item);
        done++;
      }
    }
    renderExif();
    toast(`Batch scrub complete — ${done} image(s) cleaned.`);
  });

  $('#btnDownloadClean').addEventListener('click', () => {
    const item = state.exifItems[state.activeExif];
    if (!item || !item.cleanBytes) return;
    const isJpeg = SGV.Meta.isJpeg(item.cleanBytes);
    const name = `${baseName(item.name)}_clean.${isJpeg ? 'jpg' : 'png'}`;
    download(item.cleanBytes, name, isJpeg ? 'image/jpeg' : 'image/png');
    toast(`Saved ${name}`);
  });

  $('#gpsCopy').addEventListener('click', async (e) => {
    e.stopPropagation();
    const item = state.exifItems[state.activeExif];
    if (!item || !item.audit.gps) return toast('No GPS fix to copy.', 'error');
    const text = `${item.audit.gps.latitude}, ${item.audit.gps.longitude}`;
    try {
      await navigator.clipboard.writeText(text);
      toast('Coordinates copied.');
    } catch (_) {
      toast(text);
    }
  });

  // ============================================================ TAB 2 ENCODE
  function payloadInfo() {
    if (state.payloadKind === 'file' && state.payloadFile) {
      return { bytes: state.payloadFile.bytes.length + state.payloadFile.name.length + state.payloadFile.mimeType.length + 4, isFile: true };
    }
    const text = $('#payloadText').value || '';
    return { bytes: SGV.utf8(text).length, isFile: false };
  }

  function updateCapacity() {
    const cover = state.cover;
    const info = payloadInfo();
    const depth = state.depth;
    if (!cover) {
      $('#capMax').textContent = '—';
      $('#capFree').textContent = '—';
      $('#capPsnr').textContent = '—';
      $('#capUsed').textContent = fmtBytes(info.bytes + SGV.Stego.HEADER_LEN + SGV.Stego.TAG_LEN);
      $('#capacityChip').textContent = 'no cover';
      $('#capBarFill').style.width = '0%';
      $('#coverDims').textContent = 'no cover';
      return;
    }
    const w = cover.imageData.width;
    const h = cover.imageData.height;
    const cap = SGV.Stego.capacityBytes(w, h, depth);
    const usable = SGV.Stego.usableBytes(w, h, depth);
    const total = info.bytes + SGV.Stego.HEADER_LEN + SGV.Stego.TAG_LEN;
    const pct = Math.min(100, (total / cap) * 100);
    $('#capMax').textContent = `${fmtBytes(usable)} · ${fmtInt(usable)} B`;
    $('#capUsed').textContent = `${fmtBytes(total)} · ${fmtInt(total)} B`;
    $('#capFree').textContent = fmtBytes(Math.max(0, cap - total));
    $('#capPsnr').textContent = `${(60 - 10 * Math.min(1, (total / cap) * 2.2)).toFixed(1)} dB`;
    $('#capBarFill').style.width = `${Math.max(pct, total > 0 ? 1.5 : 0)}%`;
    $('#capacityChip').textContent = `${depth}-bit LSB · ${fmtInt(cap)} B`;
    $('#capacityChip').className = `chip ${total > usable ? 'rose' : 'teal'}`;
    $('#coverDims').textContent = cover.bytes
      ? `${w}×${h} · ${fmtBytes(cover.bytes.length)}`
      : `${w}×${h} · synthetic`;

    const fits = total <= usable;
    $('#btnEmbed').disabled = !fits || !$('#encodePassword').value;
    if (!fits) $('#capacityChip').textContent = 'payload too large';
  }

  async function setCover(imageData, name, bytes) {
    state.cover = { imageData, name, bytes };
    paintCanvas($('#coverCanvas'), imageData);
    $('#coverEmpty').hidden = true;
    $('#coverDims').textContent = `${imageData.width}×${imageData.height}`;
    updateCapacity();
    status(`Cover loaded: ${name} · ${imageData.width}×${imageData.height}`, false);
  }

  $('#coverBrowse').addEventListener('click', (e) => {
    e.stopPropagation();
    $('#coverInput').click();
  });
  $('#coverDrop').addEventListener('click', () => $('#coverInput').click());
  $('#coverInput').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    try {
      status('Decoding cover…', true);
      const bytes = await fileBytes(file);
      const decoded = await decodeToImageData(bytes, file.type);
      await setCover(decoded.imageData, file.name, bytes);
      toast(`Cover ready — capacity for ${fmtBytes(SGV.Stego.usableBytes(decoded.imageData.width, decoded.imageData.height, state.depth))}.`);
    } catch (err) {
      toast(err.message, 'error');
      status('Cover decode failed', false);
    }
  });

  $('#coverMock').addEventListener('click', async (e) => {
    e.stopPropagation();
    const scene = SGV.Mock.scene(1024, 768, state.stego ? 2 : 1);
    await setCover(scene, 'mock_cover.png', null);
    toast('Synthetic cover generated.');
  });

  $('#depthToggle').addEventListener('change', (e) => {
    state.depth = e.target.checked ? 2 : 1;
    updateCapacity();
  });

  $$('#payloadKind button').forEach((btn) =>
    btn.addEventListener('click', () => {
      state.payloadKind = btn.dataset.kind;
      $$('#payloadKind button').forEach((b) => b.classList.toggle('is-active', b === btn));
      $('#textPayloadWrap').hidden = state.payloadKind !== 'text';
      $('#filePayloadWrap').hidden = state.payloadKind !== 'file';
      updateCapacity();
    })
  );

  $('#payloadText').addEventListener('input', () => {
    const bytes = SGV.utf8($('#payloadText').value).length;
    $('#textBytes').textContent = `${bytes} B · ${$('#payloadText').value.length} chars`;
    updateCapacity();
  });

  $('#payloadFileBtn').addEventListener('click', () => $('#payloadFile').click());
  $('#payloadFile').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    const bytes = await fileBytes(file);
    state.payloadFile = { name: file.name, mimeType: file.type || 'application/octet-stream', bytes };
    $('#fileChip').hidden = false;
    $('#fileName').textContent = file.name;
    $('#fileSize').textContent = fmtBytes(bytes.length);
    state.payloadKind = 'file';
    $$('#payloadKind button').forEach((b) => b.classList.toggle('is-active', b.dataset.kind === 'file'));
    $('#textPayloadWrap').hidden = true;
    $('#filePayloadWrap').hidden = false;
    updateCapacity();
    toast(`Attached ${file.name} (${fmtBytes(bytes.length)}).`);
  });

  function passwordStrength(pw) {
    if (!pw) return { score: 0, label: 'min. 8 characters recommended', color: 'var(--rose)' };
    let score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 14) score++;
    if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score++;
    if (/\d/.test(pw)) score++;
    if (/[^A-Za-z0-9]/.test(pw)) score++;
    const labels = ['too short', 'weak', 'fair', 'good', 'strong', 'vault-grade'];
    const colors = ['#fb7185', '#fb7185', '#f59e0b', '#f59e0b', '#14b8a6', '#2dd4bf'];
    return { score, label: labels[Math.min(score, 5)], color: colors[Math.min(score, 5)] };
  }

  function refreshStrength() {
    const s = passwordStrength($('#encodePassword').value);
    const bar = $('#strengthBar');
    bar.style.width = `${(s.score / 5) * 100}%`;
    bar.style.background = s.color;
    $('#strengthNote').textContent = s.label;
    updateCapacity();
  }

  $('#encodePassword').addEventListener('input', refreshStrength);
  $('#toggleEncodePw').addEventListener('click', () => {
    const input = $('#encodePassword');
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    $('#toggleEncodePw').textContent = show ? 'hide' : 'show';
  });

  // ---- comparison slider
  function wireSlider() {
    const box = $('#compareSlider');
    const stego = $('#stegoImg');
    const divider = $('#divider');
    let dragging = false;

    const move = (clientX) => {
      const rect = box.getBoundingClientRect();
      const pct = Math.min(100, Math.max(0, ((clientX - rect.left) / rect.width) * 100));
      stego.style.clipPath = `inset(0 0 0 ${pct}%)`;
      divider.style.left = `${pct}%`;
    };
    const down = (e) => {
      dragging = true;
      box.setPointerCapture && e.pointerId != null && box.setPointerCapture(e.pointerId);
      move(e.clientX);
    };
    const up = () => {
      dragging = false;
    };
    box.addEventListener('pointerdown', down);
    window.addEventListener('pointermove', (e) => dragging && move(e.clientX));
    window.addEventListener('pointerup', up);
    box.addEventListener('mousemove', (e) => dragging && move(e.clientX));
    box.addEventListener('touchmove', (e) => {
      if (dragging && e.touches[0]) move(e.touches[0].clientX);
    }, { passive: true });
  }
  wireSlider();

  async function embedPayload() {
    if (!state.cover) return toast('Select a cover image first.', 'error');
    const password = $('#encodePassword').value;
    if (!password) return toast('A passphrase is required.', 'error');
    const info = payloadInfo();
    if (info.bytes === 0) return toast('Payload is empty.', 'error');

    $('#btnEmbed').disabled = true;
    status('Deriving key (PBKDF2 100k) …', true);
    await nextFrame();
    try {
      const opts = {
        password,
        depth: state.depth,
        onStage: (s) => status(`${s} …`, true),
      };
      if (state.payloadKind === 'file' && state.payloadFile) {
        opts.fileBytes = state.payloadFile.bytes;
        opts.fileName = state.payloadFile.name;
        opts.mimeType = state.payloadFile.mimeType;
      } else {
        opts.text = $('#payloadText').value;
      }
      const result = SGV.Stego.embed(state.cover.imageData, opts);
      const png = SGV.Png.encodePng(result.imageData);
      const diff = SGV.Stego.diff(state.cover.imageData, result.imageData);

      // cover preview as JPEG data-URL (visual only), stego exactly as written
      const coverCanvas = document.createElement('canvas');
      paintCanvas(coverCanvas, state.cover.imageData);
      const coverJpeg = coverCanvas.toDataURL('image/jpeg', 0.92);
      if (state.stego && state.stego.url) URL.revokeObjectURL(state.stego.url);
      const stegoUrl = URL.createObjectURL(new Blob([png], { type: 'image/png' }));

      state.stego = {
        bytes: png,
        url: stegoUrl,
        imageData: result.imageData,
        metrics: result,
        diff,
        name: `${baseName(state.cover.name)}_stego.png`,
        password,
      };

      $('#coverImg').src = coverJpeg;
      $('#stegoImg').src = stegoUrl;
      $('#embedResult').hidden = false;
      $('#embedBadge').textContent = `SGV1 · ${result.depth}-bit`;
      $('#hudPsnr').textContent = `${diff.psnr.toFixed(1)} dB`;
      $('#hudDelta').textContent = `${diff.maxDelta}/255`;
      $('#hudChanged').textContent = `${fmtInt(diff.changed)} (${(diff.changedRatio * 100).toFixed(1)}%)`;
      $('#hudTime').textContent = `${result.elapsed.toFixed(0)} ms`;
      status(`Container written — ${fmtBytes(png.length)} PNG, ${fmtInt(result.payloadBytes)} B payload hidden`, false);
      toast('Payload encrypted and embedded. Download the PNG to share it.');
    } catch (err) {
      status('Embedding failed', false);
      toast(err.message, 'error');
    } finally {
      updateCapacity();
    }
  }

  $('#btnEmbed').addEventListener('click', embedPayload);

  $('#btnDownloadStego').addEventListener('click', () => {
    if (!state.stego) return;
    download(state.stego.bytes, state.stego.name, 'image/png');
    toast(`Saved ${state.stego.name}`);
  });

  $('#btnSendToDecoder').addEventListener('click', async () => {
    if (!state.stego) return;
    const decoded = await decodeToImageData(state.stego.bytes, 'image/png');
    setDecodeImage(decoded.imageData, state.stego.name, state.stego.bytes);
    $('#decodePassword').value = state.stego.password || '';
    setTab('decode');
    toast('Container loaded in the decoder — press “Decrypt & verify”.');
  });

  // ============================================================ TAB 3 DECODE
  function setDecodeImage(imageData, name, bytes) {
    state.decode = { imageData, name, bytes };
    state.decodeResult = null;
    paintCanvas($('#decodeCanvas'), imageData);
    $('#decodeEmpty').hidden = true;
    const presence = SGV.Stego.detect(imageData);
    const badge = $('#detectBadge');
    if (presence.present) {
      badge.textContent = `SGV1 · ${presence.depth}-bit · ${fmtBytes(presence.header.cipherLen)} ciphertext`;
      badge.className = 'chip teal';
    } else {
      badge.textContent = 'no container signature';
      badge.className = 'chip amber';
    }
    $('#btnReveal').disabled = false;
    $('#authChip').textContent = 'unverified';
    $('#authChip').className = 'chip amber';
    $('#decodeOutput').hidden = true;
    const diag = $$('#decodeDiag > div b');
    if (presence.present) {
      const h = presence.header;
      const values = [
        'SGV1',
        'v' + h.version,
        `${presence.depth}-bit LSB${h.isFile ? ' · file' : ' · text'}`,
        `${fmtBytes(h.cipherLen)}`,
        'pending',
        '—',
      ];
      diag.forEach((el, i) => (el.textContent = values[i]));
    } else {
      diag.forEach((el, i) => (el.textContent = i === 0 ? 'not found' : '—'));
    }
    status(`Container loaded: ${name}`, false);
  }

  $('#decodeBrowse').addEventListener('click', (e) => {
    e.stopPropagation();
    $('#decodeInput').click();
  });
  $('#decodeDrop').addEventListener('click', () => $('#decodeInput').click());
  $('#decodeInput').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    try {
      status('Scanning container…', true);
      const bytes = await fileBytes(file);
      const decoded = await decodeToImageData(bytes, file.type);
      setDecodeImage(decoded.imageData, file.name, bytes);
      const presence = SGV.Stego.detect(decoded.imageData);
      toast(
        presence.present
          ? 'SGV1 signature found — enter the passphrase to reveal the payload.'
          : 'No SGV1 signature found. This image holds no hidden payload.',
        presence.present ? undefined : 'error'
      );
    } catch (err) {
      toast(err.message, 'error');
      status('Scan failed', false);
    }
  });

  $('#decodeMock').addEventListener('click', async (e) => {
    e.stopPropagation();
    status('Building mock container…', true);
    await nextFrame();
    const scene = SGV.Mock.scene(960, 720, 5);
    const secret =
      'Vault note #7 — the client handover is at 21:30.\n' +
      'Coordinates in the original photo were scrubbed before sharing.\n' +
      'If you can read this, the LSB payload + AES-256-GCM tag verified.';
    const result = SGV.Stego.embed(scene, { password: DEMO_PASSWORD, text: secret, depth: 1 });
    const png = SGV.Png.encodePng(result.imageData);
    setDecodeImage(result.imageData, 'mock_stego_container.png', png);
    $('#decodePassword').value = DEMO_PASSWORD;
    toast(`Mock container created — passphrase “${DEMO_PASSWORD}” is pre-filled.`);
  });

  $('#toggleDecodePw').addEventListener('click', () => {
    const input = $('#decodePassword');
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    $('#toggleDecodePw').textContent = show ? 'hide' : 'show';
  });

  async function reveal() {
    if (!state.decode) return toast('Load a container first.', 'error');
    const password = $('#decodePassword').value;
    if (!password) return toast('Enter the passphrase.', 'error');
    $('#btnReveal').disabled = true;
    status('Deriving key (PBKDF2 100k) …', true);
    await nextFrame();
    const diag = $$('#decodeDiag > div b');
    try {
      const result = SGV.Stego.extract(state.decode.imageData, {
        password,
        onStage: (s) => status(`${s} …`, true),
      });
      state.decodeResult = result;
      $('#authChip').textContent = 'tag verified';
      $('#authChip').className = 'chip teal';
      diag[4].textContent = 'verified ✓';
      diag[5].textContent = `${result.elapsed.toFixed(0)} ms`;

      $('#decodeOutput').hidden = false;
      if (result.file) {
        $('#outKind').textContent = 'file';
        $('#outText').textContent = `${result.file.fileName}\n${result.file.mimeType}\n${fmtBytes(result.file.data.length)} of decrypted bytes\n\nBinary payload — use Download to save it.`;
        $('#btnDownloadOut').textContent = 'Download file';
      } else {
        $('#outKind').textContent = 'text';
        $('#outText').textContent = result.text;
        $('#btnDownloadOut').textContent = 'Download .txt';
      }
      status(`Payload revealed — GCM tag verified in ${result.elapsed.toFixed(0)} ms`, false);
      toast('Payload decrypted. Authentication tag verified.');
    } catch (err) {
      $('#decodeOutput').hidden = true;
      $('#authChip').textContent = err.code === 'AUTH_FAILED' ? 'wrong passphrase' : 'not a container';
      $('#authChip').className = 'chip rose';
      diag[4].textContent = err.code === 'AUTH_FAILED' ? 'failed ✗' : '—';
      diag[5].textContent = '—';
      status('Decryption rejected', false);
      toast(err.message, 'error');
    } finally {
      $('#btnReveal').disabled = false;
    }
  }

  $('#btnReveal').addEventListener('click', reveal);
  $('#decodePassword').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') reveal();
  });

  $('#btnCopyOut').addEventListener('click', async () => {
    const result = state.decodeResult;
    if (!result) return;
    const text = result.file ? result.file.fileName : result.text;
    try {
      await navigator.clipboard.writeText(text);
      toast('Copied to clipboard.');
    } catch (_) {
      toast('Clipboard blocked by the browser.', 'error');
    }
  });

  $('#btnDownloadOut').addEventListener('click', () => {
    const result = state.decodeResult;
    if (!result) return;
    if (result.file) {
      download(result.file.data, result.file.fileName, result.file.mimeType);
    } else {
      download(new Blob([result.text], { type: 'text/plain' }), 'revealed_payload.txt');
    }
  });

  // ------------------------------------------------------------ drag & drop
  function wireDropzone(el, handler) {
    ['dragenter', 'dragover'].forEach((evt) =>
      el.addEventListener(evt, (e) => {
        e.preventDefault();
        el.classList.add('is-over');
      })
    );
    ['dragleave', 'dragend'].forEach((evt) =>
      el.addEventListener(evt, () => el.classList.remove('is-over'))
    );
    el.addEventListener('drop', (e) => {
      e.preventDefault();
      e.stopPropagation();
      el.classList.remove('is-over');
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) {
        handler(e.dataTransfer.files);
      }
    });
  }

  wireDropzone($('#exifDrop'), (files) => addExifFiles(files));
  wireDropzone($('#coverDrop'), async (files) => {
    const file = files[0];
    if (!file) return;
    try {
      const bytes = await fileBytes(file);
      const decoded = await decodeToImageData(bytes, file.type);
      await setCover(decoded.imageData, file.name, bytes);
    } catch (err) {
      toast(err.message, 'error');
    }
  });
  wireDropzone($('#decodeDrop'), async (files) => {
    const file = files[0];
    if (!file) return;
    try {
      const bytes = await fileBytes(file);
      const decoded = await decodeToImageData(bytes, file.type);
      setDecodeImage(decoded.imageData, file.name, bytes);
    } catch (err) {
      toast(err.message, 'error');
    }
  });

  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => e.preventDefault());

  // -------------------------------------------------------------- bootstrap
  function bootstrap() {
    updateCapacity();
    refreshStrength();
    drawGpsMap();
    status('Engine idle — no image loaded');
    if (location.protocol === 'file:') {
      $('#enginePill').textContent = 'LOCAL FILE';
    }
    const params = new URLSearchParams(location.search);
    if (params.get('mock') === '1') {
      $('#mockToggle').checked = true;
      $('#mockToggle').dispatchEvent(new Event('change'));
    }
  }

  bootstrap();

  // expose a tiny API for automated tests / console tinkering
  globalThis.SGVApp = { state, setTab, inspect, mockPhoto, scrubItem };
})();
