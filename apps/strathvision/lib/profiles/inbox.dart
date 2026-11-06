import 'dart:io';


import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'profile_package.dart';
import 'package_exchange.dart';

/// Setting key for the shared inbox folder (Syncthing, a USB stick, a
/// network share…). Packages dropped there are imported; no cloud involved.
const inboxFolderKey = 'inbox_folder';

/// Imports every new package (`.zip`) in [folder] into [store] and the
/// Library. Returns how many were added. Bad files are skipped.
Future<int> scanInbox(AppDatabase db, String folder, Directory store) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return 0;
  final installed = {
    for (final r in await db.allProfiles()) '${r.profileId}@${r.version}',
  };
  var added = 0;
  await store.create(recursive: true);
  await for (final f in dir.list()) {
    if (f is! File || p.extension(f.path).toLowerCase() != '.zip') continue;
    try {
      final meta = await readProfilePackage(f.path);
      final key = '${meta.profileId}@${meta.version}';
      if (installed.contains(key)) continue;
      await applyImport(db, f.path, meta, null, () async => store);
      installed.add(key);
      added++;
    } on Object {
      continue;
    }
  }
  return added;
}
