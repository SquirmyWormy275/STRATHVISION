// Success payloads from docs/INTERFACES.md, plus validators that check JSON
// against those schemas. Validators return a list of problems; empty = valid.

/// `phases.<phase_id>` in a Metric Vector.
class PhaseSpan {
  const PhaseSpan({
    required this.startFrame,
    required this.endFrame,
    required this.confidence,
  });

  final int startFrame;
  final int endFrame;
  final double confidence;

  Map<String, Object?> toJson() => {
        'start_frame': startFrame,
        'end_frame': endFrame,
        'confidence': confidence,
      };

  factory PhaseSpan.fromJson(Map<String, Object?> j) => PhaseSpan(
        startFrame: (j['start_frame'] as num).toInt(),
        endFrame: (j['end_frame'] as num).toInt(),
        confidence: (j['confidence'] as num).toDouble(),
      );
}

/// `metrics.<metric_key>` in a Metric Vector.
class MetricValue {
  const MetricValue({
    required this.value,
    required this.confidence,
    required this.phase,
  });

  final double value;
  final double confidence;
  final String phase;

  Map<String, Object?> toJson() =>
      {'value': value, 'confidence': confidence, 'phase': phase};

  factory MetricValue.fromJson(Map<String, Object?> j) => MetricValue(
        value: (j['value'] as num).toDouble(),
        confidence: (j['confidence'] as num).toDouble(),
        phase: j['phase'] as String,
      );
}

/// Metric Vector (per analyzed clip).
class MetricVector {
  const MetricVector({
    required this.clipId,
    required this.packId,
    required this.eventId,
    required this.metricSchemaVersion,
    required this.phases,
    required this.metrics,
    required this.poseConfidenceSummary,
    required this.specialistResiduals,
  });

  final String clipId;
  final String packId;
  final String eventId;
  final String metricSchemaVersion;
  final Map<String, PhaseSpan> phases;
  final Map<String, MetricValue> metrics;
  final double poseConfidenceSummary;
  final Map<String, double> specialistResiduals;

  Map<String, Object?> toJson() => {
        'clip_id': clipId,
        'pack_id': packId,
        'event_id': eventId,
        'metric_schema_version': metricSchemaVersion,
        'phases': {for (final e in phases.entries) e.key: e.value.toJson()},
        'metrics': {for (final e in metrics.entries) e.key: e.value.toJson()},
        'pose_confidence_summary': poseConfidenceSummary,
        'specialist_residuals': specialistResiduals,
      };

  /// Parses JSON that passed [validateMetricVector].
  factory MetricVector.fromJson(Map<String, Object?> j) {
    Map<String, Object?> m(Object? o) => Map<String, Object?>.from(o as Map);
    return MetricVector(
      clipId: j['clip_id'] as String,
      packId: j['pack_id'] as String,
      eventId: j['event_id'] as String,
      metricSchemaVersion: j['metric_schema_version'] as String,
      phases: {
        for (final e in m(j['phases']).entries)
          e.key: PhaseSpan.fromJson(m(e.value)),
      },
      metrics: {
        for (final e in m(j['metrics']).entries)
          e.key: MetricValue.fromJson(m(e.value)),
      },
      poseConfidenceSummary: (j['pose_confidence_summary'] as num).toDouble(),
      specialistResiduals: {
        for (final e in m(j['specialist_residuals']).entries)
          e.key: (e.value as num).toDouble(),
      },
    );
  }
}

/// One entry of `ranked_deltas` in a Comparison Result.
class RankedDelta {
  const RankedDelta({
    required this.metricKey,
    required this.userValue,
    required this.coachCenter,
    required this.coachSpread,
    required this.distanceSpreads,
    required this.contribution,
    required this.phase,
    required this.direction,
  });

  final String metricKey;
  final double userValue;
  final double coachCenter;
  final double coachSpread;
  final double distanceSpreads;
  final double contribution;
  final String phase;

  /// `higher | lower | neutral`.
  final String direction;

