// JpegMeta.dart
//
// Zero-dependency, byte-level EXIF / XMP / IPTC inspector and *lossless* JPEG
// scrubbing. No re-compression happens for JPEG inputs: we drop the metadata
// segments (APP1/APP13/COM/MPF) from the container and leave the entropy-coded
// scan data untouched, so pixels stay bit-identical while every identifying tag
// disappears. PNG/BMP/WebP are re-encoded from decoded pixels on the service
// layer, which is equally lossless for PNG/BMP.

import 'dart:convert';
import 'dart:typed_data';

class MetadataEntry {
  const MetadataEntry({
    required this.group,
    required this.tag,
    required this.value,
    this.sensitive = false,
  });

  /// IFD group: `IFD0`, `Exif`, `GPS`, `XMP`, `IPTC`, `PNG`, `JFIF`, `COMMENT`.
  final String group;
  final String tag;
  final String value;
  final bool sensitive;

  @override
  String toString() => '$group/$tag=$value';
}

class GpsPoint {
  const GpsPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class MediaAudit {
  const MediaAudit({
    required this.format,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.entries,
    this.gps,
  });

  final String format;
  final int width;
  final int height;
  final int sizeBytes;
  final List<MetadataEntry> entries;
  final GpsPoint? gps;

  int get sensitiveCount => entries.where((e) => e.sensitive).length;
  bool get hasMetadata => entries.isNotEmpty;
  bool get hasGps => gps != null;

  List<MetadataEntry> get sensitiveEntries => entries.where((e) => e.sensitive).toList();
}

class JpegMeta {
  // ------------------------------------------------------------------ parse

  static bool isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;
  static bool isPng(Uint8List b) =>
      b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  static bool isBmp(Uint8List b) => b.length > 2 && b[0] == 0x42 && b[1] == 0x4D;
  static bool isWebp(Uint8List b) =>
      b.length > 12 && ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP';

  /// Inspects a JPEG and returns every readable metadata entry.
  static MediaAudit inspectJpeg({
    required Uint8List bytes,
    String safeName = 'image',
  }) {
    final entries = <MetadataEntry>[];
    var width = 0;
    var height = 0;
    GpsPoint? gps;
    var jfif = false;

    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      var marker = bytes[i + 1];
      // Skip fill bytes.
      while (marker == 0xFF && i + 2 < bytes.length) {
        i++;
        marker = bytes[i + 1];
      }
      i += 2;
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
        continue; // standalone markers
      }
      if (marker == 0xDA) break; // start of scan, stop parsing headers
      if (i + 1 >= bytes.length) break;
      final segLen = (bytes[i] << 8) | bytes[i + 1];
      if (segLen < 2 || i + segLen > bytes.length) break;
      final payload = Uint8List.sublistView(bytes, i + 2, i + segLen);

