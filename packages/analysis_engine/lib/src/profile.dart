import 'dart:convert';

/// `metrics.<metric_key>` in a Profile Package.
class ProfileMetric {
  const ProfileMetric({
    required this.center,
    required this.spread,
    required this.weight,
    required this.unit,
    required this.phase,
  });

  final double center;
  final double spread;
  final double weight;
  final String unit;
  final String phase;

  Map<String, Object?> toJson() => {
    'center': center,
    'spread': spread,
    'weight': weight,
    'unit': unit,
    'phase': phase,
  };

  factory ProfileMetric.fromJson(Map<String, Object?> j) => ProfileMetric(
    center: (j['center'] as num).toDouble(),
    spread: (j['spread'] as num).toDouble(),
    weight: (j['weight'] as num).toDouble(),
    unit: j['unit'] as String,
    phase: j['phase'] as String,
  );
}

/// A reference clip kept in the package for nearest-reference lookup.
/// Holds metric values only, never video or file paths.
class ReferenceClip {
  const ReferenceClip({
    required this.clipId,
    required this.metrics,
    this.exemplar = false,
    this.weight = 1.0,
    this.confidence = 1.0,
    this.source,
  });

  final String clipId;
  final Map<String, double> metrics;

  /// A residual exemplar (added by CARNE ASADA from a marked stroke) rather
  /// than one of the coach's own reference strokes.
  final bool exemplar;

  /// Exemplar weight, 0..1 (how strongly it acts as a mixture component).
  final double weight;

  /// Measurement confidence of the stroke it came from, 0..1.
  final double confidence;

  /// Where it came from, for explanations ("the 14-second mark of the X clip").
  final String? source;

  ReferenceClip withWeight(double w) => ReferenceClip(
    clipId: clipId,
    metrics: metrics,
    exemplar: exemplar,
    weight: w,
    confidence: confidence,
    source: source,
  );

  Map<String, Object?> toJson() => {
    'clip_id': clipId,
    'metrics': metrics,
    if (exemplar) ...{
      'exemplar': true,
      'weight': weight,
      'confidence': confidence,
      'source': source,
    },
  };

