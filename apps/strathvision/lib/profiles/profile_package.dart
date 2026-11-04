import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Error codes from docs/INTERFACES.md "Error Contract".
class AnalysisError implements Exception {
  AnalysisError(this.errorCode, this.message, [this.details = const {}]);

  final String errorCode;
  final String message;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() =>
      {'error_code': errorCode, 'message': message, 'details': details};

  @override
  String toString() => '$errorCode: $message';
}

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
    final problems = <String>[];
    if (json is! Map<String, Object?>) {
      throw AnalysisError('SCHEMA_MISMATCH', 'Profile must be a JSON object.');
    }

    T? field<T>(Map<String, Object?> m, String key, String path) {
      final v = m[key];
      if (v is T) return v;
      problems.add(v == null ? '$path is missing' : '$path has the wrong type');
      return null;
    }

    final profileId = field<String>(json, 'profile_id', 'profile_id');
    final version = field<int>(json, 'version', 'version');
    final coachName = field<String>(json, 'coach_name', 'coach_name');
    final packId = field<String>(json, 'pack_id', 'pack_id');
    final eventId = field<String>(json, 'event_id', 'event_id');
    final schema =
        field<String>(json, 'metric_schema_version', 'metric_schema_version');
    final createdAtRaw = field<String>(json, 'created_at', 'created_at');
    final clipCount =
        field<int>(json, 'source_clip_count', 'source_clip_count');
    final gates = field<Map<String, Object?>>(
        json, 'quality_gates', 'quality_gates');
    final metrics = field<Map<String, Object?>>(json, 'metrics', 'metrics');

    bool? minClipsMet;
    bool? selfConsistency;
    if (gates != null) {
      minClipsMet =
          field<bool>(gates, 'min_clips_met', 'quality_gates.min_clips_met');
      selfConsistency = field<bool>(gates, 'self_consistency_passed',
          'quality_gates.self_consistency_passed');
      field<String>(gates, 'notes', 'quality_gates.notes');
    }

    if (metrics != null) {
      for (final entry in metrics.entries) {
        final path = 'metrics.${entry.key}';
        final m = entry.value;
        if (m is! Map<String, Object?>) {
          problems.add('$path must be an object');
          continue;
        }
        for (final k in ['center', 'spread', 'weight']) {
          if (m[k] is! num) problems.add('$path.$k must be a number');
        }
        for (final k in ['unit', 'phase']) {
          if (m[k] is! String) problems.add('$path.$k must be a string');
        }
      }
    }

    DateTime? createdAt;
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw);
      if (createdAt == null) problems.add('created_at is not ISO 8601');
    }
    if (version != null && version < 1) problems.add('version must be >= 1');
    if (clipCount != null && clipCount < 0) {
      problems.add('source_clip_count must be >= 0');
    }
    for (final (name, v) in [
      ('profile_id', profileId),
      ('pack_id', packId),
      ('event_id', eventId),
      ('metric_schema_version', schema),
    ]) {
      if (v != null && v.trim().isEmpty) problems.add('$name is empty');
    }

    if (problems.isNotEmpty) {
      throw AnalysisError('SCHEMA_MISMATCH',
          'This file is not a valid profile package.', {'problems': problems});
    }

    return ProfileMetadata(
      profileId: profileId!,
      version: version!,
      coachName: coachName!,
      packId: packId!,
      eventId: eventId!,
      metricSchemaVersion: schema!,
      createdAt: createdAt!,
      sourceClipCount: clipCount!,
      metricCount: metrics!.length,
      minClipsMet: minClipsMet!,
      selfConsistencyPassed: selfConsistency!,
    );
  }
}

/// Name of the manifest inside a directory or zip package.
const profileManifestName = 'profile.json';

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
        throw AnalysisError('SCHEMA_MISMATCH',
            'The package has no $profileManifestName inside it.');
      }
      text = utf8.decode(entry.content as List<int>);
    } else {
      text = await File(path).readAsString();
    }
  } on AnalysisError {
    rethrow;
  } on Object catch (e) {
    throw AnalysisError('SCHEMA_MISMATCH', 'The file could not be read.',
        {'cause': e.toString()});
  }

  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw AnalysisError(
        'SCHEMA_MISMATCH', 'The file is not valid JSON.', {'cause': e.message});
  }
  return ProfileMetadata.fromJson(json);
}
