import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Zip bytes for a profile package: `profile.json`, plus the empty
/// `specialist_patches/` and `adapters/` directories (INTERFACES.md).
///
/// [patches] and [adapters] (file name → contents) go into
/// `specialist_patches/` and `adapters/`.
Uint8List zipProfilePackage(Profile profile,
    {Map<String, String> patches = const {},
    Map<String, String> adapters = const {}}) {
  final archive = Archive();
  final entries = {
    ...profile.packageEntries(),
    for (final e in patches.entries) 'specialist_patches/${e.key}': e.value,
    for (final e in adapters.entries) 'adapters/${e.key}': e.value,
  };
  for (final e in entries.entries) {
    final content = e.value;
    archive.add(content == null
        ? ArchiveFile.directory(e.key)
        : ArchiveFile.bytes(e.key, utf8.encode(content)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// File name for a package: `<coach>_v<version>.zip`, filesystem-safe.
String packageFileName(Profile profile) {
  final slug = profile.coachName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${slug.isEmpty ? 'profile' : slug}_v${profile.version}.zip';
}

/// Writes the package into [dir] (the app's own profile store) and returns
/// its path.
Future<String> storeProfilePackage(Profile profile, Directory dir,
    {Map<String, String> patches = const {},
    Map<String, String> adapters = const {}}) async {
  await dir.create(recursive: true);
  final path =
      p.join(dir.path, '${profile.profileId}_v${profile.version}.zip');
  await File(path).writeAsBytes(
      zipProfilePackage(profile, patches: patches, adapters: adapters),
      flush: true);
  return path;
}
