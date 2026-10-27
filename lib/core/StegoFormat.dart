// StegoFormat.dart
//
// Byte-level definition of the SGV-1 container. See docs/STEGO_FORMAT.md.
// Nothing here touches pixels: it only serialises the header + framed payload.

import 'dart:convert';
import 'dart:typed_data';

import 'CryptoService.dart';

class StegoFormat {
  static const List<int> magic = <int>[0x53, 0x47, 0x56, 0x31]; // "SGV1"
  static const int version = 0x01;

  static const int headerLength = 38; // magic4 + ver1 + flags1 + len4 + salt16 + iv12
  static const int saltOffset = 10;
  static const int ivOffset = 26;
  static const int bodyOffset = 38;

  static const int flagIsFile = 1 << 0;
  static const int flagTwoBit = 1 << 1;

  /// Bytes authenticated by GCM (magic/version/flags/cipherLen).
  static const int aadLength = 10;

  /// Capacity in bytes of an RGB image of [width] x [height] at [depth] LSBs.
  static int capacityBytes({required int width, required int height, required int depth}) {
    final bits = width * height * 3 * depth;
    return bits ~/ 8;
  }

  /// Largest plaintext (before GCM tag and framing overhead) that fits.
  static int usablePayloadBytes({required int width, required int height, required int depth}) {
    final cap = capacityBytes(width: width, height: height, depth: depth);
    final usable = cap - headerLength - CryptoService.tagLengthBytes;
    return usable < 0 ? 0 : usable;
  }

  static bool hasMagic(List<int> bytes, int offset) {
    if (bytes.length < offset + 4) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  static Uint8List buildHeader({
    required int flags,
    required int cipherLen,
    required Uint8List salt,
    required Uint8List iv,
  }) {
    assert(salt.length == CryptoService.saltLengthBytes);
    assert(iv.length == CryptoService.ivLengthBytes);
    final header = Uint8List(headerLength);
    header.setRange(0, 4, magic);
    header[4] = version;
    header[5] = flags;
    final len = ByteData(4)..setUint32(0, cipherLen, Endian.big);
    header.setRange(6, 10, len.buffer.asUint8List());
    header.setRange(saltOffset, saltOffset + salt.length, salt);
    header.setRange(ivOffset, ivOffset + iv.length, iv);
    return header;
  }

  static StegoHeader parseHeader(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw StegoFormatException('Container truncated: header incomplete.');
    }
    if (!hasMagic(bytes, 0)) {
      throw StegoFormatException('Magic header missing.');
    }
    final bd = ByteData.sublistView(bytes, 6, 10);
    return StegoHeader(
      version: bytes[4],
      flags: bytes[5],
      cipherLen: bd.getUint32(0, Endian.big),
      salt: Uint8List.sublistView(bytes, saltOffset, saltOffset + CryptoService.saltLengthBytes),
      iv: Uint8List.sublistView(bytes, ivOffset, ivOffset + CryptoService.ivLengthBytes),
      aad: Uint8List.sublistView(bytes, 0, aadLength),
    );
  }

  /// Frames a file payload: nameLen|name|mimeLen|mime|bytes (see spec §4).
  static Uint8List frameFile({
    required String fileName,
    required String mimeType,
    required Uint8List data,
  }) {
    final name = Uint8List.fromList(utf8.encode(fileName));
    final mime = Uint8List.fromList(utf8.encode(mimeType));
    final out = BytesBuilder(copy: false);
    final head = ByteData(4);
    head.setUint16(0, name.length, Endian.big);
    head.setUint16(2, mime.length, Endian.big);
    out.add(head.buffer.asUint8List(0, 2));
    out.add(name);
    out.add(head.buffer.asUint8List(2, 2));
    out.add(mime);
    out.add(data);
    return out.toBytes();
  }

  static UnframedFile unframeFile(Uint8List plain) {
    final bd = ByteData.sublistView(plain);
    if (plain.length < 2) throw StegoFormatException('File frame truncated.');
    final nameLen = bd.getUint16(0, Endian.big);
    var cursor = 2;
    if (plain.length < cursor + nameLen + 2) {
      throw StegoFormatException('File frame truncated (name).');
    }
    final name = utf8.decode(Uint8List.sublistView(plain, cursor, cursor + nameLen));
    cursor += nameLen;
    final mimeLen = bd.getUint16(cursor, Endian.big);
    cursor += 2;
    if (plain.length < cursor + mimeLen) {
      throw StegoFormatException('File frame truncated (mime).');
    }
    final mime = utf8.decode(Uint8List.sublistView(plain, cursor, cursor + mimeLen));
    cursor += mimeLen;
    return UnframedFile(
      fileName: name,
      mimeType: mime,
      data: Uint8List.sublistView(plain, cursor),
    );
  }
}

class StegoHeader {
  const StegoHeader({
    required this.version,
    required this.flags,
    required this.cipherLen,
    required this.salt,
    required this.iv,
    required this.aad,
  });

  final int version;
  final int flags;
  final int cipherLen;
  final Uint8List salt;
  final Uint8List iv;
  final Uint8List aad;

  bool get isFile => flags & StegoFormat.flagIsFile != 0;
  bool get isTwoBit => flags & StegoFormat.flagTwoBit != 0;
  int get depth => isTwoBit ? 2 : 1;
}

class UnframedFile {
  const UnframedFile({
    required this.fileName,
    required this.mimeType,
    required this.data,
  });
  final String fileName;
  final String mimeType;
  final Uint8List data;
}

class StegoFormatException implements Exception {
  StegoFormatException(this.message);
  final String message;
  @override
  String toString() => 'StegoFormatException: $message';
}