      switch (marker) {
        case 0xE0: // APP0
          if (_startsWith(payload, 'JFIF')) {
            jfif = true;
            final ver = payload.length > 12
                ? '${payload[11]}.${payload[12].toRadixString(16).padLeft(2, '0')}'
                : '?';
            entries.add(MetadataEntry(group: 'JFIF', tag: 'Version', value: ver));
          }
          break;
        case 0xE1: // APP1: EXIF or XMP
          if (_startsWith(payload, 'Exif')) {
            final tiff = Uint8List.sublistView(payload, 6);
            final parsed = _TiffReader(tiff).read();
            entries.addAll(parsed.entries);
            gps = parsed.gps ?? gps;
          } else if (_startsWith(payload, 'http://ns.adobe.com/xap/1.0/')) {
            final xmp = utf8.decode(
              payload.sublist(29),
              allowMalformed: true,
            );
            entries.addAll(_extractXmp(xmp));
          }
          break;
        case 0xE2: // APP2: ICC profile or MPF
          if (_startsWith(payload, 'ICC_PROFILE')) {
            entries.add(const MetadataEntry(
              group: 'ICC',
              tag: 'Profile',
              value: 'Embedded colour profile (kept: no identity data)',
            ));
          } else if (_startsWith(payload, 'MPF')) {
            entries.add(const MetadataEntry(
              group: 'MPF',
              tag: 'Multi-Picture',
              value: 'Multi-picture index present',
              sensitive: true,
            ));
          }
          break;
        case 0xED: // APP13: IPTC / Photoshop resource blocks
          entries.addAll(_extractIptc(payload));
          break;
        case 0xFE: // COM
          final text = utf8.decode(payload, allowMalformed: true).trim();
          if (text.isNotEmpty) {
            entries.add(MetadataEntry(
              group: 'COMMENT',
              tag: 'UserComment',
              value: text.length > 120 ? '${text.substring(0, 120)}…' : text,
              sensitive: true,
            ));
          }
          break;
        case 0xC0:
        case 0xC1:
        case 0xC2:
        case 0xC3:
        case 0xC5:
        case 0xC6:
        case 0xC7:
        case 0xC9:
        case 0xCA:
        case 0xCB:
        case 0xCD:
        case 0xCE:
        case 0xCF:
          if (payload.length >= 5) {
            height = (payload[1] << 8) | payload[2];
            width = (payload[3] << 8) | payload[4];
          }
          break;
      }
      i += segLen;
    }

    if (jfif && entries.where((e) => e.group == 'JFIF').isEmpty) {
      entries.add(const MetadataEntry(group: 'JFIF', tag: 'Marker', value: 'present'));
    }

