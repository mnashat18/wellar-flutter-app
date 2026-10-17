import 'dart:io';

import 'package:camera/camera.dart';

/// Best-effort removal for temporary scan media owned by the app.
Future<void> deleteLocalScanMedia(Iterable<String?> paths) async {
  final seen = <String>{};
  for (final rawPath in paths) {
    final path = rawPath?.trim();
    if (path == null || path.isEmpty || !seen.add(path)) continue;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup is best effort; never mask the scan's terminal outcome.
    } catch (_) {
      // Platform file providers can fail independently of scan completion.
    }
  }
}

Future<void> deleteLocalScanFiles(Iterable<XFile?> files) =>
    deleteLocalScanMedia(files.map((file) => file?.path));
