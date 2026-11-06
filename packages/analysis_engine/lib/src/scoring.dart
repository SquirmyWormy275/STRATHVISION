import 'dart:math' as math;

import 'profile.dart';

/// Distance of [value] from a profile metric, in spreads.
double distanceSpreads(double value, ProfileMetric m) {
  if (m.spread <= 0) return value == m.center ? 0 : double.infinity;
  return (value - m.center).abs() / m.spread;
}

/// Per-metric match in 0..1: exp(−d²/2), where d is the distance in spreads.
double metricMatch(double value, ProfileMetric m) {
  final d = distanceSpreads(value, m);
  return d.isInfinite ? 0 : math.exp(-d * d / 2);
}

/// Style-match score in 0..1: weight-averaged [metricMatch] over the profile
/// metrics present in [values]. Null when no weighted metric is present.
/// This is a match against one profile, not a quality score.
double? styleMatchScore(
  Map<String, double> values,
  Map<String, ProfileMetric> profile, {
  List<ReferenceClip> exemplars = const [],
}) {
  var num = 0.0, den = 0.0;
  for (final e in profile.entries) {
    final v = values[e.key];
    if (v == null || e.value.weight <= 0) continue;
    num += e.value.weight * prototypeMatch(v, e.key, e.value, exemplars);
    den += e.value.weight;
  }
  return den == 0 ? null : num / den;
}

/// Same scalar prototype semantics for research evaluation and inference.
/// Exemplar reliability limits the match it can contribute.
double prototypeMatch(
  double value,
  String key,
  ProfileMetric metric,
  List<ReferenceClip> exemplars,
) {
  var best = metricMatch(value, metric);
  for (final exemplar in exemplars.where((e) => e.exemplar)) {
    final center = exemplar.metrics[key];
    if (center == null || !center.isFinite || !exemplar.weight.isFinite) {
      continue;
    }
    final prototype = ProfileMetric(
      center: center,
      spread: metric.spread,
      weight: metric.weight,
      unit: metric.unit,
      phase: metric.phase,
    );
    best = math.max(
      best,
      exemplar.weight.clamp(0.0, 1.0) * metricMatch(value, prototype),
    );
  }
  return best;
}
