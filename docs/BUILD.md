# Building the release APK

Target artefact: **ARM64 / v8a optimised release APK**, no network permission, no
debug symbols.

## 1. Prerequisites

| Tool | Version | Note |
| --- | --- | --- |
| Flutter | ≥ 3.27 (stable) | `flutter --version` |
| Dart | ≥ 3.4 | ships with Flutter |
| Android SDK | Platform 34 + Build-Tools 34 | `sdkmanager "platforms;android-34" "build-tools;34.0.0"` |
| JDK | 17 | required by AGP 8.3 |
| NDK | whatever `flutter.ndkVersion` resolves to | installed on first build |

```bash
flutter doctor -v          # must show a green Android toolchain
flutter config --android-sdk "$ANDROID_SDK_ROOT"
```

## 2. The one command

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Output:

```
build/app/outputs/flutter-apk/app-release.apk
```

The `ndk { abiFilters "arm64-v8a" }` block in `android/app/build.gradle` keeps the
APK ARM64-only even if `--target-platform` is omitted, so the artefact cannot
accidentally ship 32-bit or x86 code.

### Other flavours

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
flutter build appbundle --release --target-platform android-arm64
flutter build apk --debug --target-platform android-arm64      # local testing only
```

## 3. Signing

Create a keystore once (keep it out of git):

```bash
keytool -genkey -v -keystore android/keystore/stego-vault.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias stego-vault
```

`android/key.properties` (already git-ignored):

```properties
storeFile=../keystore/stego-vault.jks
storePassword=changeit
keyAlias=stego-vault
keyPassword=changeit
```

`app/build.gradle` picks this up automatically; without it the release build signs
with the debug key so CI can still produce an installable APK.

## 4. Verify the artefact

```bash
# permissions: must NOT list android.permission.INTERNET
$ANDROID_SDK_ROOT/build-tools/34.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk

# signature
$ANDROID_SDK_ROOT/build-tools/34.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

# ABIs
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep lib/
#   -> only lib/arm64-v8a/…
```

## 5. Run with Mock Data Mode

Emulators have empty galleries; the app can generate its own demo material.

```bash
flutter run --release --dart-define=MOCK_DATA=true
# or flip the "Mock Data Mode" switch in the side rail at runtime
```

The mock path is not a stub: it writes a real JPEG with real EXIF/XMP/IPTC
segments and builds real SGV-1 containers, so every screen exercises production
code.

## 6. Size optimisation

The release build already enables R8 (`minifyEnabled`), resource shrinking and
`debugSymbolLevel NONE`. Typical ARM64 release APK: **~12–16 MB**.

```bash
flutter build apk --release --target-platform android-arm64 --obfuscate \
  --split-debug-info=build/symbols
```

## 7. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NDK not configured` | `sdkmanager "ndk;26.1.10909125"`, or set `android.ndkVersion` in `app/build.gradle` |
| `minSdk 24` conflict from a plugin | raise `minSdk` to 26 in `defaultConfig` (the app itself supports 24) |
| `Execution failed for task ':app:lintVitalRelease'` | already disabled in `lint { checkReleaseBuilds = false }` |
| `file_picker` requires compileSdk 34 | keep `compileSdk = 34` |
| Gradle daemon OOM | `android/gradle.properties` already sets `-Xmx4G`; lower it on small CI runners |
| Build ok but app shows a black screen | check that `MainActivity` extends `FlutterActivity` and that `flutterEmbedding=2` is in the manifest |

## 8. Continuous integration sketch

```yaml
- uses: subosito/flutter-action@v2
  with: { flutter-version: '3.27.x', channel: stable }
- run: flutter pub get
- run: flutter analyze
- run: flutter test
- run: node --test test/preview_engine.test.mjs
- run: flutter build apk --release --target-platform android-arm64
- uses: actions/upload-artifact@v4
  with: { name: stego-vault-arm64, path: build/app/outputs/flutter-apk/app-release.apk }
```
