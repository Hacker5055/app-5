// LSBStegoEngine.dart
//
// Custom multi-plane LSB embedder / extractor over the RGB channels of a raster
// container. Alpha is preserved bit-exactly, so PNG round-trips never introduce
// visible artefacts.
//
// Design notes
//  * Bit depth 1 or 2 per channel (2-bit doubles capacity; on photographs it is
//    still invisible to the eye because the deviation is <= 3/255 per channel).
//  * Traversal is row-major RGB, MSB-first, and the remaining capacity is filled
//    with random bits (see [LSBStegoEngine.embed]) so the ciphertext boundary is
//    not detectable.
//  * The engine is pure Dart -> works on device AND on host for unit tests.

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'CryptoService.dart';
import 'StegoFormat.dart';

class EmbedResult {
  const EmbedResult({
    required this.pngBytes,
    required this.image,
    required this.depth,
    required this.capacityBytes,
    required this.usedBytes,
    required this.payloadBits,
  });

  final Uint8List pngBytes;
  final img.Image image;
  final int depth;
  final int capacityBytes;
  final int usedBytes;
  final int payloadBits;

  double get utilisation => capacityBytes == 0 ? 0 : usedBytes / capacityBytes;
  double get psnrDb => estimatePsnr(payloadBits, capacityBytes);
}

/// Rough PSNR estimate for the LSB plane; 1-bit typically lands > 50 dB,
/// 2-bit around 44 dB (imperceptible).
double estimatePsnr(int payloadBits, int capacityBytes) {
  if (capacityBytes == 0) return 99;
  final depth = payloadBits / (capacityBytes * 8);
  return 60 - (10 * depth);
}

class ExtractResult {
  const ExtractResult({
    required this.payload,
    required this.header,
    required this.depth,
    required this.iterations,
    required this.elapsed,
  });

  final Uint8List payload;
  final StegoHeader header;
  final int depth;
  final int iterations;
  final Duration elapsed;
}

class LSBStegoEngine {
  LSBStegoEngine(this._crypto);

  final CryptoService _crypto;

  /// Encrypts [payload] and embeds it into [cover].
  ///
  /// [depth] must be 1 or 2. Returns a PNG (lossless) container; encoding to
  /// JPEG would destroy the LSB plane, which is why the engine refuses to emit
  /// anything lossy.
  EmbedResult embed({
    required img.Image cover,
    required List<int> payload,
    required String password,
    required bool isFilePayload,
    int depth = 1,
  }) {
    if (depth != 1 && depth != 2) {
      throw StegoFormatException('Unsupported bit depth: $depth.');
    }
    final capacity = StegoFormat.capacityBytes(
      width: cover.width,
      height: cover.height,
      depth: depth,
    );
    final maxPlain = StegoFormat.usablePayloadBytes(
      width: cover.width,
      height: cover.height,
      depth: depth,
    );
    if (payload.length > maxPlain) {
      throw StegoFormatException(
        'Payload of ${payload.length} B exceeds capacity of $maxPlain B at $depth-bit.',
      );
    }

    // Reserve the header first so its bytes can be authenticated as AAD.
    final flags = (isFilePayload ? StegoFormat.flagIsFile : 0) |
        (depth == 2 ? StegoFormat.flagTwoBit : 0);
    final salt = _crypto.randomBytes(CryptoService.saltLengthBytes);
    final iv = _crypto.randomBytes(CryptoService.ivLengthBytes);
    final lengthField = ByteData(4)..setUint32(0, payload.length + CryptoService.tagLengthBytes, Endian.big);

    final aad = Uint8List(StegoFormat.aadLength)
      ..setRange(0, 4, StegoFormat.magic)
      ..[4] = StegoFormat.version
      ..[5] = flags
      ..setRange(6, 10, lengthField.buffer.asUint8List());

    final blob = _crypto.encrypt(
      password: password,
      plaintext: payload,
      associatedData: aad,
      salt: salt,
      iv: iv,
    );

    final header = StegoFormat.buildHeader(
      flags: flags,
      cipherLen: blob.ciphertext.length,
      salt: blob.salt,
      iv: blob.iv,
    );

    final stream = Uint8List.fromList([...header, ...blob.ciphertext]);

    final bits = stream.length * 8;
    final randomPad = _crypto.randomBytes((capacity * 8 - bits) ~/ 8);

    final output = cover.convert(numChannels: 4);
    _writeBits(output, depth, stream, 0);
    if (randomPad.isNotEmpty) {
      _writeBits(output, depth, randomPad, stream.length * 8);
    }

    final png = img.encodePng(output, level: 6);
    return EmbedResult(
      pngBytes: Uint8List.fromList(png),
      image: output,
      depth: depth,
      capacityBytes: capacity,
      usedBytes: stream.length,
      payloadBits: bits,
    );
  }