    return MediaAudit(
      format: 'JPEG',
      width: width,
      height: height,
      sizeBytes: bytes.length,
      entries: entries,
      gps: gps,
    );
  }

  /// PNG text / EXIF chunks -> audit rows.
  static MediaAudit inspectPng({required Uint8List bytes}) {
    final entries = <MetadataEntry>[];
    var width = 0;
    var height = 0;
    var i = 8;
    while (i + 8 <= bytes.length) {
      final len = (bytes[i] << 24) | (bytes[i + 1] << 16) | (bytes[i + 2] << 8) | bytes[i + 3];
      if (len < 0 || i + 12 + len > bytes.length) break;
      final type = ascii.decode(bytes.sublist(i + 4, i + 8), allowInvalid: true);
      final data = Uint8List.sublistView(bytes, i + 8, i + 8 + len);
      if (type == 'IHDR' && data.length >= 8) {
        width = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
        height = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
      } else if (type == 'tEXt' || type == 'iTXt') {
        final sep = data.indexOf(0);
        final key = ascii.decode(data.sublist(0, sep < 0 ? data.length : sep), allowInvalid: true);
        final raw = utf8.decode(
          data.sublist(sep < 0 ? data.length : sep + 1),
          allowMalformed: true,
        );
        entries.add(MetadataEntry(
          group: 'PNG',
          tag: key.isEmpty ? type : key,
          value: _clip(raw),
          sensitive: true,
        ));
      } else if (type == 'zTXt') {
        entries.add(const MetadataEntry(
          group: 'PNG',
          tag: 'zTXt',
          value: 'Compressed text chunk (stripped)',
          sensitive: true,
        ));
      } else if (type == 'eXIf') {
        final parsed = _TiffReader(data).read();
        entries.addAll(parsed.entries);
      } else if (type == 'tIME') {
        entries.add(const MetadataEntry(
          group: 'PNG',
          tag: 'tIME',
          value: 'Last-modification timestamp',
          sensitive: true,
        ));
      } else if (type == 'IEND') {
        break;
      }
      i += 12 + len;
    }
    return MediaAudit(
      format: 'PNG',
      width: width,
      height: height,
      sizeBytes: bytes.length,
      entries: entries,
    );
  }

  static String _clip(String v) => v.length > 120 ? '${v.substring(0, 120)}…' : v;

  static bool _startsWith(Uint8List data, String prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix.codeUnitAt(i)) return false;
    }
    return true;
  }

  static List<MetadataEntry> _extractXmp(String xmp) {
    final out = <MetadataEntry>[];
    final patterns = <String, String>{
      'xmp:CreatorTool': r'xmp:CreatorTool="([^"]+)"',
      'xmp:CreateDate': r'xmp:CreateDate="([^"]+)"',
      'photoshop:SerialNumber': r'photoshop:SerialNumber="([^"]+)"',
      'aux:SerialNumber': r'aux:SerialNumber="([^"]+)"',
      'xmpMM:DocumentID': r'xmpMM:DocumentID="([^"]+)"',
      'dc:creator': r'<dc:creator>[\s\S]*?<rdf:li[^>]*>([^<]+)</rdf:li>',
      'tiff:Make': r'tiff:Make="([^"]+)"',
      'tiff:Model': r'tiff:Model="([^"]+)"',
    };
    patterns.forEach((tag, pattern) {
      final m = RegExp(pattern).firstMatch(xmp);
      if (m != null && (m.group(1) ?? '').trim().isNotEmpty) {
        out.add(MetadataEntry(
          group: 'XMP',
          tag: tag.split(':').last,
          value: _clip(m.group(1)!.trim()),
          sensitive: true,
        ));
      }
    });
    if (out.isEmpty) {
      out.add(const MetadataEntry(
        group: 'XMP',
        tag: 'Packet',
        value: 'XMP packet present (stripped)',
        sensitive: true,
      ));
    }
    return out;
  }

  static List<MetadataEntry> _extractIptc(Uint8List payload) {
    final out = <MetadataEntry>[];
    final text = latin1.decode(payload, allowInvalid: true);
    const labels = <int, String>{
      80: 'By-line (author)',
      90: 'City',
      92: 'Sub-location',
      95: 'State',
      101: 'Country',
      105: 'Headline',
      110: 'Credit',
      115: 'Source',
      116: 'Copyright',
      120: 'Caption',
    };
    for (var i = 0; i + 4 < payload.length; i++) {
      if (payload[i] == 0x1C && payload[i + 1] == 0x02) {
        final dataset = payload[i + 2];
        final len = (payload[i + 3] << 8) | payload[i + 4];
        final label = labels[dataset];
        if (label == null || len <= 0 || i + 5 + len > payload.length) continue;
        final value = latin1
            .decode(Uint8List.sublistView(payload, i + 5, i + 5 + len), allowInvalid: true)
            .trim();
        if (value.isEmpty) continue;
        out.add(MetadataEntry(
          group: 'IPTC',
          tag: label,
          value: _clip(value),
          sensitive: true,
        ));
        i += 4 + len;
      }
    }
    if (out.isEmpty && text.contains('Photoshop')) {
      out.add(const MetadataEntry(
        group: 'IPTC',
        tag: 'Photoshop resource block',
        value: 'APP13 present (stripped)',
        sensitive: true,
      ));
    }
    return out;
  }

  // ------------------------------------------------------------------ strip

  /// Removes APP1 (EXIF + XMP), APP13 (IPTC), COM, and MPF APP2 segments while
  /// copying every other byte verbatim. Scan data is never re-compressed.
  static Uint8List stripJpeg(Uint8List bytes) {
    if (!isJpeg(bytes)) return bytes;
    final out = BytesBuilder(copy: false);
    out.add(const <int>[0xFF, 0xD8]);

    var i = 2;
    while (i < bytes.length) {
      if (bytes[i] != 0xFF) {
        out.add(Uint8List.sublistView(bytes, i));
        break;
      }
      var marker = bytes[i + 1];
      var markerStart = i;
      while (marker == 0xFF && i + 2 < bytes.length) {
        i++;
        marker = bytes[i + 1];
      }
      final headerStart = i;
      i += 2;

      if (marker == 0xD9) {
        out.add(Uint8List.sublistView(bytes, headerStart, i));
        break;
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        out.add(Uint8List.sublistView(bytes, markerStart, i));
        continue;
      }
      if (marker == 0xDA) {
        // Everything from SOS to EOF (including trailing thumbnails' metadata is
        // never present after SOS in valid JPEGs) is copied verbatim.
        out.add(Uint8List.sublistView(bytes, markerStart));
        break;
      }
      if (i + 1 >= bytes.length) {
        out.add(Uint8List.sublistView(bytes, markerStart));
        break;
      }
      final segLen = (bytes[i] << 8) | bytes[i + 1];
      if (segLen < 2 || i + segLen > bytes.length) {
        out.add(Uint8List.sublistView(bytes, markerStart));
        break;
      }
      final payload = Uint8List.sublistView(bytes, i + 2, i + segLen);

      var drop = false;
      if (marker == 0xE1) drop = true; // EXIF + XMP
      if (marker == 0xED) drop = true; // IPTC / Photoshop
      if (marker == 0xFE) drop = true; // COM
      if (marker == 0xE2 && _startsWith(payload, 'MPF')) drop = true;

      if (!drop) {
        out.add(Uint8List.sublistView(bytes, markerStart, i + segLen));
      }
      i += segLen;
    }
    return out.toBytes();
  }
}

