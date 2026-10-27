# Exif Cleaner & Stego Vault

**منظف البصمات الرقمية والتشفير المخفي**

A standalone, **100 % offline** Android application (Flutter) that (1) strips every
identifying tag from a photo — EXIF, XMP, IPTC, GPS, camera/lens serial numbers —
and (2) hides an AES-256-GCM-encrypted payload inside the RGB least-significant
bits of a cover image, then gets it back on demand.

The app declares **no `INTERNET` permission**, so the operating system — not
application logic — guarantees that no photo, key or payload can ever leave the
device.

| | |
| --- | --- |
| Flutter app | `lib/` (Dart 3, Flutter 3.27+, ARM64 release APK) |
| Live browser build | `preview/index.html` — the same engine in plain JavaScript, no build step, no network |
| Container spec | [`docs/STEGO_FORMAT.md`](docs/STEGO_FORMAT.md) |
| Build guide | [`docs/BUILD.md`](docs/BUILD.md) |
| Threat model | [`docs/SECURITY.md`](docs/SECURITY.md) |

---

## 1. What it does

### Tab 1 · Exif Scrub & Share
* Drag-and-drop / picker for a **single image or a whole batch** (JPEG, PNG, BMP, WebP).
* Full metadata audit: IFD0, Exif sub-IFD, GPS sub-IFD, IFD1 thumbnail tags, XMP,
  IPTC-IIM, JPEG comments, PNG `tEXt`/`iTXt`/`zTXt`/`eXIf`/`tIME`.
* **GPS card** with a custom-painted offline map (no tile server exists in this app)
  showing the embedded fix, plus a "pin destroyed" state after scrubbing.
* **Before vs After comparison table** — every tag is listed with its value and the
  mark it gets after the strip (`STRIPPED`, or `KEPT` for harmless colour markers).
* One-tap **Scrub & strip all meta**, batch mode, export & share.

**JPEG scrubbing is lossless**: APP1 (EXIF + XMP), APP13 (IPTC), COM and MPF
segments are cut out of the container and the entropy-coded scan is copied
verbatim. No re-compression, no generation loss, pixel-for-pixel identical output —
proven by a test that decodes both files with ImageMagick and compares every byte.
PNG/BMP/WebP are re-encoded from decoded pixels, which is equally lossless for
PNG/BMP and drops every ancillary chunk.

### Tab 2 · Stego Encoder (hide payload)
* Cover picker or generated mock scene; **1-bit or 2-bit LSB** per RGB channel.
* **Real-time capacity calculator**: maximum hidden bytes, used bytes, free
  headroom, utilisation meter and an estimated PSNR for the current fill level.
* Text or file payload (the file keeps its name + MIME type through the round-trip).
* Passphrase field with a strength meter; PBKDF2-HMAC-SHA256 (100 000 rounds) →
  AES-256-GCM with a random 16-byte salt and 12-byte nonce per container.
* **Instant preview comparison slider** plus a HUD: PSNR, max channel Δ, changed
  channels, embed time. At 1-bit the maximum deviation is 1/255 — invisible.

### Tab 3 · Stego Decoder (reveal payload)
* Loads a container and **immediately reports whether an `SGV1` payload exists**
  (magic header + authenticated length field), including its bit depth and size —
  before any password is typed.
* Passphrase → GCM tag verification. A wrong password is reported
  deterministically ("wrong passphrase"), never as corrupted output.
* Revealed text: copy / export. Revealed file: name, MIME type, export.
* Diagnostics panel: magic, version, mode, salt/IV sizes, PBKDF2 iterations, elapsed.

### Mock Data Mode
A toggle (rail switch, or `--dart-define=MOCK_DATA=true`) that synthesises a
photograph **and a genuinely EXIF/XMP/IPTC-bearing JPEG** at runtime, so every
screen can be demonstrated on a fresh emulator with an empty gallery. The mock
JPEG is produced with a real TIFF/IFD writer — the same parser that handles a
camera's file handles the mock, so no code path is faked. In the browser build it
also generates a ready-to-decode container with the passphrase `stegovault`.