  Map<String, Object?> toJson() => {
        'metric_key': metricKey,
        'user_value': userValue,
        'coach_center': coachCenter,
        'coach_spread': coachSpread,
        'distance_spreads': distanceSpreads,
        'contribution': contribution,
        'phase': phase,
        'direction': direction,
      };
}

/// Comparison Result. Produced from Phase 5 on; defined here so the
/// contract lives in one package.
class ComparisonResult {
  const ComparisonResult({
    required this.resultId,
    required this.clipId,
    required this.profileId,
    required this.profileVersion,
    required this.overallScore,
    required this.rankedDeltas,
    required this.metricsUsed,
    required this.metricsMissing,
    required this.lowConfidencePhases,
    required this.nearestReferenceClipIds,
    required this.warnings,
    required this.appliedPatches,
  });

  final String resultId;
  final String clipId;
  final String profileId;
  final int profileVersion;
  final double overallScore;
  final List<RankedDelta> rankedDeltas;
  final int metricsUsed;
  final List<String> metricsMissing;
  final List<String> lowConfidencePhases;
  final List<String> nearestReferenceClipIds;
  final List<String> warnings;
  final List<String> appliedPatches;

  Map<String, Object?> toJson() => {
        'result_id': resultId,
        'clip_id': clipId,
        'profile_id': profileId,
        'profile_version': profileVersion,
        'overall_score': overallScore,
        'score_meaning': 'style_match',
        'ranked_deltas': [for (final d in rankedDeltas) d.toJson()],
        'coverage': {
          'metrics_used': metricsUsed,
          'metrics_missing': metricsMissing,
          'low_confidence_phases': lowConfidencePhases,
        },
        'nearest_reference_clip_ids': nearestReferenceClipIds,
        'warnings': warnings,
        'applied_patches': appliedPatches,
      };
}

// ---------------------------------------------------------------- validators

class _Check {
  final problems = <String>[];

  Map<String, Object?>? obj(Object? v, String path) {
    if (v is Map) {
      if (v.keys.every((k) => k is String)) {
        return Map<String, Object?>.from(v);
      }
    }
    problems.add('$path must be an object');
    return null;
  }

  void str(Map<String, Object?> j, String key, String path,
      {bool nonEmpty = true}) {
    final v = j[key];
    if (v is! String || (nonEmpty && v.isEmpty)) {
      problems.add('$path$key must be a ${nonEmpty ? 'non-empty ' : ''}string');
    }
  }

  void number(Map<String, Object?> j, String key, String path,
      {double? min, double? max}) {
    final v = j[key];
    if (v is! num || v.isNaN || v.isInfinite) {
      problems.add('$path$key must be a finite number');
      return;
    }
    if (min != null && v < min) problems.add('$path$key must be >= $min');
    if (max != null && v > max) problems.add('$path$key must be <= $max');
  }

  void integer(Map<String, Object?> j, String key, String path, {int? min}) {
    final v = j[key];
    if (v is! int) {
      problems.add('$path$key must be an integer');
      return;
    }
    if (min != null && v < min) problems.add('$path$key must be >= $min');
  }

  void stringList(Map<String, Object?> j, String key, String path) {
    final v = j[key];
    if (v is! List || v.any((e) => e is! String)) {
      problems.add('$path$key must be a list of strings');
    }
  }
}

