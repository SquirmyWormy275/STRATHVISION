import 'dart:math' as math;

import 'body.dart';
import 'engine.dart';
import 'pack.dart';

/// Stroke spans from implement-speed peaks (DECISIONS.md: stroke boundaries
/// from implement-speed peaks + phase transitions). Each peak is one stroke;
/// boundaries sit midway between peaks. Partial strokes at the clip edges
/// and spans far from the typical length are dropped ("actual stroke").
List<(int, int)> segmentStrokes(ImplementTrack imp, double fps) {
  final f = imp.frames;
  if (f.length < 5) return const [];
  // Tip speed per sample (metres per second).
  final speed = <double>[0];
  for (var i = 1; i < f.length; i++) {
    final dt = (f[i].frame - f[i - 1].frame) / fps;
    speed.add(dt <= 0 ? 0 : (f[i].tip - f[i - 1].tip).length / dt);
  }
  // Light smoothing.
  final s = [
    for (var i = 0; i < speed.length; i++)
      [for (var j = math.max(0, i - 1); j <= math.min(speed.length - 1, i + 1); j++) speed[j]]
          .reduce((a, b) => a + b) /
          (math.min(speed.length - 1, i + 1) - math.max(0, i - 1) + 1),
  ];
  final maxS = s.reduce(math.max);
  final minS = s.reduce(math.min);
  if (maxS - minS < 1e-6) return const [];
  final level = minS + 0.6 * (maxS - minS);
  final peaks = <int>[];
  for (var i = 1; i < s.length - 1; i++) {
    if (s[i] >= level && s[i] >= s[i - 1] && s[i] > s[i + 1]) {
      if (peaks.isNotEmpty && (f[i].frame - f[peaks.last].frame) / fps < 0.4) {
        if (s[i] > s[peaks.last]) peaks[peaks.length - 1] = i;
        continue;
      }
      peaks.add(i);
    }
  }
  if (peaks.length < 2) return const [];
  final frames = [for (final p in peaks) f[p].frame];
  final bounds = [
    for (var i = 0; i < frames.length - 1; i++) (frames[i] + frames[i + 1]) ~/ 2,
  ];
  // Strokes between consecutive boundaries: each contains exactly one peak.
  final spans = [
    for (var i = 0; i < bounds.length - 1; i++) (bounds[i], bounds[i + 1] - 1),
  ];
  if (spans.isEmpty) return const [];
  final lens = [for (final (a, b) in spans) b - a + 1]..sort();
  final median = lens[lens.length ~/ 2];
  return [
    for (final sp in spans)
      if ((sp.$2 - sp.$1 + 1) >= 0.5 * median && (sp.$2 - sp.$1 + 1) <= 1.5 * median) sp,
  ];
}

/// Longest run, in seconds, where the implement track is unconfident
/// (below 0.5) inside frames [start, end].
double longestDropout(ImplementTrack imp, double fps, int start, int end) {
  var best = 0, runStart = -1, lastFrame = start;
  for (final fr in imp.frames) {
    if (fr.frame < start || fr.frame > end) continue;
    if (fr.confidence < 0.5) {
      if (runStart < 0) runStart = fr.frame;
      lastFrame = fr.frame;
      best = math.max(best, lastFrame - runStart + 1);
    } else {
      runStart = -1;
    }
  }
  return best / fps;
}

/// Why a stroke is not usable action.
enum StrokeIssue { noPhases, weakPose, implementDropout }

/// One analyzed stroke.
class StrokeDetail {
  StrokeDetail({
    required this.clipId,
    required this.index,
    required this.startFrame,
    required this.endFrame,
    required this.fps,
    required this.detail,
    required this.dropoutSeconds,
    required AnalysisPack pack,
    double? clipDropoutSeconds,
  })  : clipDropoutSeconds = clipDropoutSeconds ?? dropoutSeconds,
        issues = _issues(detail, dropoutSeconds, pack);

  final String clipId;
  final int index;
  final int startFrame, endFrame;
  final double fps;
  final AnalysisDetail detail;
  final double dropoutSeconds;

  /// Longest implement dropout anywhere in the clip (for status copy).
  final double clipDropoutSeconds;
  final List<StrokeIssue> issues;

  /// Usable action: confident pose, confident implement, assigned phases,
  /// actual stroke (DECISIONS.md).
  bool get usable => issues.isEmpty;
  double get seconds => (endFrame - startFrame + 1) / fps;
  double get midSeconds => (startFrame + endFrame) / 2 / fps;

  Map<String, double> get metrics => switch (detail.outcome) {
        AnalysisSuccess(:final vector) => {
            for (final e in vector.metrics.entries) e.key: e.value.value,
          },
        _ => const {},
      };

  static List<StrokeIssue> _issues(AnalysisDetail d, double dropout, AnalysisPack pack) {
    if (d.outcome is! AnalysisSuccess) return const [StrokeIssue.noPhases];
    final out = <StrokeIssue>[];
    final crit = [for (final p in pack.criticalPhases) d.phasePoseConfidence[p] ?? 0];
    final c = crit.isEmpty ? 0.0 : crit.reduce((a, b) => a + b) / crit.length;
    if (c < pack.minCriticalPoseConfidence) out.add(StrokeIssue.weakPose);
    if (dropout > pack.maxImplementDropoutS) out.add(StrokeIssue.implementDropout);
    return out;
  }
}
