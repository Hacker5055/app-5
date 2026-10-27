// Unit tests for the crypto + LSB engine. Run with:
//   flutter test
//
// These mirror the browser test-suite (test/preview_engine.test.mjs) so both
// implementations of the SGV-1 container stay bit-compatible.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stego_vault/core/CryptoService.dart';
import 'package:stego_vault/core/LSBStegoEngine.dart';
import 'package:stego_vault/core/StegoFormat.dart';

img.Image noiseCover({int width = 320, int height = 240, int seed = 7}) {
  final rnd = Random(seed);
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        rnd.nextInt(256),
        rnd.nextInt(256),
        rnd.nextInt(256),
        255,
      );
    }
  }
  return image;
}

void main() {
  // 100k PBKDF2 rounds per operation: keep the iteration count low in tests.
  final crypto = CryptoService(iterations: 500);
  final engine = LSBStegoEngine(crypto);

  group('CryptoService', () {
    test('derives a 32-byte key and round-trips AES-256-GCM', () {
      final salt = crypto.randomBytes(16);
      final iv = crypto.randomBytes(12);
      final aad = utf8.encode('SGV1-header');
      final plain = utf8.encode('the quick brown fox');

      final blob = crypto.encrypt(
        password: 'correct horse battery staple',
        plaintext: plain,
        associatedData: aad,
        salt: salt,
        iv: iv,
      );
      expect(crypto.deriveKey('x', salt).length, 32);
      expect(blob.ciphertext.length, plain.length + 16);

      final back = crypto.decrypt(
        password: 'correct horse battery staple',
        salt: blob.salt,
        iv: blob.iv,
        ciphertext: blob.ciphertext,
        associatedData: aad,
      );
      expect(utf8.decode(back), 'the quick brown fox');
    });

    test('rejects a wrong password and tampered associated data', () {
      final blob = crypto.encrypt(
        password: 'right',
        plaintext: utf8.encode('secret'),
        associatedData: utf8.encode('aad'),
      );
      expect(
        () => crypto.decrypt(
          password: 'wrong',
          salt: blob.salt,
          iv: blob.iv,
          ciphertext: blob.ciphertext,
          associatedData: utf8.encode('aad'),
        ),
        throwsA(isA<CryptoException>()),
      );
      expect(
        () => crypto.decrypt(
          password: 'right',
          salt: blob.salt,
          iv: blob.iv,
          ciphertext: blob.ciphertext,
          associatedData: utf8.encode('other'),
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('StegoFormat', () {
    test('capacity maths matches width × height × channels × depth / 8', () {
      expect(StegoFormat.capacityBytes(width: 100, height: 100, depth: 1), 3750);
      expect(StegoFormat.capacityBytes(width: 100, height: 100, depth: 2), 7500);
      expect(
        StegoFormat.usablePayloadBytes(width: 100, height: 100, depth: 1),
        3750 - StegoFormat.headerLength - CryptoService.tagLengthBytes,
      );
    });

    test('frames and unframes a file payload', () {
      final data = Uint8List.fromList(<int>[1, 2, 3, 4, 250]);
      final framed = StegoFormat.frameFile(
        fileName: 'note.bin',
        mimeType: 'application/octet-stream',
        data: data,
      );
      final back = StegoFormat.unframeFile(framed);
      expect(back.fileName, 'note.bin');
      expect(back.mimeType, 'application/octet-stream');
      expect(back.data, data);
    });
  });

  group('LSBStegoEngine', () {
    test('1-bit text payload round-trips', () {
      final cover = noiseCover();
      final result = engine.embed(
        cover: cover,
        payload: utf8.encode('meet me at 30.0444, 31.2357'),
        password: 'pw-12345678',
        isFilePayload: false,
        depth: 1,
      );
      expect(result.depth, 1);
      expect(result.usedBytes, greaterThan(16));

      final decoded = img.decodeImage(result.pngBytes)!;
      final out = engine.extract(stego: decoded, password: 'pw-12345678');
      expect(utf8.decode(out.payload), 'meet me at 30.0444, 31.2357');
      expect(out.header.isFile, isFalse);
      expect(out.depth, 1);
    });

    test('2-bit mode doubles capacity and still round-trips', () {
      final cover = noiseCover();
      final payload = Uint8List.fromList(List<int>.filled(3000, 0x41));
      final result = engine.embed(
        cover: cover,
        payload: payload,
        password: 'pw-two-bit',
        isFilePayload: false,
        depth: 2,
      );
      final out = engine.extract(stego: result.image, password: 'pw-two-bit');
      expect(out.payload, payload);
      expect(out.depth, 2);
    });

    test('wrong password fails on the GCM tag', () {
      final result = engine.embed(
        cover: noiseCover(),
        payload: utf8.encode('classified'),
        password: 'right-password',
        isFilePayload: false,
      );
      expect(
        () => engine.extract(stego: result.image, password: 'wrong-password'),
        throwsA(isA<CryptoException>()),
      );
    });

    test('detect() finds the header without the password', () {
      final result = engine.embed(
        cover: noiseCover(),
        payload: utf8.encode('hello'),
        password: 'pw',
        isFilePayload: false,
        depth: 2,
      );
      final presence = engine.detect(result.image);
      expect(presence.present, isTrue);
      expect(presence.depth, 2);
      expect(presence.header!.cipherLen, 5 + CryptoService.tagLengthBytes);
    });

    test('a plain image reports no container', () {
      expect(engine.detect(noiseCover()).present, isFalse);
      expect(
        () => engine.extract(stego: noiseCover(), password: 'anything'),
        throwsA(isA<StegoFormatException>()),
      );
    });

    test('oversized payloads are refused', () {
      final cover = noiseCover(width: 64, height: 64);
      expect(
        () => engine.embed(
          cover: cover,
          payload: Uint8List(10000),
          password: 'pw',
          isFilePayload: false,
        ),
        throwsA(isA<StegoFormatException>()),
      );
    });

    test('alpha is never touched and PSNR stays above 40 dB', () {
      final cover = noiseCover();
      final result = engine.embed(
        cover: cover,
        payload: utf8.encode('visual check'),
        password: 'pw-visual',
        isFilePayload: false,
      );
      for (var y = 0; y < cover.height; y += 5) {
        for (var x = 0; x < cover.width; x += 5) {
          expect(
            result.image.getPixel(x, y).a.toInt(),
            cover.getPixel(x, y).a.toInt(),
            reason: 'alpha must never be used as a payload channel',
          );
        }
      }
      final diff = LSBStegoEngine.diff(cover, result.image);
      expect(diff.maxChannelDelta, lessThanOrEqualTo(1));
      expect(diff.psnrDb, greaterThan(40));
    });
  });
}
