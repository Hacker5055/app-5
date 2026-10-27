// VaultController.dart
//
// Single source of truth for all three screens. The UI listens with
// AnimatedBuilder / ListenableBuilder; the controller owns the engine, the file
// boundary and every user-visible status message.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/CryptoService.dart';
import '../core/ExifCleanerService.dart';
import '../core/JpegMeta.dart';
import '../core/LSBStegoEngine.dart';
import '../core/MediaStore.dart';
import '../core/MockSource.dart';
import '../core/StegoFormat.dart';
import '../models/vault_models.dart';

class VaultController extends ChangeNotifier {
  VaultController({MediaStore? mediaStore}) : media = mediaStore ?? const MediaStore();

  final MediaStore media;
  final CryptoService crypto = CryptoService(iterations: 100000);
  late final LSBStegoEngine engine = LSBStegoEngine(crypto);
  final ExifCleanerService cleaner = ExifCleanerService();
  final MockSource mockSource = MockSource();

  // ------------------------------------------------------------------ state
  bool mockMode = false;
  bool busy = false;
  String status = 'Engine idle — no image loaded';

  final List<ScanItem> items = <ScanItem>[];
  int activeIndex = 0;

  CoverImage? cover;
  int depth = 1;
  PayloadKind payloadKind = PayloadKind.text;
  String payloadText = '';
  VaultFile? payloadFile;
  String encodePassword = '';
  StegoContainer? container;

  DecodeTarget? decodeTarget;
  RevealedPayload? revealed;
  String? decodeError;
  String lastDemoPassword = '';

  ScanItem? get activeItem {
    if (items.isEmpty) return null;
    final index = activeIndex.clamp(0, items.length - 1);
    return items[index];
  }

  int get totalTags => items.fold<int>(0, (sum, item) => sum + item.tagCount);
  int get cleanedCount => items.where((item) => item.isCleaned).length;

  // ------------------------------------------------------------- capacities
  int get capacityBytes => cover == null
      ? 0
      : StegoFormat.capacityBytes(width: cover!.width, height: cover!.height, depth: depth);

  int get usableBytes => cover == null
      ? 0
      : StegoFormat.usablePayloadBytes(width: cover!.width, height: cover!.height, depth: depth);

  int get payloadSizeBytes {
    if (payloadKind == PayloadKind.file && payloadFile != null) {
      // nameLen(2) + name + mimeLen(2) + mime + raw bytes — see StegoFormat.frameFile.
      return payloadFile!.bytes.length + payloadFile!.name.length + payloadFile!.mimeType.length + 4;
    }
    return utf8.encode(payloadText).length;
  }

  int get containerOverheadBytes => StegoFormat.headerLength + CryptoService.tagLengthBytes;

  int get usedBytes => payloadSizeBytes == 0 ? 0 : payloadSizeBytes + containerOverheadBytes;

  double get utilisation => capacityBytes == 0 ? 0 : (usedBytes / capacityBytes).clamp(0.0, 1.0);

  bool get payloadFits => payloadSizeBytes > 0 && payloadSizeBytes <= usableBytes;

  bool get canEmbed => cover != null && payloadFits && encodePassword.isNotEmpty && !busy;

