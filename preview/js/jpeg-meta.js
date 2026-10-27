/* eslint-disable */
// jpeg-meta.js — byte-level EXIF/XMP/IPTC inspector and *lossless* JPEG scrubber.
// Browser port of lib/core/JpegMeta.dart. No pixels are ever re-encoded when a
// JPEG is stripped: metadata segments are cut out of the container and the
// entropy-coded scan is copied verbatim.

(function () {
  const SGV = (globalThis.SGV = globalThis.SGV || {});

  const u16 = (b, o, le) => (le ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1]);
  const u32 = (b, o, le) =>
    le
      ? (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0
      : ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;

  const ascii = (b, s, e) => {
    let out = '';
    for (let i = s; i < e; i++) out += String.fromCharCode(b[i]);
    return out;
  };

  const startsWith = (b, prefix, offset = 0) => {
    if (b.length < offset + prefix.length) return false;
    for (let i = 0; i < prefix.length; i++) if (b[offset + i] !== prefix.charCodeAt(i)) return false;
    return true;
  };

  const isJpeg = (b) => b.length > 3 && b[0] === 0xff && b[1] === 0xd8;
  const isPng = (b) =>
    b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47;
  const isBmp = (b) => b.length > 2 && b[0] === 0x42 && b[1] === 0x4d;
  const isWebp = (b) =>
    b.length > 12 && ascii(b, 0, 4) === 'RIFF' && ascii(b, 8, 12) === 'WEBP';

  const clip = (v) => (v.length > 120 ? v.slice(0, 120) + '…' : v);

  // ---------------------------------------------------------------- TIFF/EXIF
  const GPS_TAGS = {
    0: 'GPSVersionID', 1: 'GPSLatitudeRef', 2: 'GPSLatitude', 3: 'GPSLongitudeRef',
    4: 'GPSLongitude', 5: 'GPSAltitudeRef', 6: 'GPSAltitude', 7: 'GPSTimeStamp',
    8: 'GPSSatellites', 9: 'GPSStatus', 11: 'GPSDOP', 12: 'GPSSpeedRef',
    13: 'GPSSpeed', 16: 'GPSImgDirectionRef', 17: 'GPSImgDirection',
    23: 'GPSDestBearingRef', 24: 'GPSDestBearing', 29: 'GPSDateStamp',
    31: 'GPSHPositioningError',
  };
  const TAGS = {
    0x010e: 'ImageDescription', 0x010f: 'Make', 0x0110: 'Model', 0x0112: 'Orientation',
    0x011a: 'XResolution', 0x011b: 'YResolution', 0x0128: 'ResolutionUnit',
    0x0131: 'Software', 0x0132: 'DateTime', 0x013b: 'Artist', 0x8298: 'Copyright',
    0x9c9b: 'XPTitle', 0x9c9c: 'XPComment', 0x9c9d: 'XPAuthor', 0x9c9e: 'XPKeywords',
    0x829a: 'ExposureTime', 0x829d: 'FNumber', 0x8822: 'ExposureProgram', 0x8827: 'ISO',
    0x9003: 'DateTimeOriginal', 0x9004: 'DateTimeDigitized', 0x9201: 'ShutterSpeedValue',
    0x9202: 'ApertureValue', 0x9204: 'ExposureBias', 0x9207: 'MeteringMode', 0x9209: 'Flash',
    0x920a: 'FocalLength', 0x9286: 'UserComment', 0xa002: 'PixelXDimension',
    0xa003: 'PixelYDimension', 0xa402: 'ExposureMode', 0xa403: 'WhiteBalance',
    0xa405: 'FocalLengthIn35mm', 0xa420: 'ImageUniqueID', 0xa430: 'CameraOwnerName',
    0xa431: 'BodySerialNumber', 0xa432: 'LensSpecification', 0xa433: 'LensMake',
    0xa434: 'LensModel', 0xa435: 'LensSerialNumber',
  };

  const SENSITIVE = [
    'gps', 'serial', 'make', 'model', 'software', 'datetime', 'artist', 'copyright',
    'owner', 'imagedescription', 'usercomment', 'cameraowner',
  ];
  const isSensitive = (name) => SENSITIVE.some((k) => name.toLowerCase().includes(k));

  const TYPE_SIZE = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8 };

  function readTiff(bytes) {
    const entries = [];
    const subs = {};
    const raw = {};
    if (bytes.length < 8) return { entries, gps: null };
    const le = bytes[0] === 0x49 && bytes[1] === 0x49;
    if (u16(bytes, 2, le) !== 0x002a) return { entries, gps: null };
    const ifd0 = u32(bytes, 4, le);

    const readIfd = (offset, group, sink) => {
      if (!offset || offset + 2 > bytes.length) return 0;
      const count = u16(bytes, offset, le);
      if (count > 512) return 0;
      for (let n = 0; n < count; n++) {
        const e = offset + 2 + n * 12;
        if (e + 12 > bytes.length) break;
        const tag = u16(bytes, e, le);
        const type = u16(bytes, e + 2, le);
        const cnt = u32(bytes, e + 4, le);
        const vo = u32(bytes, e + 8, le);
        if (tag === 0x8769) subs.exif = vo;
        if (tag === 0x8825) subs.gps = vo;
        const size = TYPE_SIZE[type];
        if (!size) continue;
        const bytesLen = size * cnt;
        if (bytesLen <= 0 || bytesLen > 65536) continue;
        const start = bytesLen <= 4 ? e + 8 : vo;
        if (start + bytesLen > bytes.length) continue;
        const values = decodeValues(bytes, type, start, cnt, le);
        if (sink) sink[tag] = values;
        const name = group === 'GPS' ? GPS_TAGS[tag] : TAGS[tag];
        if (!name) continue;
        const rendered = render(type, values);
        if (!rendered.trim()) continue;
        entries.push({ group, tag: name, value: clip(rendered), sensitive: isSensitive(name) });
      }
      return count;
    };

    const n0 = readIfd(ifd0, 'IFD0', raw);
    if (subs.exif) readIfd(subs.exif, 'Exif', null);
    let gps = null;
    if (subs.gps) {
      const gpsRaw = {};
      readIfd(subs.gps, 'GPS', gpsRaw);
      gps = decodeGps(gpsRaw);
    }
    // IFD1 = embedded thumbnail, often carries its own copy of the EXIF.
    const ifd1 = u32(bytes, ifd0 + 2 + n0 * 12, le);
    if (ifd1 && ifd1 < bytes.length && ifd1 !== ifd0) {
      const thumb = [];
      const saved = entries.length;
      readIfd(ifd1, 'IFD1', null);
      for (let i = saved; i < entries.length; i++) thumb.push(entries[i]);
      entries.length = saved;
      entries.push(...thumb.slice(0, 6));
    }
    return { entries, gps };
  }

  function decodeValues(bytes, type, start, count, le) {
    const out = [];
    for (let i = 0; i < count; i++) {
      switch (type) {
        case 1:
        case 6:
        case 7:
          out.push(bytes[start + i]);
          break;
        case 2:
          out.push(bytes[start + i]);
          break;
        case 3:
        case 8:
          out.push(u16(bytes, start + i * 2, le));
          break;
        case 4:
        case 9:
          out.push(u32(bytes, start + i * 4, le));
          break;
        case 5:
        case 10: {
          const num = u32(bytes, start + i * 8, le);
          const den = u32(bytes, start + i * 8 + 4, le);
          out.push(den ? num / den : 0);
          break;
        }
        default:
          return out;
      }
    }
    return out;
  }

  function render(type, values) {
    if (type === 2) {
      let s = '';
      for (const v of values) {
        if (v === 0) break;
        s += String.fromCharCode(v);
      }
      return s.replace(/\0/g, '').trim();
    }
    if (values.length === 1) {
      const v = values[0];
      return Number.isInteger(v) ? String(v) : v.toFixed(4);
    }
    if (values.length <= 4) {
      return values.map((v) => (Number.isInteger(v) ? String(v) : v.toFixed(4))).join(', ');
    }
    return `${values.length} values (binary block)`;
  }

  function decodeGps(gpsRaw) {
    const lat = gpsRaw[2];
    const lon = gpsRaw[4];
    if (!lat || !lon || lat.length < 3 || lon.length < 3) return null;
    let latDec = lat[0] + lat[1] / 60 + lat[2] / 3600;
    let lonDec = lon[0] + lon[1] / 60 + lon[2] / 3600;
    const latRef = gpsRaw[1];
    const lonRef = gpsRaw[3];
    const ref = (arr) => (arr && arr.length ? String.fromCharCode(arr[0]) : '');
    if (ref(latRef) === 'S') latDec = -latDec;
    if (ref(lonRef) === 'W') lonDec = -lonDec;
    return { latitude: latDec, longitude: lonDec };
  }

  // ---------------------------------------------------------------- inspection
  function inspectJpeg(bytes) {
    const entries = [];
    let width = 0;
    let height = 0;
    let gps = null;
    let jfif = false;
    let i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] !== 0xff) {
        i++;
        continue;
      }
      let marker = bytes[i + 1];
      while (marker === 0xff && i + 2 < bytes.length) {
        i++;
        marker = bytes[i + 1];
      }
      i += 2;
      if (marker === 0xd8 || marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (marker === 0xda) {
        // Stop-of-scan: keep walking segments after the entropy data.
        i = skipScan(bytes, i);
        continue;
      }
      if (i + 1 >= bytes.length) break;
      const len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2 || i + len > bytes.length) break;
      const p = i + 2;
      const pe = i + len;

      if (marker === 0xe0 && startsWith(bytes, 'JFIF', p)) {
        jfif = true;
        entries.push({ group: 'JFIF', tag: 'Version', value: `${bytes[p + 5]}.${bytes[p + 6]}`, sensitive: false });
      } else if (marker === 0xe1 && startsWith(bytes, 'Exif', p)) {
        const tiff = bytes.subarray(p + 6, pe);
        const parsed = readTiff(tiff);
        entries.push(...parsed.entries);
        if (parsed.gps) gps = parsed.gps;
      } else if (marker === 0xe1 && startsWith(bytes, 'http://ns.adobe.com/xap/1.0/', p)) {
        const xml = ascii(bytes, p + 29, pe);
        entries.push(...extractXmp(xml));
      } else if (marker === 0xe2 && startsWith(bytes, 'ICC_PROFILE', p)) {
        entries.push({ group: 'ICC', tag: 'Profile', value: 'Embedded colour profile (harmless)', sensitive: false });
      } else if (marker === 0xe2 && startsWith(bytes, 'MPF', p)) {
        entries.push({ group: 'MPF', tag: 'Multi-Picture', value: 'Multi-picture index present', sensitive: true });
      } else if (marker === 0xed) {
        entries.push(...extractIptc(bytes.subarray(p, pe)));
      } else if (marker === 0xfe) {
        const text = ascii(bytes, p, pe).replace(/\0/g, '').trim();
        if (text) entries.push({ group: 'COMMENT', tag: 'UserComment', value: clip(text), sensitive: true });
      } else if (
        (marker >= 0xc0 && marker <= 0xcf) &&
        marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc &&
        p + 5 <= pe
      ) {
        height = (bytes[p + 1] << 8) | bytes[p + 2];
        width = (bytes[p + 3] << 8) | bytes[p + 4];
      }
      i = pe;
    }
    if (jfif && !entries.some((e) => e.group === 'JFIF')) {
      entries.push({ group: 'JFIF', tag: 'Marker', value: 'present', sensitive: false });
    }
    return { format: 'JPEG', width, height, sizeBytes: bytes.length, entries, gps };
  }

  function skipScan(bytes, i) {
    // i points just past the SOS marker; skip its header then entropy data.
    const len = (bytes[i] << 8) | bytes[i + 1];
    let j = i + len;
    while (j + 1 < bytes.length) {
      if (bytes[j] === 0xff) {
        const next = bytes[j + 1];
        if (next !== 0x00 && !(next >= 0xd0 && next <= 0xd7)) return j;
      }
      j++;
    }
    return bytes.length;
  }

  function extractXmp(xml) {
    const out = [];
    const patterns = [
      ['CreatorTool', /xmp:CreatorTool="([^"]+)"/],
      ['CreateDate', /xmp:CreateDate="([^"]+)"/],
      ['SerialNumber', /(?:photoshop|aux):SerialNumber="([^"]+)"/],
      ['DocumentID', /xmpMM:DocumentID="([^"]+)"/],
      ['Make', /tiff:Make="([^"]+)"/],
      ['Model', /tiff:Model="([^"]+)"/],
      ['Creator', /<dc:creator>[\s\S]*?<rdf:li[^>]*>([^<]+)<\/rdf:li>/],
    ];
    for (const [tag, re] of patterns) {
      const m = xml.match(re);
      if (m && m[1].trim()) out.push({ group: 'XMP', tag, value: clip(m[1].trim()), sensitive: true });
    }
    if (!out.length) out.push({ group: 'XMP', tag: 'Packet', value: 'XMP packet present (stripped)', sensitive: true });
    return out;
  }

  const IPTC_LABELS = {
    80: 'By-line (author)', 90: 'City', 92: 'Sub-location', 95: 'State', 101: 'Country',
    105: 'Headline', 110: 'Credit', 115: 'Source', 116: 'Copyright', 120: 'Caption',
  };

  function extractIptc(payload) {
    const out = [];
    for (let i = 0; i + 4 < payload.length; i++) {
      if (payload[i] === 0x1c && payload[i + 1] === 0x02) {
        const dataset = payload[i + 2];
        const len = (payload[i + 3] << 8) | payload[i + 4];
        const label = IPTC_LABELS[dataset];
        if (!label || len <= 0 || i + 5 + len > payload.length) continue;
        const value = ascii(payload, i + 5, i + 5 + len).replace(/\0/g, '').trim();
        if (value) out.push({ group: 'IPTC', tag: label, value: clip(value), sensitive: true });
        i += 4 + len;
      }
    }
    if (!out.length && ascii(payload, 0, Math.min(payload.length, 40)).includes('Photoshop')) {
      out.push({ group: 'IPTC', tag: 'Photoshop resource block', value: 'APP13 present (stripped)', sensitive: true });
    }
    return out;
  }

  // ------------------------------------------------------------------ scrubbing
  function stripJpeg(bytes) {
    if (!isJpeg(bytes)) return bytes;
    const parts = [new Uint8Array([0xff, 0xd8])];
    let i = 2;
    while (i < bytes.length) {
      if (bytes[i] !== 0xff) {
        parts.push(bytes.subarray(i));
        break;
      }
      const markerStart = i;
      let marker = bytes[i + 1];
      while (marker === 0xff && i + 2 < bytes.length) {
        i++;
        marker = bytes[i + 1];
      }
      const headerStart = i;
      i += 2;
      if (marker === 0xd9) {
        parts.push(bytes.subarray(headerStart, i));
        break;
      }
      if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
        parts.push(bytes.subarray(markerStart, i));
        continue;
      }
      if (marker === 0xda) {
        parts.push(bytes.subarray(markerStart));
        break;
      }
      if (i + 1 >= bytes.length) {
        parts.push(bytes.subarray(markerStart));
        break;
      }
      const len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2 || i + len > bytes.length) {
        parts.push(bytes.subarray(markerStart));
        break;
      }
      const p = i + 2;
      let drop = false;
      if (marker === 0xe1 || marker === 0xed || marker === 0xfe) drop = true;
      if (marker === 0xe2 && startsWith(bytes, 'MPF', p)) drop = true;
      if (!drop) parts.push(bytes.subarray(markerStart, i + len));
      i += len;
    }
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

  SGV.ExifTiff = { read: readTiff };
  SGV.Meta = {
    isJpeg,
    isPng,
    isBmp,
    isWebp,
    inspectJpeg,
    stripJpeg,
    ascii,
    startsWith,
    u16,
    u32,
  };
})();
