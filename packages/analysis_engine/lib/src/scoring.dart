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
    Map<String, double> values, Map<String, ProfileMetric> profile) {
  var num = 0.0, den = 0.0;
  for (final e in profile.entries) {
    final v = values[e.key];
    if (v == null || e.value.weight <= 0) continue;
    num += e.value.weight * metricMatch(v, e.value);
    den += e.value.weight;
  }
  return den == 0 ? null : num / den;
}
