# SGV-1 Container Specification

`Exif Cleaner & Stego Vault` hides a single, authenticated payload inside the RGB
channels of a PNG/BMP container. The format below is implemented **identically**
in three places and must stay bit-compatible:

| Implementation | File |
| --- | --- |
| Flutter / Dart | `lib/core/LSBStegoEngine.dart`, `lib/core/CryptoService.dart` |
| Browser preview (JS) | `preview/js/crypto-core.js`, `preview/js/stego-engine.js` |
| Tests | `test/stego_roundtrip_test.dart` |

## 1. Bit placement

* Channels used: **R, G, B** (alpha is never touched, so transparency survives).
* Traversal: row-major, `x = 0..width-1`, `y = 0..height-1`.
* Bit depth: **1 LSB** (`depth = 1`) or **2 LSB** (`depth = 2`) per channel.
* Within a channel value, bits are consumed **most-significant-first**
  (`depth = 2` order: bit1, then bit0).
* Serialisation of the payload stream: each byte is written **most-significant bit
  first** over consecutive channel positions.
* The remaining capacity is padded with **cryptographically random** bits, so the
  ciphertext boundary is not visible in a histogram/LSB-plane attack.

Capacity (bytes) = `floor(width * height * 3 * depth / 8)`.

## 2. Header (38 bytes, plaintext)

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 4 | `magic` | ASCII `SGV1` (`53 47 56 31`) |
| 4 | 1 | `version` | `0x01` |
| 5 | 1 | `flags` | bit0 = payload is a file, bit1 = 2-bit LSB mode, rest reserved `0` |
| 6 | 4 | `cipherLen` | uint32 **big-endian**, length of ciphertext **including** the 16-byte GCM tag |
| 10 | 16 | `salt` | PBKDF2 salt |
| 26 | 12 | `iv` | AES-GCM nonce |
| 38 | `cipherLen` | `ciphertext` | AES-256-GCM output + tag |

**AAD** (additional authenticated data) = `header[0..10)` (magic, version, flags,
cipherLen). A tampered header therefore fails GCM authentication, and a truncated
or foreign image fails the magic check.

## 3. Key derivation & cipher

```
key = PBKDF2-HMAC-SHA256(password = UTF-8(password), salt = 16 bytes,
                         iterations = 100_000, dkLen = 32)
ct  = AES-256-GCM(key, iv = 12 bytes, aad = header[0..10), plaintext)
```

## 4. Plaintext framing

Text payload (`flags.bit0 = 0`): the UTF-8 bytes of the message.

File payload (`flags.bit0 = 1`):

```
uint16 nameLen (BE) | nameLen bytes UTF-8 filename
uint16 mimeLen (BE) | mimeLen bytes UTF-8 mime type
... raw file bytes ...
```

## 5. Decoder algorithm

1. Read 38 header bytes at `depth = 1`; if `magic != SGV1`, retry at `depth = 2`.
2. Validate `cipherLen` against available capacity; reject absurd lengths.
3. Derive the key, attempt GCM decryption with AAD.
   * Tag mismatch -> **"Wrong password or corrupted container"**.
4. Return the decoded text/file, flags and header diagnostics.

Because the header is authenticated, a wrong password is reported immediately and
deterministically — no fuzzy heuristics.