/// Validates a Metric Vector JSON object against INTERFACES.md.
/// [requiredResiduals] are the heads the pack declares; each must appear in
/// `specialist_residuals`.
List<String> validateMetricVector(Object? json,
    {List<String> requiredResiduals = const []}) {
  final c = _Check();
  final j = c.obj(json, 'metric_vector');
  if (j == null) return c.problems;
  for (final k in ['clip_id', 'pack_id', 'event_id', 'metric_schema_version']) {
    c.str(j, k, '');
  }

  final phaseIds = <String>{};
  final phases = c.obj(j['phases'], 'phases');
  if (phases != null) {
    if (phases.isEmpty) c.problems.add('phases must not be empty');
    for (final e in phases.entries) {
      phaseIds.add(e.key);
      final p = c.obj(e.value, 'phases.${e.key}');
      if (p == null) continue;
      final path = 'phases.${e.key}.';
      c.integer(p, 'start_frame', path, min: 0);
      c.integer(p, 'end_frame', path, min: 0);
      c.number(p, 'confidence', path, min: 0, max: 1);
      final s = p['start_frame'], en = p['end_frame'];
      if (s is int && en is int && en < s) {
        c.problems.add('${path}end_frame must be >= start_frame');
      }
    }
  }

  final metrics = c.obj(j['metrics'], 'metrics');
  if (metrics != null) {
    for (final e in metrics.entries) {
      final m = c.obj(e.value, 'metrics.${e.key}');
      if (m == null) continue;
      final path = 'metrics.${e.key}.';
      c.number(m, 'value', path);
      c.number(m, 'confidence', path, min: 0, max: 1);
      c.str(m, 'phase', path);
      final ph = m['phase'];
      if (ph is String && phases != null && !phaseIds.contains(ph)) {
        c.problems.add('${path}phase "$ph" is not in phases');
      }
    }
  }

  c.number(j, 'pose_confidence_summary', '', min: 0, max: 1);

  final residuals = c.obj(j['specialist_residuals'], 'specialist_residuals');
  if (residuals != null) {
    for (final k in requiredResiduals) {
      if (!residuals.containsKey(k)) {
        c.problems.add('specialist_residuals.$k is required');
      }
    }
    for (final k in residuals.keys) {
      c.number(residuals, k, 'specialist_residuals.');
    }
  }
  return c.problems;
}

/// Validates a Comparison Result JSON object against INTERFACES.md.
List<String> validateComparisonResult(Object? json) {
  final c = _Check();
  final j = c.obj(json, 'comparison_result');
  if (j == null) return c.problems;
  for (final k in ['result_id', 'clip_id', 'profile_id']) {
    c.str(j, k, '');
  }
  c.integer(j, 'profile_version', '', min: 1);
  c.number(j, 'overall_score', '');
  if (j['score_meaning'] != 'style_match') {
    c.problems.add('score_meaning must be "style_match"');
  }
  final deltas = j['ranked_deltas'];
  if (deltas is! List) {
    c.problems.add('ranked_deltas must be a list');
  } else {
    for (var i = 0; i < deltas.length; i++) {
      final d = c.obj(deltas[i], 'ranked_deltas[$i]');
      if (d == null) continue;
      final path = 'ranked_deltas[$i].';
      c.str(d, 'metric_key', path);
      for (final k in [
        'user_value',
        'coach_center',
        'coach_spread',
        'distance_spreads',
        'contribution',
      ]) {
        c.number(d, k, path);
      }
      c.str(d, 'phase', path);
      if (!const ['higher', 'lower', 'neutral'].contains(d['direction'])) {
        c.problems.add('${path}direction must be higher | lower | neutral');
      }
    }
  }
  final cov = c.obj(j['coverage'], 'coverage');
  if (cov != null) {
    c.integer(cov, 'metrics_used', 'coverage.', min: 0);
    c.stringList(cov, 'metrics_missing', 'coverage.');
    c.stringList(cov, 'low_confidence_phases', 'coverage.');
  }
  c.stringList(j, 'nearest_reference_clip_ids', '');
  c.stringList(j, 'warnings', '');
  c.stringList(j, 'applied_patches', '');
  return c.problems;
}

/// Validates an Error Contract object.
List<String> validateAnalysisError(Object? json) {
  final c = _Check();
  final j = c.obj(json, 'error');
  if (j == null) return c.problems;
  const codes = [
    'INSUFFICIENT_CLIPS',
    'LOW_POSE_CONFIDENCE',
    'PHASE_DETECTION_FAILED',
    'SCHEMA_MISMATCH',
    'PROFILE_NOT_READY',
    'PATCH_REJECTED',
    'ADAPTER_COMPILE_FAILED',
  ];
  if (!codes.contains(j['error_code'])) {
    c.problems.add('error_code must be one of ${codes.join(' | ')}');
  }
  c.str(j, 'message', '');
  c.obj(j['details'], 'details');
  return c.problems;
}