// ---------------------------------------------------------------------------
// Minimal TIFF/EXIF reader (IFD0 + Exif sub-IFD + GPS sub-IFD).
// ---------------------------------------------------------------------------

class _TiffResult {
  _TiffResult(this.entries, this.gps);
  final List<MetadataEntry> entries;
  final GpsPoint? gps;
}

class _TiffReader {
  _TiffReader(this.data);

  final Uint8List data;

  bool get _little {
    if (data.length < 2) return true;
    return data[0] == 0x49 && data[1] == 0x49;
  }

  int _u16(int o) {
    if (o + 2 > data.length) return 0;
    final bd = ByteData.sublistView(data, o, o + 2);
    return bd.getUint16(0, _little ? Endian.little : Endian.big);
  }

  int _u32(int o) {
    if (o + 4 > data.length) return 0;
    final bd = ByteData.sublistView(data, o, o + 4);
    return bd.getUint32(0, _little ? Endian.little : Endian.big);
  }

  _TiffResult read() {
    final entries = <MetadataEntry>[];
    GpsPoint? gps;
    if (data.length < 8) return _TiffResult(entries, null);
    if (_u16(2) != 0x002A) return _TiffResult(entries, null);

    final ifd0 = _u32(4);
    final subIfdOffsets = <String, int>{};
    _readIfd(ifd0, 'IFD0', entries, subIfdOffsets);

    final exifOffset = subIfdOffsets['Exif'];
    if (exifOffset != null && exifOffset > 0) {
      _readIfd(exifOffset, 'Exif', entries, const <String, int>{});
    }
    final gpsOffset = subIfdOffsets['GPS'];
    if (gpsOffset != null && gpsOffset > 0) {
      final gpsTags = <int, Object>{};
      _readIfd(gpsOffset, 'GPS', entries, const <String, int>{}, rawSink: gpsTags);
      gps = _decodeGps(gpsTags);
    }
    // IFD1 holds the embedded thumbnail; it often carries its own EXIF.
    final ifd1 = _u32(ifd0 + 2 + _u16(ifd0) * 12);
    if (ifd1 > 0 && ifd1 < data.length && ifd1 != ifd0) {
      final thumb = <MetadataEntry>[];
      _readIfd(ifd1, 'IFD1 (thumbnail)', thumb, const <String, int>{});
      entries.addAll(thumb.take(8));
    }
    return _TiffResult(entries, gps);
  }

