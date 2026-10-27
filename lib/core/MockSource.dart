// MockSource.dart
//
// "Mock Data Mode" generator. Emulators and CI boxes have empty galleries, so
// the app can synthesise a realistic *photograph* together with a genuine
// EXIF/XMP/IPTC-bearing JPEG. Nothing here is faked at the API level: the bytes
// produced are parsed by the exact same JpegMeta reader used for real files, so
// scrubbing demos exercise the production code path end-to-end.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'JpegMeta.dart';

class MockPhoto {
  const MockPhoto({
    required this.image,
    required this.jpegBytes,
    required this.fileName,
    required this.gps,
  });

  final img.Image image;
  final Uint8List jpegBytes;
  final String fileName;
  final GpsPoint gps;
}

class MockSource {
  MockSource({this.seed = 0x5EED});

  /// Changing the seed produces a different scene + grain pattern.
  final int seed;

  /// Deterministic procedural "photo": dusk sky, sun, mountains, reflective lake
  /// and film grain (the grain matters — it gives the LSB plane natural entropy).
  img.Image coverImage({int width = 1024, int height = 768, int variant = 0}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final rnd = Random(seed + variant * 977);
    final horizon = (height * 0.58).round();

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        int r, g, b;
        if (y < horizon) {
          final t = y / horizon;
          r = (14 + 150 * t * t).round();
          g = (26 + 96 * t * t).round();
          b = (46 + 120 * (1 - t)).round();
          // sun
          final dx = x - width * (0.72 + variant * 0.03);
          final dy = y - horizon * 0.36;
          final d = sqrt(dx * dx + dy * dy);
          final sun = max(0.0, 1 - d / (height * 0.17));
          r = (r + 190 * sun * sun).clamp(0, 255).round();
          g = (g + 150 * sun * sun).clamp(0, 255).round();
          b = (b + 80 * sun * sun).clamp(0, 255).round();
          // mountains
          final ridge = horizon * 0.78 +
              sin(x / (58.0 + variant * 6)) * 26 +
              sin(x / 19.0 + 1.7) * 9;
          if (y > ridge) {
            final shade = 0.42 + 0.2 * sin(x / 40.0);
            r = (32 * shade + 10).round();
            g = (46 * shade + 16).round();
            b = (58 * shade + 22).round();
          }
        } else {
          final t = (y - horizon) / (height - horizon);
          final shimmer = sin(x / 11.0 + y / 5.0) * 6;
          r = (14 + 46 * t + shimmer).clamp(0, 255).round();
          g = (58 + 52 * t + shimmer).clamp(0, 255).round();
          b = (86 + 60 * t + shimmer * 2).clamp(0, 255).round();
          final sunPath = (x - width * 0.72).abs();
          if (sunPath < width * 0.09 && (y ~/ 6) % 3 == 0) {
            r = (r + 90).clamp(0, 255).round();
            g = (g + 80).clamp(0, 255).round();
            b = (b + 40).clamp(0, 255).round();
          }
        }
        // film grain -> entropy for the LSB plane
        final n = rnd.nextInt(7) - 3;
        image.setPixelRgba(
          x,
          y,
          (r + n).clamp(0, 255),
          (g + n).clamp(0, 255),
          (b + n).clamp(0, 255),
          255,
        );
      }
    }

    // A couple of foreground silhouettes make the preview slider obvious.
    _drawSail(image, (width * 0.26).round(), (height * 0.70).round(), 34 + variant * 4);
    return image;
  }

  void _drawSail(img.Image image, int cx, int cy, int s) {
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final sail = y > s * 0.15 && x < (s - y) * 0.9 && x > s * 0.15;
        final hull = y > s * 0.72 && (x - s / 2).abs() < s * 0.45;
        if (!sail && !hull) continue;
        final px = cx + x, py = cy + y;
        if (px < 0 || py < 0 || px >= image.width || py >= image.height) continue;
        image.setPixelRgba(px, py, 8, 12, 18, 255);
      }
    }
  }

  /// Synthesises a JPEG whose APP1/APP13/COM segments really contain EXIF, XMP
  /// and a comment — so the scrubber and the comparison table have data to chew
  /// on even on a fresh emulator.
  MockPhoto photo({int variant = 0, int width = 1024, int height = 768}) {
    final image = coverImage(width: width, height: height, variant: variant);
    final encoded = img.encodeJpg(image.convert(numChannels: 3), quality: 92);
    final segments = buildMetadataSegments(width: width, height: height);
    final soi = Uint8List.fromList(<int>[0xFF, 0xD8]);
    final merged = Uint8List.fromList(<int>[
      ...soi,
      ...segments,
      ...encoded.sublist(2),
    ]);
    return MockPhoto(
      image: image,
      jpegBytes: merged,
      fileName: 'mock_obsidian_${variant + 1}.jpg',
      gps: const GpsPoint(30.0444, 31.2357), // Giza, the "before" pin
    );
  }

  /// Builds APP1(EXIF), APP1(XMP), APP13(IPTC) and COM segments.
  Uint8List buildMetadataSegments({int width = 1024, int height = 768}) {
    final builder = BytesBuilder(copy: false);

    final exif = _buildExifTiff(width: width, height: height);
    final app1 = <int>[...ascii.encode('Exif'), 0, 0, ...exif];
    builder.add(_segment(0xE1, app1));

    final xmp = '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
        'xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" '
        'xmlns:aux="http://ns.adobe.com/exif/1.0/aux/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:tiff="http://ns.adobe.com/tiff/1.0/" '
        'xmp:CreatorTool="VaultCam 4.2.1" '
        'xmp:CreateDate="2026-03-14T11:22:31+02:00" '
        'photoshop:SerialNumber="SN-7741-BX9" '
        'aux:SerialNumber="SN-7741-BX9" '
        'xmpMM:DocumentID="xmp.did:9d4f11ab-77c2-4c1e-9a10-2cbf10e8f0a1" '
        'tiff:Make="ObsidianCam" tiff:Model="SG-7 Pro">'
        '<dc:creator><rdf:Seq><rdf:li>Layla Hassan</rdf:li></rdf:Seq></dc:creator>'
        '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
    final xmpHeader = 'http://ns.adobe.com/xap/1.0/\u0000';
    builder.add(_segment(0xE1, <int>[...ascii.encode(xmpHeader), ...utf8.encode(xmp)]));

    // IPTC-IIM dataset block (resource 0x0404 inside an 8BIM Photoshop block).
    final iptc = <int>[
      ..._iptcDataset(0x50, 'Layla Hassan'),
      ..._iptcDataset(0x5A, 'Giza'),
      ..._iptcDataset(0x65, 'Egypt'),
      ..._iptcDataset(0x78, 'client site'),
    ];
    final photoshop = <int>[
      ...ascii.encode('Photoshop 3.0'), 0,
      ...ascii.encode('8BIM'), 0x04, 0x04, 0x00, 0x00,
      ..._u32(iptc.length), ...iptc,
      if (iptc.length.isOdd) 0,
    ];
    builder.add(_segment(0xED, photoshop));

    builder.add(_segment(0xFE, utf8.encode('shot for client site - do not share')));

    return builder.toBytes();
  }

  // ------------------------------------------------------------- TIFF writer

  Uint8List _buildExifTiff({required int width, required int height}) {
    final ifd0 = <_Tag>[
      _Tag.ascii(0x010F, 'ObsidianCam'),
      _Tag.ascii(0x0110, 'SG-7 Pro'),
      _Tag.short(0x0112, <int>[1]),
      _Tag.rational(0x011A, <List<int>>[[300, 1]]),
      _Tag.rational(0x011B, <List<int>>[[300, 1]]),
      _Tag.short(0x0128, <int>[2]),
      _Tag.ascii(0x0131, 'VaultCam 4.2.1'),
      _Tag.ascii(0x0132, '2026:03:14 11:22:31'),
      _Tag.ascii(0x013B, 'Layla Hassan'),
      _Tag.long(0x8769, <int>[0]), // Exif IFD offset (patched)
      _Tag.long(0x8825, <int>[0]), // GPS IFD offset (patched)
    ];
    final exif = <_Tag>[
      _Tag.rational(0x829A, <List<int>>[[1, 250]]),
      _Tag.rational(0x829D, <List<int>>[[28, 10]]),
      _Tag.short(0x8827, <int>[400]),
      _Tag.ascii(0x9003, '2026:03:14 11:22:31'),
      _Tag.long(0xA002, <int>[width]),
      _Tag.long(0xA003, <int>[height]),
      _Tag.ascii(0xA430, 'layla@example.com'),
      _Tag.ascii(0xA431, 'SN-7741-BX9'),
      _Tag.ascii(0xA434, 'Obsidian 24-70 f2.8'),
      _Tag.ascii(0xA435, 'LS-9920-QQ'),
    ];
    final gps = <_Tag>[
      _Tag.ascii(0x0001, 'N'),
      _Tag.rational(0x0002, <List<int>>[[30, 1], [2, 1], [39840, 1000]]),
      _Tag.ascii(0x0003, 'E'),
      _Tag.rational(0x0004, <List<int>>[[31, 1], [14, 1], [852, 100]]),
      _Tag.short(0x0005, <int>[0]),
      _Tag.rational(0x0006, <List<int>>[[34, 1]]),
      _Tag.ascii(0x001D, '2026:03:14'),
    ];

    final ifd0Size = 2 + ifd0.length * 12 + 4;
    final ifd0Blob = ifd0.fold<int>(0, (sum, t) => sum + t.blobLength);
    final exifStart = _align2(8 + ifd0Size + ifd0Blob);
    final exifSize = 2 + exif.length * 12 + 4;
    final exifBlob = exif.fold<int>(0, (sum, t) => sum + t.blobLength);
    final gpsStart = _align2(exifStart + exifSize + exifBlob);
    final gpsSize = 2 + gps.length * 12 + 4;
    final gpsBlob = gps.fold<int>(0, (sum, t) => sum + t.blobLength);
    final total = _align2(gpsStart + gpsSize + gpsBlob);

    // Patch the sub-IFD pointers.
    ifd0.firstWhere((t) => t.tag == 0x8769).setLong(exifStart);
    ifd0.firstWhere((t) => t.tag == 0x8825).setLong(gpsStart);

    final out = Uint8List(total);
    out[0] = 0x49; // II
    out[1] = 0x49;
    _putU16(out, 2, 0x002A);
    _putU32(out, 4, 8);

    _writeIfd(out, 8, ifd0, 8 + ifd0Size);
    _writeIfd(out, exifStart, exif, exifStart + exifSize);
    _writeIfd(out, gpsStart, gps, gpsStart + gpsSize);
    return out;
  }

  void _writeIfd(Uint8List out, int start, List<_Tag> tags, int blobStart) {
    _putU16(out, start, tags.length);
    var cursor = start + 2;
    var blobCursor = blobStart;
    for (final tag in tags) {
      _putU16(out, cursor, tag.tag);
      _putU16(out, cursor + 2, tag.type);
      _putU32(out, cursor + 4, tag.count);
      final payload = tag.bytes;
      if (payload.length <= 4) {
        out.setRange(cursor + 8, cursor + 8 + payload.length, payload);
      } else {
        _putU32(out, cursor + 8, blobCursor);
        out.setRange(blobCursor, blobCursor + payload.length, payload);
        blobCursor += payload.length;
        if (payload.length.isOdd) blobCursor++;
      }
      cursor += 12;
    }
    _putU32(out, cursor, 0); // no next IFD
  }

  static int _align2(int v) => v.isOdd ? v + 1 : v;

  /// IPTC-IIM dataset: 0x1C | record 2 | dataset | uint16 length | value.
  static List<int> _iptcDataset(int dataset, String text) {
    final bytes = latin1.encode(text);
    return <int>[
      0x1C, 0x02, dataset,
      (bytes.length >> 8) & 0xFF, bytes.length & 0xFF,
      ...bytes,
    ];
  }

  static void _putU16(Uint8List out, int offset, int value) {
    out[offset] = (value >> 8) & 0xFF;
    out[offset + 1] = value & 0xFF;
  }

  static List<int> _u32(int value) => <int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  static void _putU32(Uint8List out, int offset, int value) {
    out[offset] = (value >> 24) & 0xFF;
    out[offset + 1] = (value >> 16) & 0xFF;
    out[offset + 2] = (value >> 8) & 0xFF;
    out[offset + 3] = value & 0xFF;
  }

  Uint8List _segment(int marker, List<int> payload) {
    final length = payload.length + 2;
    return Uint8List.fromList(<int>[
      0xFF,
      marker,
      (length >> 8) & 0xFF,
      length & 0xFF,
      ...payload,
    ]);
  }
}

