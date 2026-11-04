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


/// Reads profile metadata from a `.json` file, a `.zip` package, or a package
/// directory. Throws [AnalysisError] on anything unreadable or invalid.
Future<ProfileMetadata> readProfilePackage(String path) async {
  final String text;
  try {
    if (await FileSystemEntity.isDirectory(path)) {
      text = await File(p.join(path, profileManifestName)).readAsString();
    } else if (p.extension(path).toLowerCase() == '.zip') {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final entry = archive.files.where((f) =>
          f.isFile && p.basename(f.name) == profileManifestName).firstOrNull;
      if (entry == null) {
        throw AnalysisError(ErrorCode.schemaMismatch,
            'The package has no $profileManifestName inside it.');
      }
      text = utf8.decode(entry.content as List<int>);
    } else {
      text = await File(path).readAsString();
    }
  } on AnalysisError {
    rethrow;
  } on Object catch (e) {
    throw AnalysisError(ErrorCode.schemaMismatch, 'The file could not be read.',
        {'cause': e.toString()});
  }

  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw AnalysisError(
        ErrorCode.schemaMismatch, 'The file is not valid JSON.', {'cause': e.message});
  }
  return ProfileMetadata.fromJson(json);
}