---

## 2. Architecture

```
lib/
├── main.dart                     App bootstrap, dark-only theme, mock-data flag
├── core/
│   ├── CryptoService.dart        AES-256-GCM + PBKDF2-HMAC-SHA256 (PointyCastle)
│   ├── StegoFormat.dart          SGV-1 header, capacity maths, file framing
│   ├── LSBStegoEngine.dart       Multi-plane LSB embed / extract / detect / PSNR
│   ├── JpegMeta.dart             Byte-level EXIF/XMP/IPTC reader + lossless JPEG strip
│   ├── ExifCleanerService.dart   Format dispatch, scrub report, native verification
│   ├── MockSource.dart           Procedural photo + real EXIF/TIFF segment builder
│   └── MediaStore.dart           File picking / saving / sharing (local only)
├── models/vault_models.dart      ScanItem, CoverImage, StegoContainer, DecodeTarget…
├── state/VaultController.dart    Single source of truth (ChangeNotifier)
├── theme/CyberTheme.dart         Cyber Obsidian palette + glass decoration + typography
└── ui/
    ├── AppShell.dart             Side rail / bottom tabs, status bar, mock switch
    ├── screens/                  ExifScreen · EncodeScreen · DecodeScreen
    └── widgets/                  GlassCard, DropZone, CapacityMeter, MetadataTable,
                                  GpsMapView (CustomPainter), ComparisonSlider, ScanBeam
android/
└── app/src/main/
    ├── AndroidManifest.xml       Media permissions, **no INTERNET**
    └── kotlin/…/MainActivity.kt  MethodChannel bridge to androidx.exifinterface
preview/                          Browser build of the identical engine (runs offline)
test/                             Node engine suite + Flutter unit tests
docs/                             Format spec, build guide, threat model
```

Design rules the code follows:

* **The engine is UI-free.** `core/` only knows bytes and pixels, so it runs in
  unit tests, on device and in the browser port.
* **One source of truth.** Screens are pure functions of `VaultController`; no
  business logic hides in widgets.
* **No hidden I/O.** `MediaStore` is the only file-system boundary; there is no
  HTTP client anywhere in the dependency tree.

---

## 3. Cryptography & container format (summary)

```
header (38 B, authenticated as AAD)
  0  magic      "SGV1"
  4  version    0x01
  5  flags      bit0 = file payload, bit1 = 2-bit LSB
  6  cipherLen  uint32 BE (GCM ciphertext + 16-byte tag)
 10  salt       16 random bytes
 26  iv         12 random bytes
body
  38  ciphertext ‖ GCM tag

key = PBKDF2-HMAC-SHA256(UTF-8(password), salt, 100_000, 32)
ct  = AES-256-GCM(key, iv, aad = header[0..10), plaintext)
```

Full spec, including bit ordering and the file-frame layout: [`docs/STEGO_FORMAT.md`](docs/STEGO_FORMAT.md).

Security properties:

* Confidentiality: AES-256-GCM, fresh 256-bit salt and 96-bit nonce per container.
* Integrity: the header is authenticated, so tampering with the length, flags or
  salt invalidates decryption instead of crashing the parser.
* Password **never** stored; keys exist only for the duration of one operation.
* Unused LSB capacity is filled with random bits, so the ciphertext boundary is not
  visible in an LSB-plane or histogram analysis.
* Alpha is never used as a carrier, so transparency survives untouched.

---

## 4. Build the APK