  factory ReferenceClip.fromJson(Map<String, Object?> j) => ReferenceClip(
    clipId: j['clip_id'] as String,
    metrics: {
      for (final e in (j['metrics'] as Map).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    exemplar: j['exemplar'] == true,
    weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
    confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
    source: j['source'] as String?,
  );
}

/// Profile Package manifest (`profile.json`): the INTERFACES.md minimum
/// contract plus the optional reference clips.
class Profile {
  const Profile({
    required this.profileId,
    required this.version,
    required this.coachName,
    required this.packId,
    required this.eventId,
    required this.metricSchemaVersion,
    required this.createdAt,
    required this.sourceClipCount,
    required this.minClipsMet,
    required this.selfConsistencyPassed,
    required this.notes,
    required this.metrics,
    this.referenceClips = const [],
  });

  final String profileId;
  final int version;
  final String coachName;
  final String packId;
  final String eventId;
  final String metricSchemaVersion;
  final DateTime createdAt;
  final int sourceClipCount;
  final bool minClipsMet;
  final bool selfConsistencyPassed;
  final String notes;
  final Map<String, ProfileMetric> metrics;
  final List<ReferenceClip> referenceClips;

  bool get ready => minClipsMet && selfConsistencyPassed;

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'version': version,
    'coach_name': coachName,
    'pack_id': packId,
    'event_id': eventId,
    'metric_schema_version': metricSchemaVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'source_clip_count': sourceClipCount,
    'quality_gates': {
      'min_clips_met': minClipsMet,
      'self_consistency_passed': selfConsistencyPassed,
      'notes': notes,
    },
    'metrics': {for (final e in metrics.entries) e.key: e.value.toJson()},
    'reference_clips': [for (final r in referenceClips) r.toJson()],
  };

  /// Parses JSON that passed [validateProfile].
  factory Profile.fromJson(Map<String, Object?> j) {
    final gates = Map<String, Object?>.from(j['quality_gates'] as Map);
    return Profile(
      profileId: j['profile_id'] as String,
      version: j['version'] as int,
      coachName: j['coach_name'] as String,
      packId: j['pack_id'] as String,
      eventId: j['event_id'] as String,
      metricSchemaVersion: j['metric_schema_version'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      sourceClipCount: j['source_clip_count'] as int,
      minClipsMet: gates['min_clips_met'] as bool,
      selfConsistencyPassed: gates['self_consistency_passed'] as bool,
      notes: gates['notes'] as String,
      metrics: {
        for (final e in (j['metrics'] as Map).entries)
          e.key as String: ProfileMetric.fromJson(
            Map<String, Object?>.from(e.value as Map),
          ),
      },
      referenceClips: [
        for (final r in (j['reference_clips'] as List? ?? const []))
          ReferenceClip.fromJson(Map<String, Object?>.from(r as Map)),
      ],
    );
  }

  /// Package contents: path → text, or null for a directory.
  /// INTERFACES.md: `profile.json`, `specialist_patches/`, `adapters/`.
  Map<String, String?> packageEntries() => {
    profileManifestName: const JsonEncoder.withIndent('  ').convert(toJson()),
    'specialist_patches/': null,
    'adapters/': null,
  };
}

/// Name of the manifest inside a directory or zip package.
const profileManifestName = 'profile.json';

/// Validates a profile manifest against the INTERFACES.md minimum contract.
/// Returns every problem; empty means valid.
List<String> validateProfile(Object? json) {
  final problems = <String>[];
  if (json is! Map<String, Object?>) return ['profile must be a JSON object'];

  T? field<T>(Map<String, Object?> m, String key, String path) {
    final v = m[key];
    if (v is T) return v;
    problems.add(v == null ? '$path is missing' : '$path has the wrong type');
    return null;
  }

  final profileId = field<String>(json, 'profile_id', 'profile_id');
  if (profileId != null &&
      (profileId.contains('/') ||
          profileId.contains('\\') ||
          profileId == '.' ||
          profileId == '..' ||
          profileId.codeUnits.any((c) => c < 32 || c == 127))) {
    problems.add('profile_id must be an identifier, not a path');
  }
  final version = field<int>(json, 'version', 'version');
  field<String>(json, 'coach_name', 'coach_name');
  final packId = field<String>(json, 'pack_id', 'pack_id');
  final eventId = field<String>(json, 'event_id', 'event_id');
  final schema = field<String>(
    json,
    'metric_schema_version',
    'metric_schema_version',
  );
  final createdAt = field<String>(json, 'created_at', 'created_at');
  final clipCount = field<int>(json, 'source_clip_count', 'source_clip_count');
  final gates = field<Map<String, Object?>>(
    json,
    'quality_gates',
    'quality_gates',
  );
  final metrics = field<Map<String, Object?>>(json, 'metrics', 'metrics');

  if (gates != null) {
    field<bool>(gates, 'min_clips_met', 'quality_gates.min_clips_met');
    field<bool>(
      gates,
      'self_consistency_passed',
      'quality_gates.self_consistency_passed',
    );
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
      final spread = m['spread'];
      if (spread is num && spread < 0) {
        problems.add('$path.spread must be >= 0');
      }
      final weight = m['weight'];
      if (weight is num && weight < 0) {
        problems.add('$path.weight must be >= 0');
      }
    }
  }

  if (createdAt != null && DateTime.tryParse(createdAt) == null) {
    problems.add('created_at is not ISO 8601');
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

  final refs = json['reference_clips'];
  if (refs != null) {
    if (refs is! List) {
      problems.add('reference_clips must be a list');
    } else {
      for (var i = 0; i < refs.length; i++) {
        final r = refs[i];
        if (r is! Map ||
            r['clip_id'] is! String ||
            r['metrics'] is! Map ||
            (r['metrics'] as Map).values.any((v) => v is! num)) {
          problems.add(
            'reference_clips[$i] must have clip_id and numeric metrics',
          );
        }
      }
    }
  }
  return problems;
}