class _Tag {
  _Tag._(this.tag, this.type, this.count, this.bytes);

  factory _Tag.ascii(int tag, String value) {
    final nullTerminated = <int>[...utf8.encode(value), 0];
    return _Tag._(tag, 2, nullTerminated.length, Uint8List.fromList(nullTerminated));
  }

  factory _Tag.short(int tag, List<int> values) {
    final b = Uint8List(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      b[i * 2] = (values[i] >> 8) & 0xFF;
      b[i * 2 + 1] = values[i] & 0xFF;
    }
    return _Tag._(tag, 3, values.length, b);
  }

  factory _Tag.long(int tag, List<int> values) {
    final b = Uint8List(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      final o = i * 4;
      b[o] = (values[i] >> 24) & 0xFF;
      b[o + 1] = (values[i] >> 16) & 0xFF;
      b[o + 2] = (values[i] >> 8) & 0xFF;
      b[o + 3] = values[i] & 0xFF;
    }
    return _Tag._(tag, 4, values.length, b);
  }

  factory _Tag.rational(int tag, List<List<int>> pairs) {
    final b = Uint8List(pairs.length * 8);
    for (var i = 0; i < pairs.length; i++) {
      final o = i * 8;
      final num = pairs[i][0];
      final den = pairs[i][1];
      b[o] = (num >> 24) & 0xFF;
      b[o + 1] = (num >> 16) & 0xFF;
      b[o + 2] = (num >> 8) & 0xFF;
      b[o + 3] = num & 0xFF;
      b[o + 4] = (den >> 24) & 0xFF;
      b[o + 5] = (den >> 16) & 0xFF;
      b[o + 6] = (den >> 8) & 0xFF;
      b[o + 7] = den & 0xFF;
    }
    return _Tag._(tag, 5, pairs.length, b);
  }

  final int tag;
  final int type;
  final int count;
  final Uint8List bytes;

  /// Rewrites a single LONG value in place (used for sub-IFD pointers).
  void setLong(int value) {
    bytes[0] = (value >> 24) & 0xFF;
    bytes[1] = (value >> 16) & 0xFF;
    bytes[2] = (value >> 8) & 0xFF;
    bytes[3] = value & 0xFF;
  }

  /// Out-of-line byte storage requirement (0 when the value fits inline).
  int get blobLength => bytes.length <= 4 ? 0 : (bytes.length.isOdd ? bytes.length + 1 : bytes.length);
}