Prerequisites: Flutter ≥ 3.27, Android SDK 34, JDK 17, NDK (installed by Flutter).

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# → build/app/outputs/flutter-apk/app-release.apk
```

Other useful commands:

```bash
flutter analyze
flutter test
flutter build appbundle --release --target-platform android-arm64   # Play bundle
flutter build apk --release --split-per-abi                        # per-ABI APKs
flutter install --release
```

Release signing: create `android/key.properties` (git-ignored)

```properties
storeFile=../keystore/stego-vault.jks
storePassword=…
keyAlias=stego-vault
keyPassword=…
```

Without it the release build falls back to the debug key so `flutter build apk
--release` still works. Full details and troubleshooting: [`docs/BUILD.md`](docs/BUILD.md).

---

## 5. Run the browser build (zero tooling)

```bash
cd preview
python3 -m http.server 8080      # or: npx serve .
# open http://localhost:8080
```

`preview/index.html` also works straight from the file system — there is no build
step, no CDN, no font download and no network access of any kind. It implements
the same SGV-1 container, the same PBKDF2/AES-GCM primitives (pure JS, verified
against Node's native crypto) and the same JPEG segment surgery, so a container
written in the browser decodes in the Flutter app and vice versa.

---

## 6. Tests

```bash
node --test test/preview_engine.test.mjs   # engine suite for the browser build
flutter test                               # Dart unit tests (crypto, LSB, EXIF)
```

The Node suite (25 tests) cross-checks:

* SHA-256 / PBKDF2 / AES-256-GCM against **Node's OpenSSL-backed WebCrypto** in both
  directions, plus the FIPS-197 AES-256 block vector;
* the PNG encoder's zlib stream against **Node's zlib** and its pixels against
  **ImageMagick**;
* that JPEG scrubbing is **pixel-identical** (ImageMagick decode of before/after);
* LSB round-trips at 1-bit and 2-bit, wrong-password rejection, single-bit tamper
  rejection, alpha preservation, capacity limits, random padding and container
  detection.

All 25 tests pass on the current tree.

---

## 7. Permissions

| Permission | Why | Scope |
| --- | --- | --- |
| `READ_MEDIA_IMAGES` | pick photos to audit / hide payloads in | Android 13+ |
| `READ_MEDIA_VISUAL_USER_SELECTED` | partial photo access prompt | Android 14+ |
| `READ_EXTERNAL_STORAGE` | legacy gallery access | `maxSdkVersion=32` |
| `WRITE_EXTERNAL_STORAGE` | save cleaned / encoded files | `maxSdkVersion=28` |
| **`INTERNET`** | **not declared — deliberately** | — |

On Android 10+ exports go through the Storage Access Framework / MediaStore, so no
write permission is requested at all on modern devices. Backup and device-transfer
are disabled (`allowBackup=false`, all domains excluded in
`res/xml/data_extraction_rules.xml`), so the vault never leaves the device through
Google's transport either.

> Note: `flutter run` (debug) adds the INTERNET permission automatically for the
> Dart VM service and hot reload. Release builds — the artefact you distribute —
> contain none. Verify with
> `aapt dump permissions build/app/outputs/flutter-apk/app-release.apk`.

---

## 8. Limitations & honest notes

* **JPEG lossy sources**: a JPEG cannot be used as a *stego cover* — its LSB plane
  is destroyed by re-compression. The encoder always emits PNG. Scrubbing a JPEG
  never re-compresses it.
* The 2-bit mode deviates by at most 3/255 per channel. It is invisible to the eye
  but detectable by dedicated steganalysis; 1-bit with low fill is the stealthier
  choice. Neither mode is a substitute for end-to-end encryption of the medium.
* Steganography is **not** a replacement for secure transport: anyone who knows the
  format can see that an `SGV1` container exists (the header is plaintext by
  design, so "is there a message?" is answered instantly). The *content* is
  protected by the passphrase.
* PBKDF2 with 100 000 rounds costs ~200 ms on a mid-range ARM64 phone; it runs on
  the platform thread with a progress indicator. (Moving it to an isolate is a
  drop-in change if you need to embed during a heavy animation.)
