// CryptoService.dart
//
// AES-256-GCM authenticated encryption with a PBKDF2-HMAC-SHA256 derived key.
// Pure Dart (PointyCastle) so the app keeps a hard offline boundary: no network,
// no platform keystore dependency, no native crypto FFI.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Result of a successful decryption.
class DecryptedPayload {
  const DecryptedPayload(this.bytes, this.isFile);

  final Uint8List bytes;
  final bool isFile;

  String get text => utf8.decode(bytes, allowMalformed: true);
}

class CryptoException implements Exception {
  CryptoException(this.message);
  final String message;
  @override
  String toString() => 'CryptoException: $message';
}

class CryptoService {
  CryptoService({
    this.iterations = 100000,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// PBKDF2 work factor. 100k per the product spec.
  final int iterations;
  final Random _random;

  static const int keyLengthBytes = 32; // AES-256
  static const int saltLengthBytes = 16;
  static const int ivLengthBytes = 12; // 96-bit GCM nonce
  static const int tagLengthBytes = 16; // 128-bit auth tag

  Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// PBKDF2-HMAC-SHA256(password, salt, 100_000, 32).
  Uint8List deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keyLengthBytes));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Encrypts [plaintext] and returns an [EncryptedBlob] holding salt, iv and
  /// ciphertext (tag appended).
  EncryptedBlob encrypt({
    required String password,
    required List<int> plaintext,
    required List<int> associatedData,
    Uint8List? salt,
    Uint8List? iv,
  }) {
    final useSalt = salt ?? randomBytes(saltLengthBytes);
    final useIv = iv ?? randomBytes(ivLengthBytes);
    final key = deriveKey(password, useSalt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          tagLengthBytes * 8,
          useIv,
          Uint8List.fromList(associatedData),
        ),
      );

    final ciphertext = cipher.process(Uint8List.fromList(plaintext));
    return EncryptedBlob(
      salt: useSalt,
      iv: useIv,
      ciphertext: ciphertext,
      iterations: iterations,
    );
  }

  /// Throws [CryptoException] when the GCM tag does not verify (wrong password
  /// or tampered container).
  Uint8List decrypt({
    required String password,
    required Uint8List salt,
    required Uint8List iv,
    required Uint8List ciphertext,
    required List<int> associatedData,
  }) {
    if (ciphertext.length <= tagLengthBytes) {
      throw CryptoException('Ciphertext shorter than the authentication tag.');
    }
    final key = deriveKey(password, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          tagLengthBytes * 8,
          iv,
          Uint8List.fromList(associatedData),
        ),
      );
    try {
      return cipher.process(ciphertext);
    } catch (_) {
      throw CryptoException('Authentication failed: wrong password or corrupted container.');
    }
  }

  /// Convenience helper used by the UI: constant-ish time string compare for
  /// integrity tags / passphrase confirmation.
  static bool secureEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class EncryptedBlob {
  const EncryptedBlob({
    required this.salt,
    required this.iv,
    required this.ciphertext,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List iv;
  final Uint8List ciphertext;
  final int iterations;

  int get totalBytes => salt.length + iv.length + ciphertext.length;
}
