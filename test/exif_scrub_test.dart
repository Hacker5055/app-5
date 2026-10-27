// Unit tests for metadata inspection and lossless JPEG scrubbing.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stego_vault/core/ExifCleanerService.dart';
import 'package:stego_vault/core/JpegMeta.dart';
import 'package:stego_vault/core/MockSource.dart';

void main() {
  final mock = MockSource();
  final cleaner = ExifCleanerService();

  /// Builds a JPEG carrying EXIF / XMP / IPTC / COM segments (mock data mode).
  Uint8List mockJpeg() {
    final photo = mock.photo(variant: 0, width: 256, height: 192);
    return photo.jpegBytes;
  }

  test('mock JPEG exposes IFD0, Exif, GPS, XMP, IPTC and comment rows', () {
    final audit = cleaner.scan(mockJpeg(), fileName: 'mock.jpg');
    final groups = audit.entries.map((e) => e.group).toSet();
    expect(groups, containsAll(<String>['IFD0', 'Exif', 'GPS', 'XMP', 'IPTC', 'COMMENT']));
    expect(audit.hasGps, isTrue);
    expect(audit.gps!.latitude, closeTo(30.0444, 0.001));
    expect(audit.gps!.longitude, closeTo(31.2357, 0.001));
    expect(audit.entries.any((e) => e.tag == 'BodySerialNumber'), isTrue);
    expect(audit.entries.any((e) => e.tag == 'CameraOwnerName'), isTrue);
    expect(audit.sensitiveCount, greaterThan(20));
  });

  test('stripJpeg removes every metadata segment and keeps the container valid',
      () {
    final original = mockJpeg();
    final stripped = JpegMeta.stripJpeg(original);

    final before = JpegMeta.inspectJpeg(bytes: original);
    final after = JpegMeta.inspectJpeg(bytes: stripped);

    expect(before.entries.length, greaterThan(20));
    expect(after.entries, isEmpty);
    expect(after.gps, isNull);
    expect(stripped.sublist(0, 2), <int>[0xFF, 0xD8]);
    expect(stripped.sublist(stripped.length - 2), <int>[0xFF, 0xD9]);
    expect(stripped.length, lessThan(original.length));
  });

  test('cleaning is lossless: decoded pixels are unchanged', () async {
    final original = mockJpeg();
    final result = await cleaner.clean(original, fileName: 'mock.jpg');
    expect(result.lossless, isTrue);
    expect(result.clean, isTrue);
    expect(result.after.entries, isEmpty);

    // Decoding both containers must yield identical pixels, because only
    // container segments were removed — the entropy-coded scan is untouched.
    final a = img.decodeJpg(original)!;
    final b = img.decodeJpg(result.bytes)!;
    expect(a.width, b.width);
    expect(a.height, b.height);
    for (var y = 0; y < a.height; y += 7) {
      for (var x = 0; x < a.width; x += 7) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        expect(pa.r, pb.r);
        expect(pa.g, pb.g);
        expect(pa.b, pb.b);
      }
    }
  });

  test('PNG text chunks are reported and stripped by re-encoding', () async {
    final image = img.Image(width: 32, height: 24, numChannels: 4);
    img.fill(image, color: img.ColorRgb8(20, 40, 60));
    final png = Uint8List.fromList(img.encodePng(image));

    // Inject a tEXt chunk the way a screenshot tool would.
    final chunk = _textChunk('Author', 'Layla Hassan');
    final withText = Uint8List.fromList(<int>[
      ...png.sublist(0, png.length - 12),
      ...chunk,
      ...png.sublist(png.length - 12),
    ]);

    final audit = cleaner.scan(withText, fileName: 'shot.png');
    expect(audit.format, 'PNG');
    expect(audit.entries.any((e) => e.tag == 'Author'), isTrue);

    final result = await cleaner.clean(withText, fileName: 'shot.png');
    expect(result.after.entries, isEmpty);
    expect(result.bytes.sublist(0, 8), <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });
}

Uint8List _textChunk(String keyword, String value) {
  final payload = <int>[...keyword.codeUnits, 0, ...value.codeUnits];
  final out = BytesBuilder();
  final length = ByteData(4)..setUint32(0, payload.length);
  out.add(length.buffer.asUint8List());
  final typeAndData = <int>[...'tEXt'.codeUnits, ...payload];
  out.add(typeAndData);
  out.add((ByteData(4)..setUint32(0, _crc(typeAndData))).buffer.asUint8List());
  return out.toBytes();
}

int _crc(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