  /// Rough PSNR the user can expect at the current fill level (>= 45 dB is
  /// invisible to the eye; 1-bit at moderate fill lands near 50 dB).
  double get estimatedPsnr {
    if (capacityBytes == 0 || usedBytes == 0) return 99;
    final fill = (usedBytes / capacityBytes).clamp(0.0, 1.0);
    return 60 - 10 * (fill * 2.2).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------- primitives
  void _setBusy(String message) {
    busy = true;
    status = message;
    notifyListeners();
  }

  void _settle(String message) {
    busy = false;
    status = message;
    notifyListeners();
  }

  /// Yields one frame so a spinner can paint before a synchronous crypto block
  /// (PBKDF2 with 100 000 rounds costs ~200 ms on a mid-range ARM64 device).
  Future<void> _yield() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Downscaled PNG of an [img.Image] for display.
  Uint8List _pngPreview(img.Image image, {int maxEdge = 1200}) {
    img.Image scaled = image.convert(numChannels: 4);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxEdge) {
      scaled = img.copyResize(
        scaled,
        width: (image.width * maxEdge / longest).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodePng(scaled));
  }

  img.Image _previewOf(Uint8List bytes, {int maxEdge = 1400}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return img.Image(width: 1, height: 1);
    if (decoded.width <= maxEdge && decoded.height <= maxEdge) {
      return decoded.convert(numChannels: 4);
    }
    final scale = maxEdge / (decoded.width > decoded.height ? decoded.width : decoded.height);
    return img.copyResize(
      decoded.convert(numChannels: 4),
      width: (decoded.width * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  // ============================================================ TAB 1: EXIF
  Future<void> addImages(List<PickedBlob> blobs) async {
    if (blobs.isEmpty) return;
    _setBusy('Reading ${blobs.length} image(s)…');
    for (final blob in blobs) {
      try {
        final audit = cleaner.scan(blob.bytes, fileName: blob.name);
        items.add(
          ScanItem(
            name: blob.name,
            originalBytes: blob.bytes,
            audit: audit,
            previewBytes: _pngPreview(_previewOf(blob.bytes)),
          ),
        );
      } catch (error) {
        status = 'Skipped ${blob.name}: $error';
      }
    }
    activeIndex = items.isEmpty ? 0 : items.length - 1;
    _settle('Audited ${items.length} image(s) — $totalTags metadata entries found');
  }

  Future<void> pickImages() async {
    try {
      final blobs = await media.pickImages();
      await addImages(blobs);
    } catch (error) {
      _settle('Picker failed: $error');
    }
  }

  /// Mock Data Mode: synthesise a photo plus a real EXIF/XMP/IPTC-bearing JPEG.
  Future<void> loadMockPhoto({bool silent = false}) async {
    if (!silent) _setBusy('Generating synthetic photo + EXIF…');
    final photo = mockSource.photo(variant: items.length % 3);
    items.add(
      ScanItem(
        name: photo.fileName,
        originalBytes: photo.jpegBytes,
        audit: cleaner.scan(photo.jpegBytes, fileName: photo.fileName),
        previewBytes: _pngPreview(photo.image),
      ),
    );
    activeIndex = items.length - 1;
    _settle('Mock photo loaded — ${items.last.tagCount} metadata entries incl. GPS');
  }

  void selectItem(int index) {
    if (index < 0 || index >= items.length) return;
    activeIndex = index;
    notifyListeners();
  }

  Future<void> scrubActive() async {
    final item = activeItem;
    if (item == null || item.isCleaned || item.busy) return;
    await _scrub(item);
    _settle('Scrubbed ${item.name} — ${item.remainingIdentityTags} identity tags left');
  }

  Future<void> scrubAll() async {
    if (items.isEmpty) return;
    _setBusy('Batch scrubbing ${items.length} image(s)…');
    for (final item in items) {
      if (!item.isCleaned) await _scrub(item, notify: false);
    }
    _settle('Batch scrub complete — ${cleanedCount}/${items.length} clean');
  }

  Future<void> _scrub(ScanItem item, {bool notify = true}) async {
    item.busy = true;
    if (notify) {
      busy = true;
      status = 'Stripping ${item.name}…';
      notifyListeners();
    }
    await _yield();
    try {
      item.clean = await cleaner.clean(item.originalBytes, fileName: item.name);
    } on CleanException catch (error) {
      item.busy = false;
      if (notify) _settle(error.message);
      return;
    }
    item.busy = false;
    if (notify) {
      busy = false;
      status = 'Metadata stripped from ${item.name}';
      notifyListeners();
    }
  }

  List<String> reportFor(ScanItem item) {
    final clean = item.clean;
    if (clean == null) return const <String>[];
    final removed = clean.removed.length;
    final sensitive = clean.removed.where((entry) => entry.sensitive).length;
    final hadSerial = item.audit.entries.any((e) => e.tag.toLowerCase().contains('serial'));
    return <String>[
      'Removed $removed metadata entries ($sensitive sensitive)',
      item.audit.hasGps ? 'GPS latitude/longitude/altitude destroyed' : 'No GPS fix was present',
      hadSerial ? 'Camera + lens serial numbers removed' : 'No serial numbers found',
      clean.lossless
          ? 'Pixel data untouched — segments cut from the container (lossless)'
          : 'Re-encoded as PNG from decoded pixels (visually identical)',
      'Re-scan after strip: ${clean.remainingIdentityEntries.length} identity tag(s) remaining',
      clean.nativeTagsAfter != null
          ? 'androidx.exifinterface re-read: ${clean.nativeTagsAfter!.isEmpty ? '0 attributes' : '${clean.nativeTagsAfter!.length} attribute(s) left'}'
          : 'androidx.exifinterface bridge unavailable in this build',
      'Container ${clean.before.sizeBytes} B → ${clean.bytes.length} B',
    ];
  }

  Future<void> saveCleaned() async {
    final item = activeItem;
    final clean = item?.clean;
    if (clean == null) return;
    final path = await media.saveBytes(clean.bytes, clean.fileName);
    _settle(path == null ? 'Save cancelled' : 'Saved ${clean.fileName}');
  }

  Future<void> shareCleaned() async {
    final item = activeItem;
    final clean = item?.clean;
    if (clean == null) return;
    await media.shareBytes(clean.bytes, clean.fileName, text: 'Metadata stripped with Stego Vault.');
    _settle('Share sheet opened for ${clean.fileName}');
  }

  // ========================================================== TAB 2: ENCODE
  Future<void> pickCover() async {
    try {
      final blobs = await media.pickImages(multiple: false);
      if (blobs.isEmpty) return;
      _setBusy('Decoding cover…');
      final decoded = img.decodeImage(blobs.first.bytes);
      if (decoded == null) {
        _settle('Unsupported image format');
        return;
      }
      final image = decoded.convert(numChannels: 4);
      cover = CoverImage(
        name: blobs.first.name,
        image: image,
        previewBytes: _pngPreview(image),
        sourceBytes: blobs.first.bytes,
      );
      container = null;
      _settle('Cover ready — ${usableBytes} B usable capacity at $depth-bit');
    } catch (error) {
      _settle('Cover load failed: $error');
    }
  }

  Future<void> useMockCover({bool silent = false}) async {
    if (!silent) _setBusy('Rendering synthetic cover…');
    final image = mockSource.coverImage(variant: container == null ? 1 : 2);
    cover = CoverImage(
      name: 'mock_cover.png',
      image: image,
      previewBytes: _pngPreview(image),
    );
    container = null;
    _settle('Synthetic cover ready — ${usableBytes} B usable capacity');
  }

  void setDepth(int value) {
    depth = value == 2 ? 2 : 1;
    notifyListeners();
  }

  void setPayloadKind(PayloadKind kind) {
    payloadKind = kind;
    notifyListeners();
  }

  void setPayloadText(String value) {
    payloadText = value;
    notifyListeners();
  }

  Future<void> pickPayloadFile() async {
    final picked = await media.pickPayloadFile();
    if (picked == null) return;
    payloadFile = VaultFile(
      name: picked.name,
      mimeType: picked.mimeType ?? 'application/octet-stream',
      bytes: picked.bytes,
    );
    payloadKind = PayloadKind.file;
    notifyListeners();
  }

  void setPassword(String value) {
    encodePassword = value;
    notifyListeners();
  }

  Future<void> embed() async {
    if (cover == null) {
      _settle('Select a cover image first');
      return;
    }
    if (encodePassword.isEmpty) {
      _settle('A passphrase is required');
      return;
    }
    if (!payloadFits) {
      _settle('Payload does not fit at $depth-bit — reduce it or switch to 2-bit');
      return;
    }
    _setBusy('Deriving key (PBKDF2 100k) and embedding…');
    await _yield();
    try {
      final isFile = payloadKind == PayloadKind.file && payloadFile != null;
      final payload = isFile
          ? StegoFormat.frameFile(
              fileName: payloadFile!.name,
              mimeType: payloadFile!.mimeType,
              data: payloadFile!.bytes,
            )
          : Uint8List.fromList(utf8.encode(payloadText));
      final result = engine.embed(
        cover: cover!.image,
        payload: payload,
        password: encodePassword,
        isFilePayload: isFile,
        depth: depth,
      );
      container = StegoContainer(
        pngBytes: result.pngBytes,
        image: result.image,
        previewBytes: _pngPreview(result.image),
        metrics: result,
        diff: LSBStegoEngine.diff(cover!.image, result.image),
        fileName: '${_baseName(cover!.name)}_stego.png',
        depth: depth,
        payloadBytes: payloadSizeBytes,
      );
      _settle('Container written — ${result.pngBytes.length} B PNG, $payloadSizeBytes B hidden');
    } on StegoFormatException catch (error) {
      _settle(error.message);
    } catch (error) {
      _settle('Embedding failed: $error');
    }
  }

  Future<void> saveContainer() async {
    final value = container;
    if (value == null) return;
    final path = await media.saveBytes(value.pngBytes, value.fileName);
    _settle(path == null ? 'Save cancelled' : 'Saved ${value.fileName}');
  }

  Future<void> shareContainer() async {
    final value = container;
    if (value == null) return;
    await media.shareBytes(value.pngBytes, value.fileName, text: 'SGV1 container — passphrase required.');
    _settle('Share sheet opened');
  }

  /// Hands the freshly built container to the decoder screen.
  void sendContainerToDecoder() {
    final value = container;
    if (value == null) return;
    decodeTarget = DecodeTarget(
      name: value.fileName,
      bytes: value.pngBytes,
      image: value.image,
      presence: engine.detect(value.image),
    );
    revealed = null;
    decodeError = null;
    lastDemoPassword = encodePassword;
    notifyListeners();
  }

  // ========================================================== TAB 3: DECODE
  Future<void> pickContainer() async {
    try {
      final blobs = await media.pickImages(multiple: false);
      if (blobs.isEmpty) return;
      await loadContainer(blobs.first);
    } catch (error) {
      _settle('Load failed: $error');
    }
  }

  Future<void> loadContainer(PickedBlob blob) async {
    _setBusy('Scanning for an SGV1 container…');
    final decoded = img.decodeImage(blob.bytes);
    if (decoded == null) {
      _settle('Unsupported image format');
      return;
    }
    final image = decoded.convert(numChannels: 4);
    decodeTarget = DecodeTarget(
      name: blob.name,
      bytes: blob.bytes,
      image: image,
      presence: engine.detect(image),
    );
    revealed = null;
    decodeError = null;
    _settle(
      decodeTarget!.hasContainer
          ? 'SGV1 signature found (${decodeTarget!.depth}-bit) — enter the passphrase'
          : 'No SGV1 signature in this image',
    );
  }

  /// Builds a ready-to-decode demo container so the flow can be previewed on any
  /// emulator without files.
  Future<void> loadMockContainer() async {
    _setBusy('Building mock container…');
    await _yield();
    const password = 'stegovault';
    const secret = 'Vault note #7 — handover at 21:30.\n'
        'The original photo was scrubbed before sharing.\n'
        'If you can read this, the LSB payload and the AES-256-GCM tag verified.';
    final scene = mockSource.coverImage(variant: 5);
    final result = engine.embed(
      cover: scene,
      payload: Uint8List.fromList(utf8.encode(secret)),
      password: password,
      isFilePayload: false,
    );
    final image = img.decodeImage(result.pngBytes)!;
    decodeTarget = DecodeTarget(
      name: 'mock_stego_container.png',
      bytes: result.pngBytes,
      image: image.convert(numChannels: 4),
      presence: engine.detect(image),
    );
    revealed = null;
    decodeError = null;
    lastDemoPassword = password;
    _settle('Mock container created — demo passphrase "$password"');
  }

  Future<void> reveal(String password) async {
    final target = decodeTarget;
    if (target == null) {
      _settle('Load a container first');
      return;
    }
    if (!target.hasContainer) {
      decodeError = 'No SGV1 container found in this image.';
      notifyListeners();
      return;
    }
    if (password.isEmpty) {
      decodeError = 'Enter the passphrase.';
      notifyListeners();
      return;
    }
    _setBusy('Deriving key (PBKDF2 100k)…');
    await _yield();
    try {
      final result = engine.extract(
        stego: target.image,
        password: password,
        onStage: (stage) {
          status = '$stage…';
          notifyListeners();
        },
      );
      final header = result.header;
      VaultFile? file;
      var text = '';
      if (header.isFile) {
        final framed = StegoFormat.unframeFile(result.payload);
        file = VaultFile(name: framed.fileName, mimeType: framed.mimeType, bytes: framed.data);
      } else {
        text = utf8.decode(result.payload, allowMalformed: true);
      }
      revealed = RevealedPayload(
        text: text,
        file: file,
        header: header,
        depth: result.depth,
        elapsed: result.elapsed,
      );
      decodeError = null;
      _settle('Payload revealed — GCM tag verified in ${result.elapsed.inMilliseconds} ms');
    } on CryptoException {
      revealed = null;
      decodeError = 'Wrong password — the authentication tag did not verify.';
      _settle('Decryption rejected');
    } on StegoFormatException catch (error) {
      revealed = null;
      decodeError = error.message;
      _settle('Decryption rejected');
    }
    notifyListeners();
  }

  Future<void> copyRevealed() async {
    final value = revealed;
    if (value == null) return;
    await media.copyText(value.isFile ? value.file!.name : value.text);
    _settle('Copied to clipboard');
  }

  Future<void> saveRevealed() async {
    final value = revealed;
    if (value == null) return;
    if (value.isFile) {
      await media.saveBytes(value.file!.bytes, value.file!.name);
    } else {
      await media.saveBytes(Uint8List.fromList(utf8.encode(value.text)), 'revealed_payload.txt');
    }
    _settle('Payload exported');
  }

  // -------------------------------------------------------------- mock mode
  Future<void> setMockMode(bool enabled) async {
    mockMode = enabled;
    notifyListeners();
    if (!enabled) {
      _settle('Mock Data Mode off — select real files to continue');
      return;
    }
    _setBusy('Mock Data Mode — generating samples…');
    if (items.isEmpty) await loadMockPhoto(silent: true);
    if (cover == null) await useMockCover(silent: true);
    if (decodeTarget == null) await loadMockContainer();
    _settle('Mock Data Mode on — synthetic photos with real EXIF bytes');
  }

  // ------------------------------------------------------------------ utils
  static String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

}
