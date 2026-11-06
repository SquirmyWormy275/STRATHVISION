import 'dart:math' as math;

import 'contracts.dart';
import 'errors.dart';
import 'profile.dart';
import 'scoring.dart';

/// Below this confidence a phase, metric, or pose summary is flagged.
const lowConfidence = 0.6;

/// Distance in spreads under which a delta is `neutral`.
const neutralSpreads = 0.5;

sealed class ComparisonOutcome {
  const ComparisonOutcome();
  Map<String, Object?> toJson();
}

class ComparisonSuccess extends ComparisonOutcome {
  const ComparisonSuccess(this.result);
  final ComparisonResult result;
  @override
  Map<String, Object?> toJson() => result.toJson();
}

class ComparisonFailure extends ComparisonOutcome {
  const ComparisonFailure(this.error);
  final AnalysisError error;
  @override
  Map<String, Object?> toJson() => error.toJson();
}

double _r(double v) => (v * 1e4).roundToDouble() / 1e4;

/// Metric Vector + Profile → Comparison Result (INTERFACES.md "Comparison
/// rules"). Deterministic apart from [resultId].
ComparisonOutcome compare({
  required MetricVector vector,
  required Profile profile,
  required String resultId,
  List<String> appliedPatches = const [],
  List<String> rejectedPatches = const [],
  List<String> extraWarnings = const [],
  String Function(String metricKey)? metricLabel,
  String Function(String phaseId)? phaseLabel,
}) {
  String m(String k) => metricLabel?.call(k) ?? k;
  String ph(String k) => phaseLabel?.call(k) ?? k;
  if (profile.packId != vector.packId || profile.eventId != vector.eventId) {
    return ComparisonFailure(
      AnalysisError(
        ErrorCode.schemaMismatch,
        'This profile is for a different event.',
        {
          'profile_pack_id': profile.packId,
          'profile_event_id': profile.eventId,
          'clip_pack_id': vector.packId,
          'clip_event_id': vector.eventId,
        },
      ),
    );
  }
  if (profile.metricSchemaVersion != vector.metricSchemaVersion) {
    return ComparisonFailure(
      AnalysisError(
        ErrorCode.schemaMismatch,
        'This profile was measured differently and needs rebuilding.',
        {
          'profile_schema': profile.metricSchemaVersion,
          'clip_schema': vector.metricSchemaVersion,
        },
      ),
    );
  }
  if (!profile.ready) {
    return ComparisonFailure(
      AnalysisError(
        ErrorCode.profileNotReady,
        'This profile did not pass its quality checks.',
        {
          'min_clips_met': profile.minClipsMet,
          'self_consistency_passed': profile.selfConsistencyPassed,
        },
      ),
    );
  }

  final keys = profile.metrics.keys.toList()..sort();
  final used = [
    for (final k in keys)
      if (vector.metrics.containsKey(k)) k,
  ];
  final missing = [
    for (final k in keys)
      if (!vector.metrics.containsKey(k)) k,
  ];
  if (used.isEmpty) {
    return ComparisonFailure(
      AnalysisError(
        ErrorCode.schemaMismatch,
        'This clip has no measurements in common with the profile.',
        {'metrics_missing': missing},
      ),
    );
  }

  final values = {for (final k in used) k: vector.metrics[k]!.value};
  final usedProfile = {for (final k in used) k: profile.metrics[k]!};
  final score =
      styleMatchScore(values, usedProfile, exemplars: profile.referenceClips) ??
      0;
  final totalW = usedProfile.values.fold(0.0, (a, m) => a + m.weight);

  final deltas = <RankedDelta>[];
  for (final k in used) {
    final m = profile.metrics[k]!;
    final v = values[k]!;
    final d = distanceSpreads(v, m);
    final contrib = totalW == 0
        ? 0.0
        : m.weight *
              (1 - prototypeMatch(v, k, m, profile.referenceClips)) /
              totalW;
    final mv = vector.metrics[k]!;
    final reliability = math.min(
      vector.poseConfidenceSummary,
      math.min(mv.confidence, vector.phases[mv.phase]?.confidence ?? 0),
    );
    deltas.add(
      RankedDelta(
        metricKey: k,
        userValue: v,
        coachCenter: m.center,
        coachSpread: m.spread,
        distanceSpreads: _r(d.isInfinite ? 1e9 : d),
        contribution: _r(contrib),
        confidence: _r(reliability),
        rankingWeight: reliability < lowConfidence
            ? 0
            : _r(contrib * reliability),
        phase: m.phase,
        direction: d < neutralSpreads
            ? 'neutral'
            : (v > m.center ? 'higher' : 'lower'),
      ),
    );
  }
  deltas.sort((a, b) {
    final c = b.rankingWeight!.compareTo(a.rankingWeight!);
    if (c != 0) return c;
    final reliability = b.confidence.compareTo(a.confidence);
    return reliability != 0 ? reliability : a.metricKey.compareTo(b.metricKey);
  });

  final lowPhases = [
    for (final e in vector.phases.entries)
      if (e.value.confidence < lowConfidence) e.key,
  ]..sort();
  final warnings = <String>[];
  if (vector.poseConfidenceSummary < lowConfidence) {
    warnings.add(
      'Body tracking was weak in this clip '
      '(${(vector.poseConfidenceSummary * 100).round()}%).',
    );
  }
  if (lowPhases.isNotEmpty) {
    warnings.add(
      'Phase timing is uncertain for ${lowPhases.map(ph).join(', ')}.',
    );
  }
  final lowMetrics = [
    for (final k in used)
      if (vector.metrics[k]!.confidence < lowConfidence) k,
  ];
  if (lowMetrics.isNotEmpty) {
    warnings.add(
      'Low-confidence measurements: ${lowMetrics.map(m).join(', ')}.',
    );
  }
  if (missing.isNotEmpty) {
    warnings.add('Not measured in this clip: ${missing.map(m).join(', ')}.');
  }
  for (final p in rejectedPatches) {
    warnings.add('Specialist patch $p was rejected and not applied.');
  }
  if (deltas.any((d) => d.confidence < lowConfidence)) {
    warnings.add(
      'Uncertain differences are ranked last. The style-match score still includes them.',
    );
  }
  warnings.addAll(extraWarnings);

  // Nearest reference clips: weighted RMS distance in spreads.
  final refs = <(String, double)>[];
  for (final ref in profile.referenceClips) {
    var sum = 0.0, w = 0.0;
    for (final k in used) {
      final rv = ref.metrics[k];
      if (rv == null) continue;
      final m = profile.metrics[k]!;
      final z = (values[k]! - rv) / m.spread;
      sum += m.weight * z * z;
      w += m.weight;
    }
    if (w > 0) refs.add((ref.clipId, math.sqrt(sum / w)));
  }
  refs.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });

  return ComparisonSuccess(
    ComparisonResult(
      resultId: resultId,
      rankingPolicy: 'confidence-v1',
      clipId: vector.clipId,
      profileId: profile.profileId,
      profileVersion: profile.version,
      overallScore: _r(score),
      rankedDeltas: deltas,
      metricsUsed: used.length,
      metricsMissing: missing,
      lowConfidencePhases: lowPhases,
      nearestReferenceClipIds: [for (final r in refs.take(3)) r.$1],
      warnings: warnings,
      appliedPatches: appliedPatches,
    ),
  );
}
