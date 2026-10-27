/* eslint-disable */
// mock.js — Mock Data Mode for the browser preview.
// Generates a procedurally shot "photograph" plus genuine EXIF / XMP / IPTC / COM
// segments, so the scrubber has real metadata to strip even with an empty device
// or when the user just wants to explore without picking files.

(function () {
  const SGV = (globalThis.SGV = globalThis.SGV || {});

  function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const clamp = (v) => (v < 0 ? 0 : v > 255 ? 255 : v | 0);

  /** Dusk sky, sun, mountain ridge, shimmering lake, sailboat + film grain. */
  function scene(width = 1024, height = 768, variant = 0, seed = 0x5eed) {
    const data = new Uint8ClampedArray(width * height * 4);
    const rnd = mulberry32(seed + variant * 977);
    const horizon = Math.round(height * 0.58);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        let r;
        let g;
        let b;
        if (y < horizon) {
          const t = y / horizon;
          r = 14 + 150 * t * t;
          g = 26 + 96 * t * t;
          b = 46 + 120 * (1 - t);
          const dx = x - width * (0.72 + variant * 0.03);
          const dy = y - horizon * 0.36;
          const d = Math.sqrt(dx * dx + dy * dy);
          const sun = Math.max(0, 1 - d / (height * 0.17));
          r += 190 * sun * sun;
          g += 150 * sun * sun;
          b += 80 * sun * sun;
          const ridge =
            horizon * 0.78 + Math.sin(x / (58 + variant * 6)) * 26 + Math.sin(x / 19 + 1.7) * 9;
          if (y > ridge) {
            const shade = 0.42 + 0.2 * Math.sin(x / 40);
            r = 32 * shade + 10;
            g = 46 * shade + 16;
            b = 58 * shade + 22;
          }
        } else {
          const t = (y - horizon) / (height - horizon);
          const shimmer = Math.sin(x / 11 + y / 5) * 6;
          r = 14 + 46 * t + shimmer;
          g = 58 + 52 * t + shimmer;
          b = 86 + 60 * t + shimmer * 2;
          if (Math.abs(x - width * 0.72) < width * 0.09 && Math.floor(y / 6) % 3 === 0) {
            r += 90;
            g += 80;
            b += 40;
          }
        }
        const n = (rnd() * 7) | 0;
        const grain = n - 3;
        const o = (y * width + x) * 4;
        data[o] = clamp(r + grain);
        data[o + 1] = clamp(g + grain);
        data[o + 2] = clamp(b + grain);
        data[o + 3] = 255;
      }
    }
    // foreground sailboat silhouette
    drawSail(data, width, height, Math.round(width * 0.26), Math.round(height * 0.7), 34 + variant * 4);
    return { data, width, height };
  }

  function drawSail(data, width, height, cx, cy, s) {
    for (let y = 0; y < s; y++) {
      for (let x = 0; x < s; x++) {
        const sail = y > s * 0.15 && x < (s - y) * 0.9 && x > s * 0.15;
        const hull = y > s * 0.72 && Math.abs(x - s / 2) < s * 0.45;
        if (!sail && !hull) continue;
        const px = cx + x;
        const py = cy + y;
        if (px < 0 || py < 0 || px >= width || py >= height) continue;
        const o = (py * width + px) * 4;
        data[o] = 8;
        data[o + 1] = 12;
        data[o + 2] = 18;
        data[o + 3] = 255;
      }
    }
  }

  // ------------------------------------------------------------- TIFF writer
  const BIG = false; // written little-endian ("II"), like most cameras

  function putU16(arr, o, v) {
    if (BIG) {
      arr[o] = (v >> 8) & 0xff;
      arr[o + 1] = v & 0xff;
    } else {
      arr[o] = v & 0xff;
      arr[o + 1] = (v >> 8) & 0xff;
    }
  }
  function putU32(arr, o, v) {
    if (BIG) {
      arr[o] = (v >>> 24) & 0xff;
      arr[o + 1] = (v >>> 16) & 0xff;
      arr[o + 2] = (v >>> 8) & 0xff;
      arr[o + 3] = v & 0xff;
    } else {
      arr[o] = v & 0xff;
      arr[o + 1] = (v >>> 8) & 0xff;
      arr[o + 2] = (v >>> 16) & 0xff;
      arr[o + 3] = (v >>> 24) & 0xff;
    }
  }

  const tagAscii = (tag, str) => {
    const bytes = new Uint8Array(str.length + 1);
    for (let i = 0; i < str.length; i++) bytes[i] = str.charCodeAt(i) & 0xff;
    return { tag, type: 2, count: bytes.length, bytes };
  };
  const tagShort = (tag, values) => {
    const bytes = new Uint8Array(values.length * 2);
    values.forEach((v, i) => putU16(bytes, i * 2, v));
    return { tag, type: 3, count: values.length, bytes };
  };
  const tagLong = (tag, values) => {
    const bytes = new Uint8Array(values.length * 4);
    values.forEach((v, i) => putU32(bytes, i * 4, v));
    return { tag, type: 4, count: values.length, bytes };
  };
  const tagRational = (tag, pairs) => {
    const bytes = new Uint8Array(pairs.length * 8);
    pairs.forEach((p, i) => {
      putU32(bytes, i * 8, p[0]);
      putU32(bytes, i * 8 + 4, p[1]);
    });
    return { tag, type: 5, count: pairs.length, bytes };
  };

  function blobLength(t) {
    return t.bytes.length <= 4 ? 0 : t.bytes.length + (t.bytes.length % 2);
  }
  const align2 = (v) => (v % 2 ? v + 1 : v);

  function writeIfd(out, start, tags, blobStart) {
    putU16(out, start, tags.length);
    let cursor = start + 2;
    let blob = blobStart;
    for (const t of tags) {
      putU16(out, cursor, t.tag);
      putU16(out, cursor + 2, t.type);
      putU32(out, cursor + 4, t.count);
      if (t.bytes.length <= 4) {
        out.set(t.bytes, cursor + 8);
      } else {
        putU32(out, cursor + 8, blob);
        out.set(t.bytes, blob);
        blob += t.bytes.length + (t.bytes.length % 2);
      }
      cursor += 12;
    }
    putU32(out, cursor, 0);
  }

  function buildExifTiff(width, height) {
    const ifd0 = [
      tagAscii(0x010f, 'ObsidianCam'),
      tagAscii(0x0110, 'SG-7 Pro'),
      tagShort(0x0112, [1]),
      tagRational(0x011a, [[300, 1]]),
      tagRational(0x011b, [[300, 1]]),
      tagShort(0x0128, [2]),
      tagAscii(0x0131, 'VaultCam 4.2.1'),
      tagAscii(0x0132, '2026:03:14 11:22:31'),
      tagAscii(0x013b, 'Layla Hassan'),
      tagLong(0x8769, [0]),
      tagLong(0x8825, [0]),
    ];
    const exif = [
      tagRational(0x829a, [[1, 250]]),
      tagRational(0x829d, [[28, 10]]),
      tagShort(0x8827, [400]),
      tagAscii(0x9003, '2026:03:14 11:22:31'),
      tagLong(0xa002, [width]),
      tagLong(0xa003, [height]),
      tagAscii(0xa430, 'layla@example.com'),
      tagAscii(0xa431, 'SN-7741-BX9'),
      tagAscii(0xa434, 'Obsidian 24-70 f2.8'),
      tagAscii(0xa435, 'LS-9920-QQ'),
    ];
    const gps = [
      tagAscii(0x0001, 'N'),
      tagRational(0x0002, [[30, 1], [2, 1], [39840, 1000]]),
      tagAscii(0x0003, 'E'),
      tagRational(0x0004, [[31, 1], [14, 1], [852, 100]]),
      tagShort(0x0005, [0]),
      tagRational(0x0006, [[34, 1]]),
      tagAscii(0x001d, '2026:03:14'),
    ];

    const size = (tags) => 2 + tags.length * 12 + 4;
    const blob = (tags) => tags.reduce((s, t) => s + blobLength(t), 0);

    const ifd0Start = 8;
    const exifStart = align2(ifd0Start + size(ifd0) + blob(ifd0));
    const gpsStart = align2(exifStart + size(exif) + blob(exif));
    const total = align2(gpsStart + size(gps) + blob(gps));

    ifd0.find((t) => t.tag === 0x8769).bytes = new Uint8Array(4);
    ifd0.find((t) => t.tag === 0x8825).bytes = new Uint8Array(4);
    putU32(ifd0.find((t) => t.tag === 0x8769).bytes, 0, exifStart);
    putU32(ifd0.find((t) => t.tag === 0x8825).bytes, 0, gpsStart);

    const out = new Uint8Array(total);
    out[0] = 0x49;
    out[1] = 0x49;
    putU16(out, 2, 0x002a);
    putU32(out, 4, 8);
    writeIfd(out, ifd0Start, ifd0, ifd0Start + size(ifd0));
    writeIfd(out, exifStart, exif, exifStart + size(exif));
    writeIfd(out, gpsStart, gps, gpsStart + size(gps));
    return out;
  }

  function segment(marker, payload) {
    const len = payload.length + 2;
    const out = new Uint8Array(len + 2);
    out[0] = 0xff;
    out[1] = marker;
    out[2] = (len >> 8) & 0xff;
    out[3] = len & 0xff;
    out.set(payload, 4);
    return out;
  }

  function concatBytes(list) {
    let total = 0;
    for (const a of list) total += a.length;
    const out = new Uint8Array(total);
    let o = 0;
    for (const a of list) {
      out.set(a, o);
      o += a.length;
    }
    return out;
  }

  const enc = (s) => SGV.utf8(s);

  /** IPTC-IIM dataset: marker | record 2 | dataset | 16-bit length | value. */
  function iptcDataset(dataset, text) {
    const bytes = enc(text);
    return new Uint8Array([
      0x1c, 0x02, dataset, (bytes.length >> 8) & 0xff, bytes.length & 0xff, ...bytes,
    ]);
  }

  function metadataSegments(width, height) {
    const exif = buildExifTiff(width, height);
    const app1 = concatBytes([enc('Exif'), new Uint8Array([0, 0]), exif]);

    const xmp =
      '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>' +
      '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">' +
      '<rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" ' +
      'xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" xmlns:aux="http://ns.adobe.com/exif/1.0/aux/" ' +
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" ' +
      'xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/" ' +
      'xmp:CreatorTool="VaultCam 4.2.1" xmp:CreateDate="2026-03-14T11:22:31+02:00" ' +
      'photoshop:SerialNumber="SN-7741-BX9" aux:SerialNumber="SN-7741-BX9" ' +
      'xmpMM:DocumentID="xmp.did:9d4f11ab-77c2-4c1e-9a10-2cbf10e8f0a1" ' +
      'tiff:Make="ObsidianCam" tiff:Model="SG-7 Pro">' +
      '<dc:creator><rdf:Seq><rdf:li>Layla Hassan</rdf:li></rdf:Seq></dc:creator></rdf:Description>' +
      '</rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
    const xmpApp1 = concatBytes([enc('http://ns.adobe.com/xap/1.0/'), new Uint8Array([0]), enc(xmp)]);

    const iptc = concatBytes([
      iptcDataset(0x50, 'Layla Hassan'),
      iptcDataset(0x5a, 'Giza'),
      iptcDataset(0x65, 'Egypt'),
      iptcDataset(0x78, 'client site'),
    ]);
    const ps = concatBytes([
      enc('Photoshop 3.0'),
      new Uint8Array([0]),
      enc('8BIM'),
      new Uint8Array([0x04, 0x04, 0x00, 0x00, (iptc.length >> 24) & 0xff, (iptc.length >> 16) & 0xff, (iptc.length >> 8) & 0xff, iptc.length & 0xff]),
      iptc,
      new Uint8Array(iptc.length % 2),
    ]);

    return concatBytes([
      segment(0xe1, app1),
      segment(0xe1, xmpApp1),
      segment(0xed, ps),
      segment(0xfe, enc('shot for client site - do not share')),
    ]);
  }

  /** Splices metadata segments directly after SOI, before the JFIF header. */
  function injectSegments(jpegBytes, segments) {
    if (jpegBytes[0] !== 0xff || jpegBytes[1] !== 0xd8) return jpegBytes;
    return concatBytes([jpegBytes.subarray(0, 2), segments, jpegBytes.subarray(2)]);
  }

  SGV.Mock = { scene, metadataSegments, injectSegments, buildExifTiff, mulberry32 };
})();
