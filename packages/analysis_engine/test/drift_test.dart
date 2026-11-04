import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

void main() {
  DriftPoint p(int day, int hour, double score, {double d = 1}) => DriftPoint(
      at: DateTime(2026, 11, day, hour), score: score, profileVersion: 1, distances: {'m': d});

  test('groups by day, averages, and finds a rising trend', () {
    final s = summarizeDrift([
      p(1, 9, 0.50, d: 2), p(1, 10, 0.60, d: 1),
      p(3, 9, 0.62),
      p(5, 9, 0.70), p(5, 11, 0.74),
    ]);
    expect(s.sessions, hasLength(3));
    expect(s.sessions.first.meanScore, closeTo(0.55, 1e-9));
    expect(s.sessions.first.count, 2);
    expect(s.sessions.first.meanDistances['m'], 1.5);
    expect(s.direction, DriftDirection.closer);
    expect(s.trendPerSession, closeTo(0.085, 1e-3));
  });

  test('falling and flat trends; one session is unknown', () {
    expect(summarizeDrift([p(1, 9, 0.8), p(2, 9, 0.6), p(3, 9, 0.5)]).direction,
        DriftDirection.further);
    expect(summarizeDrift([p(1, 9, 0.6), p(2, 9, 0.605)]).direction, DriftDirection.steady);
    expect(summarizeDrift([p(1, 9, 0.6)]).direction, DriftDirection.unknown);
    expect(summarizeDrift([]).sessions, isEmpty);
  });

  test('reads stored Comparison Result JSON', () {
    final pt = DriftPoint.fromResult(DateTime(2026), {
      'overall_score': 0.7,
      'profile_version': 2,
      'ranked_deltas': [
        {'metric_key': 'a', 'distance_spreads': 1.5},
      ],
    });
    expect(pt.score, 0.7);
    expect(pt.distances, {'a': 1.5});
  });
}