  void _readIfd(
    int offset,
    String group,
    List<MetadataEntry> out,
    Map<String, int> subIfd,
    {Map<int, Object>? rawSink}
  ) {
    if (offset + 2 > data.length) return;
    final count = _u16(offset);
    if (count > 512) return; // corrupt guard
    for (var n = 0; n < count; n++) {
      final entryOffset = offset + 2 + n * 12;
      if (entryOffset + 12 > data.length) return;
      final tag = _u16(entryOffset);
      final type = _u16(entryOffset + 2);
      final valueCount = _u32(entryOffset + 4);
      final valueOffsetField = _u32(entryOffset + 8);

      if (tag == 0x8769) subIfd['Exif'] = valueOffsetField;
      if (tag == 0x8825) subIfd['GPS'] = valueOffsetField;
      if (tag == 0xA005) subIfd['Interop'] = valueOffsetField;

      final typeSize = _typeSize(type);
      if (typeSize == 0) continue;
      final byteLength = typeSize * valueCount;
      if (byteLength <= 0 || byteLength > 65536) continue;
      final valueStart = byteLength <= 4 ? entryOffset + 8 : valueOffsetField;
      if (valueStart + byteLength > data.length) continue;

      final values = _decodeValues(type, valueStart, valueCount);
      if (values.isEmpty) continue;
      rawSink?[tag] = values.length == 1 ? values.first : values;

      final name = _tagName(group, tag);
      if (name == null) continue;
      final rendered = _render(type, values);
      if (rendered.trim().isEmpty) continue;
      out.add(MetadataEntry(
        group: group,
        tag: name,
        value: JpegMeta._clip(rendered),
        sensitive: _isSensitive(name),
      ));
    }
  }

  int _typeSize(int type) => switch (type) {
        1 => 1, // BYTE
        2 => 1, // ASCII
        3 => 2, // SHORT
        4 => 4, // LONG
        5 => 8, // RATIONAL
        6 => 1, // SBYTE
        7 => 1, // UNDEFINED
        8 => 2, // SSHORT
        9 => 4, // SLONG
        10 => 8, // SRATIONAL
        11 => 4, // FLOAT
        12 => 8, // DOUBLE
        _ => 0,
      };

  List<num> _decodeValues(int type, int start, int count) {
    final out = <num>[];
    final bd = ByteData.sublistView(data);
    for (var i = 0; i < count; i++) {
      switch (type) {
        case 1:
        case 7:
        case 2:
        case 6:
          if (start + i < data.length) out.add(data[start + i]);
          break;
        case 3:
        case 8:
          if (start + i * 2 + 2 <= data.length) {
            out.add(bd.getUint16(start + i * 2, _little ? Endian.little : Endian.big));
          }
          break;
        case 4:
        case 9:
          if (start + i * 4 + 4 <= data.length) {
            out.add(bd.getUint32(start + i * 4, _little ? Endian.little : Endian.big));
          }
          break;
        case 5:
        case 10:
          if (start + i * 8 + 8 <= data.length) {
            final numer = bd.getUint32(start + i * 8, _little ? Endian.little : Endian.big);
            final den = bd.getUint32(start + i * 8 + 4, _little ? Endian.little : Endian.big);
            out.add(den == 0 ? 0 : numer / den);
          }
          break;
      }
    }
    return out;
  }