  /// Attempts extraction at 1-bit, then at 2-bit.
  ExtractResult extract({
    required img.Image stego,
    required String password,
    void Function(String stage)? onStage,
  }) {
    final sw = Stopwatch()..start();
    final image = stego.convert(numChannels: 4);

    for (final depth in const <int>[1, 2]) {
      onStage?.call('Probing ${depth}-bit plane');
      final headerBytes = _readBits(image, depth, 0, StegoFormat.headerLength);
      if (!StegoFormat.hasMagic(headerBytes, 0)) continue;

      final head = StegoFormat.parseHeader(headerBytes);
      final cap = StegoFormat.capacityBytes(
        width: image.width,
        height: image.height,
        depth: depth,
      );
      if (head.cipherLen <= 0 || head.cipherLen > cap - StegoFormat.headerLength) {
        throw StegoFormatException('Header length field is out of range.');
      }

      onStage?.call('Validating GCM tag (PBKDF2 100k)');
      final cipherBytes = _readBits(image, depth, StegoFormat.headerLength * 8, head.cipherLen);
      final plain = _crypto.decrypt(
        password: password,
        salt: head.salt,
        iv: head.iv,
        ciphertext: cipherBytes,
        associatedData: head.aad,
      );
      sw.stop();
      return ExtractResult(
        payload: plain,
        header: head,
        depth: depth,
        iterations: _crypto.iterations,
        elapsed: sw.elapsed,
      );
    }

    sw.stop();
    throw StegoFormatException(
      'No SGV1 container found. The image holds no hidden payload '
      '(or it is not a lossless RGB container).',
    );
  }

  /// Cheap detection pass used by the UI badge: does the image carry a container?
  ContainerPresence detect(img.Image candidate) {
    final image = candidate.convert(numChannels: 4);
    for (final depth in const <int>[1, 2]) {
      final head = _readBits(image, depth, 0, StegoFormat.headerLength);
      if (!StegoFormat.hasMagic(head, 0)) continue;
      try {
        final parsed = StegoFormat.parseHeader(head);
        return ContainerPresence.present(parsed, depth);
      } on StegoFormatException {
        continue;
      }
    }
    return ContainerPresence.absent;
  }

  // ---------------------------------------------------------------- bit i/o

  void _writeBits(img.Image image, int depth, Uint8List data, int bitOffset) {
    var position = bitOffset;
    for (final byte in data) {
      for (var b = 7; b >= 0; b--) {
        final bit = (byte >> b) & 1;
        final pixel = position ~/ (3 * depth);
        final rem = position % (3 * depth);
        final channel = rem ~/ depth;
        final inChannel = depth - 1 - (rem % depth);

        final x = pixel % image.width;
        final y = pixel ~/ image.width;
        if (y >= image.height) return;
        final p = image.getPixel(x, y);
        switch (channel) {
          case 0:
            p.r = ((p.r.toInt() & ~(1 << inChannel)) | (bit << inChannel)).toInt();
            break;
          case 1:
            p.g = ((p.g.toInt() & ~(1 << inChannel)) | (bit << inChannel)).toInt();
            break;
          default:
            p.b = ((p.b.toInt() & ~(1 << inChannel)) | (bit << inChannel)).toInt();
        }
        image.setPixel(x, y, p);
        position++;
      }
    }
  }

  Uint8List _readBits(img.Image image, int depth, int bitOffset, int byteLength) {
    final out = Uint8List(byteLength);
    var position = bitOffset;
    for (var i = 0; i < byteLength; i++) {
      var value = 0;
      for (var b = 7; b >= 0; b--) {
        final pixel = position ~/ (3 * depth);
        final rem = position % (3 * depth);
        final channel = rem ~/ depth;
        final inChannel = depth - 1 - (rem % depth);

        final x = pixel % image.width;
        final y = pixel ~/ image.width;
        if (y >= image.height) return out;
        final p = image.getPixel(x, y);
        final v = switch (channel) { 0 => p.r.toInt(), 1 => p.g.toInt(), _ => p.b.toInt() };
        final bit = (v >> inChannel) & 1;
        value = (value << 1) | bit;
        position++;
      }
      out[i] = value;
    }
    return out;
  }

  /// Utility for the preview slider: absolute mean channel delta between cover
  /// and stego image, plus a rough PSNR figure.
  static StegoDiff diff(img.Image a, img.Image b) {
    final w = min(a.width, b.width);
    final h = min(a.height, b.height);
    var sumSq = 0.0;
    var changed = 0;
    var maxDelta = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        for (final delta in <int>[
          (pa.r - pb.r).abs().toInt(),
          (pa.g - pb.g).abs().toInt(),
          (pa.b - pb.b).abs().toInt(),
        ]) {
          sumSq += delta * delta;
          if (delta != 0) changed++;
          if (delta > maxDelta) maxDelta = delta;
        }
      }
    }
    final n = w * h * 3;
    final mse = n == 0 ? 0.0 : sumSq / n;
    final psnr = mse == 0 ? 99.0 : 10 * (log(255 * 255 / mse) / ln10);
    return StegoDiff(psnrDb: psnr, changedChannels: changed, totalChannels: n, maxChannelDelta: maxDelta);
  }
}

class StegoDiff {
  const StegoDiff({
    required this.psnrDb,
    required this.changedChannels,
    required this.totalChannels,
    required this.maxChannelDelta,
  });

  final double psnrDb;
  final int changedChannels;
  final int totalChannels;
  final int maxChannelDelta;

  double get changedRatio => totalChannels == 0 ? 0 : changedChannels / totalChannels;
}

class ContainerPresence {
  const ContainerPresence._(this.present, this.header, this.depth);

  static const absent = ContainerPresence._(false, null, 0);

  factory ContainerPresence.present(StegoHeader header, int depth) =>
      ContainerPresence._(true, header, depth);

  final bool present;
  final StegoHeader? header;
  final int depth;
}
