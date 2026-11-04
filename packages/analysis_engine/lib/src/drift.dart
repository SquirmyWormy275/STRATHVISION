import 'dart:math' as math;

/// One stored comparison, as the drift view reads it.
class DriftPoint {
  const DriftPoint({
    required this.at,
    required this.score,
    required this.profileVersion,
    required this.distances,
  });

  final DateTime at;

  /// Style-match score, 0..1.
  final double score;
  final int profileVersion;

  /// metric_key → distance in spreads (from ranked deltas).
  final Map<String, double> distances;

  factory DriftPoint.fromResult(DateTime at, Map<String, Object?> result) => DriftPoint(
        at: at,
        score: (result['overall_score'] as num).toDouble(),
        profileVersion: (result['profile_version'] as num).toInt(),
        distances: {
          for (final d in (result['ranked_deltas'] as List).cast<Map<String, Object?>>())
            d['metric_key'] as String: (d['distance_spreads'] as num).toDouble(),
        },
      );
}

/// One session (a local calendar day) of comparisons.
class DriftSession {
  const DriftSession({
    required this.day,
    required this.meanScore,
    required this.count,
    required this.meanDistances,
    required this.profileVersions,
  });

  final DateTime day;
  final double meanScore;
  final int count;
  final Map<String, double> meanDistances;
  final Set<int> profileVersions;
}

enum DriftDirection { closer, steady, further, unknown }

class DriftSummary {
  const DriftSummary({required this.sessions, required this.direction, required this.trendPerSession});
  final List<DriftSession> sessions;
  final DriftDirection direction;

  /// Least-squares change in mean score per session (0..1 units).
  final double trendPerSession;
}

/// Groups comparisons into sessions (one per local day) and fits a trend.
/// "closer" means the match is rising by more than 1 point per session.
DriftSummary summarizeDrift(List<DriftPoint> points) {
  final byDay = <DateTime, List<DriftPoint>>{};
  for (final p in points) {
    final l = p.at.toLocal();
    byDay.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(p);
  }
  final days = byDay.keys.toList()..sort();
  final sessions = [
    for (final d in days)
      () {
        final ps = byDay[d]!;
        final keys = {for (final p in ps) ...p.distances.keys};
        return DriftSession(
          day: d,
          meanScore: ps.map((p) => p.score).reduce((a, b) => a + b) / ps.length,
          count: ps.length,
          meanDistances: {
            for (final k in keys)
              k: () {
                final xs = [for (final p in ps) if (p.distances[k] != null) p.distances[k]!];
                return xs.reduce((a, b) => a + b) / xs.length;
              }(),
          },
          profileVersions: {for (final p in ps) p.profileVersion},
        );
      }(),
  ];
  if (sessions.length < 2) {
    return DriftSummary(sessions: sessions, direction: DriftDirection.unknown, trendPerSession: 0);
  }
  final n = sessions.length;
  final mx = (n - 1) / 2;
  final my = sessions.map((s) => s.meanScore).reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (i - mx) * (sessions[i].meanScore - my);
    sxx += (i - mx) * (i - mx);
  }
  final rate = sxx == 0 ? 0.0 : sxy / sxx;
  final dir = rate > 0.01
      ? DriftDirection.closer
      : rate < -0.01
          ? DriftDirection.further
          : DriftDirection.steady;
  return DriftSummary(sessions: sessions, direction: dir, trendPerSession: math.max(-1, math.min(1, rate)));
}
