import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// iOS Photos picks are temporary exports. Own a durable copy before saving
/// their path in a project; other platforms keep their original references.
Future<String> retainPickedVideo(
  String path, {
  bool? onIOS,
  Future<Directory> Function()? supportDirectory,
  Future<void> Function(File source, File destination)? copy,
}) async {
  if (!(onIOS ?? Platform.isIOS)) return path;
  final source = File(path);
  // Retain every iOS picker export rather than infer its lifetime from a path.
  // path_provider's "temporary" directory is Library/Caches on iOS, while
  // file_picker uses NSTemporaryDirectory; they are not interchangeable.
  final support = await (supportDirectory ?? getApplicationSupportDirectory)();
  final imports = Directory(p.join(support.path, 'imported_clips'));
  await imports.create(recursive: true);
  final directory = await imports.createTemp('clip-');
  final destination = File(p.join(directory.path, p.basename(path)));
  try {
    if (copy == null) {
      await source.copy(destination.path);
    } else {
      await copy(source, destination);
    }
    return destination.path;
  } catch (_) {
    // A failed copy must never become a saved clip or leave partial video data.
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Preserve the original copy failure if cleanup itself is unavailable.
    }
    rethrow;
  }
}
