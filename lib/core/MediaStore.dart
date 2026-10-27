// MediaStore.dart
//
// Thin, auditable boundary between the vault engine and the operating system.
// Everything is local: files picked from the gallery, saved to the app's own
// cache or to a user-chosen path, shared through the system share sheet. No
// socket, no HTTP client, no analytics.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PickedBlob {
  const PickedBlob({required this.name, required this.bytes, this.mimeType});
  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

class MediaStore {
  const MediaStore();

  static const Set<String> imageExtensions = <String>{
    'jpg', 'jpeg', 'png', 'bmp', 'webp', 'heic', 'heif', 'tif', 'tiff',
  };

  /// Picks one or more images with the system document picker (no permission
  /// prompt needed on Android 13+ thanks to the photos picker).
  Future<List<PickedBlob>> pickImages({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageExtensions.toList(growable: false),
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null) return const <PickedBlob>[];
    final out = <PickedBlob>[];
    for (final file in result.files) {
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) continue;
      out.add(PickedBlob(name: file.name, bytes: bytes));
    }
    return out;
  }

  /// Picks an arbitrary file to hide inside a container.
  Future<PickedBlob?> pickPayloadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return null;
    return PickedBlob(name: file.name, bytes: bytes, mimeType: _guessMime(file.name));
  }

  /// Saves [bytes] through the platform save dialog; falls back to the app cache
  /// (still shareable) when the user cancels.
  Future<String?> saveBytes(Uint8List bytes, String fileName) async {
    try {
      final path = await FilePicker.platform.saveFile(
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: <String>[fileName.split('.').last],
      );
      if (path != null) return path;
    } on PlatformException {
      // Fall through to cache.
    }
    return writeToCache(bytes, fileName);
  }

  Future<String> writeToCache(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Opens the system share sheet for a saved artefact.
  Future<void> shareBytes(Uint8List bytes, String fileName, {String? text}) async {
    final path = await writeToCache(bytes, fileName);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path)],
        text: text,
        subject: fileName,
      ),
    );
  }

  Future<void> copyText(String value) => Clipboard.setData(ClipboardData(text: value));

  static String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'json' => 'application/json',
      'zip' => 'application/zip',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }
}
