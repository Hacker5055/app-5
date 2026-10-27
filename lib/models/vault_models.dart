// vault_models.dart — plain data objects shared by the controller and the UI.

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/ExifCleanerService.dart';
import '../core/JpegMeta.dart';
import '../core/LSBStegoEngine.dart';
import '../core/StegoFormat.dart';

/// One image loaded into the scrub queue.
class ScanItem {
  ScanItem({
    required this.name,
    required this.originalBytes,
    required this.audit,
    required this.previewBytes,
    this.clean,
    this.busy = false,
  });

  final String name;
  final Uint8List originalBytes;
  final MediaAudit audit;

  /// Downscaled PNG used for thumbnails and the on-screen preview.
  final Uint8List previewBytes;

  CleanResult? clean;
  bool busy;

  bool get isCleaned => clean != null;
  int get tagCount => audit.entries.length;
  int get sensitiveCount => audit.sensitiveCount;
  GpsPoint? get gps => audit.gps;

  /// Identity-bearing entries still present after the scrub (JFIF/ICC colour
  /// markers are harmless and intentionally kept).
  int get remainingIdentityTags =>
      clean?.remainingIdentityEntries.length ?? audit.entries.length;
}

/// Payload kind for the encoder screen.
enum PayloadKind { text, file }

class VaultFile {
  const VaultFile({required this.name, required this.mimeType, required this.bytes});
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Cover image + the metrics the capacity calculator needs.
class CoverImage {
  const CoverImage({
    required this.name,
    required this.image,
    required this.previewBytes,
    this.sourceBytes,
  });

  final String name;

  /// Full-resolution raster that actually receives the LSB payload.
  final img.Image image;

  /// Downscaled PNG for the on-screen preview (keeps the widget tree light).
  final Uint8List previewBytes;
  final Uint8List? sourceBytes;

  int get width => image.width;
  int get height => image.height;
}

/// A finished stego container.
class StegoContainer {
  const StegoContainer({
    required this.pngBytes,
    required this.image,
    required this.previewBytes,
    required this.metrics,
    required this.diff,
    required this.fileName,
    required this.depth,
    required this.payloadBytes,
  });

  final Uint8List pngBytes;
  final img.Image image;

  /// Downscaled preview of the container (identical pixels, smaller memory).
  final Uint8List previewBytes;
  final EmbedResult metrics;
  final StegoDiff diff;
  final String fileName;
  final int depth;
  final int payloadBytes;

  double get psnr => diff.psnrDb;
  double get utilisation => metrics.utilisation;
}

/// A container loaded into the decoder.
class DecodeTarget {
  const DecodeTarget({
    required this.name,
    required this.bytes,
    required this.image,
    required this.presence,
  });

  final String name;
  final Uint8List bytes;
  final img.Image image;
  final ContainerPresence presence;

  bool get hasContainer => presence.present;
  int get depth => presence.depth;
}

class RevealedPayload {
  const RevealedPayload({
    required this.text,
    required this.file,
    required this.header,
    required this.depth,
    required this.elapsed,
  });

  final String text;
  final VaultFile? file;
  final StegoHeader header;
  final int depth;
  final Duration elapsed;

  bool get isFile => file != null;
}
