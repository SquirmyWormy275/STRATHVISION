import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:analysis_engine/analysis_engine.dart';

export 'package:analysis_engine/analysis_engine.dart' show AnalysisError, ErrorCode, profileManifestName;

/// Metadata read from the minimum Profile Package contract
/// (docs/INTERFACES.md "Profile Package").
///
/// Phase 1 only stores metadata. Pack and event identifiers are opaque
/// strings; no pack-specific meaning is attached to them here.
class ProfileMetadata {
  ProfileMetadata({
    required this.profileId,
    required this.version,
    required this.coachName,
    required this.packId,
    required this.eventId,
    required this.metricSchemaVersion,
    required this.createdAt,
    required this.sourceClipCount,
    required this.metricCount,
    required this.minClipsMet,
    required this.selfConsistencyPassed,
  });

  final String profileId;
  final int version;
  final String coachName;
  final String packId;
  final String eventId;
  final String metricSchemaVersion;
  final DateTime createdAt;
  final int sourceClipCount;
  final int metricCount;
  final bool minClipsMet;
  final bool selfConsistencyPassed;

  /// Validates [json] against the minimum required contract and returns its
  /// metadata, or throws [AnalysisError] with `SCHEMA_MISMATCH`.
  factory ProfileMetadata.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw AnalysisError(ErrorCode.schemaMismatch, 'Profile must be a JSON object.');
    }
    final problems = validateProfile(json);
    if (problems.isNotEmpty) {
      throw AnalysisError(ErrorCode.schemaMismatch,
          'This file is not a valid profile package.', {'problems': problems});
    }

    final profile = Profile.fromJson(json);
    return ProfileMetadata(
      profileId: profile.profileId,
      version: profile.version,
      coachName: profile.coachName,
      packId: profile.packId,
      eventId: profile.eventId,
      metricSchemaVersion: profile.metricSchemaVersion,
      createdAt: profile.createdAt,
      sourceClipCount: profile.sourceClipCount,
      metricCount: profile.metrics.length,
      minClipsMet: profile.minClipsMet,
      selfConsistencyPassed: profile.selfConsistencyPassed,
    );
  }
}


/// A profile package as the comparison engine needs it: the full manifest
/// plus any specialist patch files (name → contents).
class ProfileBundle {
  const ProfileBundle({
    required this.profile,
    required this.patchFiles,
    this.adapterFiles = const {},
  });
  final Profile profile;

  /// `specialist_patches/*.patch`: name → contents.
  final Map<String, String> patchFiles;

  /// `adapters/*.paw`: name → contents.
  final Map<String, String> adapterFiles;
}

typedef _Package = (String manifest, Map<String, String> patches, Map<String, String> adapters);

/// Raw manifest text and patch files from a `.json`, `.zip`, or directory.
Future<_Package> _readPackage(String path) async {
  try {
    if (await FileSystemEntity.isDirectory(path)) {
      Future<Map<String, String>> files(String sub, String ext) async {
        final out = <String, String>{};
        final dir = Directory(p.join(path, sub));
        if (await dir.exists()) {
          await for (final f in dir.list()) {
            if (f is File && f.path.endsWith(ext)) {
              out[p.basename(f.path)] = await f.readAsString();
            }
          }
        }
        return out;
      }

      return (
        await File(p.join(path, profileManifestName)).readAsString(),
        await files('specialist_patches', '.patch'),
        await files('adapters', '.paw'),
      );
    }
    if (p.extension(path).toLowerCase() == '.zip') {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final entry = archive.files.where((f) =>
          f.isFile && p.basename(f.name) == profileManifestName).firstOrNull;
      if (entry == null) {
        throw AnalysisError(ErrorCode.schemaMismatch,
            'The package has no $profileManifestName inside it.');
      }
      Map<String, String> files(String sub, String ext) => {
            for (final f in archive.files)
              if (f.isFile &&
                  p.basename(p.dirname(f.name)) == sub &&
                  f.name.endsWith(ext))
                p.basename(f.name): utf8.decode(f.content as List<int>),
          };
      return (
        utf8.decode(entry.content as List<int>),
        files('specialist_patches', '.patch'),
        files('adapters', '.paw'),
      );
    }
    return (await File(path).readAsString(), <String, String>{}, <String, String>{});
  } on AnalysisError {
    rethrow;
  } on Object catch (e) {
    throw AnalysisError(ErrorCode.schemaMismatch, 'The file could not be read.',
        {'cause': e.toString()});
  }
}

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw AnalysisError(
        ErrorCode.schemaMismatch, 'The file is not valid JSON.', {'cause': e.message});
  }
}

/// Reads profile metadata from a `.json` file, a `.zip` package, or a package
/// directory. Throws [AnalysisError] on anything unreadable or invalid.
Future<ProfileMetadata> readProfilePackage(String path) async {
  final (text, _, _) = await _readPackage(path);
  return ProfileMetadata.fromJson(_decode(text));
}

/// Reads the full profile and its patch files. Throws [AnalysisError].
Future<ProfileBundle> readProfileBundle(String path) async {
  final (text, patches, adapters) = await _readPackage(path);
  final json = _decode(text);
  ProfileMetadata.fromJson(json); // same checks as import
  return ProfileBundle(
      profile: Profile.fromJson(json as Map<String, Object?>),
      patchFiles: patches,
      adapterFiles: adapters);
}