  String _render(int type, List<num> values) {
    if (type == 2) {
      final sb = StringBuffer();
      for (final v in values) {
        if (v == 0) break;
        sb.writeCharCode(v.toInt());
      }
      return sb.toString().replaceAll('\u0000', '').trim();
    }
    if (values.length == 1) {
      final v = values.first;
      return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4);
    }
    if (values.length <= 4 && type != 7) {
      return values.map((v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4)).join(', ');
    }
    return '${values.length} values (binary block)';
  }

  GpsPoint? _decodeGps(Map<int, Object> tags) {
    final lat = tags[2];
    final lon = tags[4];
    final latRef = tags[1];
    final lonRef = tags[3];
    if (lat is! List<num> || lon is! List<num> || lat.length < 3 || lon.length < 3) return null;
    var latDec = lat[0].toDouble() + lat[1] / 60.0 + lat[2] / 3600.0;
    var lonDec = lon[0].toDouble() + lon[1] / 60.0 + lon[2] / 3600.0;
    if (latRef is num && latRef == 'S'.codeUnitAt(0)) latDec = -latDec;
    if (lonRef is num && lonRef == 'W'.codeUnitAt(0)) lonDec = -lonDec;
    if (latRef is List<num> && latRef.isNotEmpty && latRef.first == 'S'.codeUnitAt(0)) {
      latDec = -latDec;
    }
    if (lonRef is List<num> && lonRef.isNotEmpty && lonRef.first == 'W'.codeUnitAt(0)) {
      lonDec = -lonDec;
    }
    if (latDec.isNaN || lonDec.isNaN) return null;
    return GpsPoint(latDec, lonDec);
  }

  static bool _isSensitive(String tag) {
    const keys = <String>[
      'GPS', 'Serial', 'Make', 'Model', 'Software', 'DateTime', 'Artist',
      'Copyright', 'Owner', 'ImageDescription', 'BodySerial', 'LensSerial',
      'UserComment', 'CameraOwner', 'XPTitle', 'XPComment', 'XPAuthor', 'XPKeywords',
    ];
    return keys.any((k) => tag.toLowerCase().contains(k.toLowerCase()));
  }

  static String? _tagName(String group, int tag) {
    if (group == 'GPS') {
      const gps = <int, String>{
        0: 'GPSVersionID',
        1: 'GPSLatitudeRef',
        2: 'GPSLatitude',
        3: 'GPSLongitudeRef',
        4: 'GPSLongitude',
        5: 'GPSAltitudeRef',
        6: 'GPSAltitude',
        7: 'GPSTimeStamp',
        8: 'GPSSatellites',
        9: 'GPSStatus',
        11: 'GPSDOP',
        12: 'GPSSpeedRef',
        13: 'GPSSpeed',
        16: 'GPSImgDirectionRef',
        17: 'GPSImgDirection',
        23: 'GPSDestBearingRef',
        24: 'GPSDestBearing',
        29: 'GPSDateStamp',
        31: 'GPSHPositioningError',
      };
      return gps[tag];
    }
    const exif = <int, String>{
      0x829A: 'ExposureTime',
      0x829D: 'FNumber',
      0x8822: 'ExposureProgram',
      0x8827: 'ISO',
      0x9003: 'DateTimeOriginal',
      0x9004: 'DateTimeDigitized',
      0x9201: 'ShutterSpeedValue',
      0x9202: 'ApertureValue',
      0x9204: 'ExposureBias',
      0x9207: 'MeteringMode',
      0x9209: 'Flash',
      0x920A: 'FocalLength',
      0x9286: 'UserComment',
      0xA002: 'PixelXDimension',
      0xA003: 'PixelYDimension',
      0xA402: 'ExposureMode',
      0xA403: 'WhiteBalance',
      0xA405: 'FocalLengthIn35mm',
      0xA430: 'CameraOwnerName',
      0xA431: 'BodySerialNumber',
      0xA432: 'LensSpecification',
      0xA433: 'LensMake',
      0xA434: 'LensModel',
      0xA435: 'LensSerialNumber',
      0xA420: 'ImageUniqueID',
      0xA005: 'InteropOffset',
      0x8825: 'GPSIFDOffset',
      0x8769: 'ExifIFDOffset',
    };
    const ifd0 = <int, String>{
      0x010E: 'ImageDescription',
      0x010F: 'Make',
      0x0110: 'Model',
      0x0112: 'Orientation',
      0x011A: 'XResolution',
      0x011B: 'YResolution',
      0x0128: 'ResolutionUnit',
      0x0131: 'Software',
      0x0132: 'DateTime',
      0x013B: 'Artist',
      0x013E: 'WhitePoint',
      0x013F: 'PrimaryChromaticities',
      0x0213: 'YCbCrPositioning',
      0x8298: 'Copyright',
      0x9C9B: 'XPTitle',
      0x9C9C: 'XPComment',
      0x9C9D: 'XPAuthor',
      0x9C9E: 'XPKeywords',
      0x9C9F: 'XPSubject',
    };
    return exif[tag] ?? ifd0[tag];
  }
}
