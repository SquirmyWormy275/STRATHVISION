import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

import '../data/database.dart';
import 'profile_export.dart';
import 'profile_package.dart';

/// Installs a generated version without changing an existing version's identity.
/// Explicit import replacement is handled separately by package_exchange.
Future<String> storeNewProfileVersion(
  AppDatabase db,
  Profile profile,
  Directory directory, {
  Map<String, String> patches = const {},
  Map<String, String> adapters = const {},
  Map<String, String> research = const {},
}) async {
  String? created;
  try {
    return await db.transaction(() async {
      final rows = await db.allProfiles();
      if (rows.any((r) => r.profileId == profile.profileId &&
          r.version == profile.version)) {
        throw StateError('Version ${profile.version} already exists. '
            'Open the latest version from the Library to continue.');
      }
      final path = await storeProfilePackage(profile, directory,
          patches: patches, adapters: adapters, research: research);
      created = path;
      // The primary key also rejects collisions from another connection.
      await db.saveProfile(await readProfilePackage(path), path, replace: false);
      return path;
    });
  } catch (_) {
    if (created != null) await File(created!).delete();
    rethrow;
  }
}
