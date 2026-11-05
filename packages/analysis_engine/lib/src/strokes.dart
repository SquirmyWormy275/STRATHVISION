import 'dart:math' as math;

import 'body.dart';
import 'engine.dart';
import 'pack.dart';

/// Implement tip positions with single-sample glitches removed: a sample
/// far from both neighbours while they agree with each other (the pose
/// model briefly flipping a forearm) is replaced by their midpoint.
List<Vec3> despikedTips(ImplementTrack imp) {
  final t = [for (final f in imp.frames) f.tip];
  final out = [...t];
  for (var i = 1; i < t.length - 1; i++) {
    final mid = (t[i - 1] + t[i + 1]).scale(0.5);
    final gap = (t[i + 1] - t[i - 1]).length;
    if ((t[i] - mid).length > 2 * gap + 0.2) out[i] = mid;
  }
  return out;
}

/// Tip speed per sample (m/s) from [tips], averaged over [r] samples
/// either side.
List<double> tipSpeed(ImplementTrack imp, List<Vec3> tips, double fps, {int r = 1}) {
  final raw = <double>[0];
  for (var i = 1; i < tips.length; i++) {
    final df = math.max(1, imp.frames[i].frame - imp.frames[i - 1].frame);
    raw.add((tips[i] - tips[i - 1]).length / df * fps);
  }
  return [
    for (var i = 0; i < raw.length; i++)
      () {
        final a = math.max(0, i - r), b = math.min(raw.length - 1, i + r);
        var sum = 0.0;
        for (var j = a; j <= b; j++) {
          sum += raw[j];
        }
        return sum / (b - a + 1);
      }(),
  ];
}

/// Contacts: fast swings that stop sharply. A sample is a contact when the
/// tip speed peaks (at least 40% of the clip's fastest and 4 m/s) and then
/// falls below 30% of that peak within 0.6 s. Returns the stop indices,
/// at least 0.6 s apart.
List<int> findStops(ImplementTrack imp, double fps) {
  final v = tipSpeed(imp, despikedTips(imp), fps);
  if (v.length < 5) return const [];
  final top = v.reduce(math.max);
  final stops = <int>[];
  final peaks = <int>[];
  for (var i = 1; i < v.length - 1; i++) {
    if (!(v[i] >= v[i - 1] && v[i] > v[i + 1])) continue;
    if (v[i] < 0.4 * top || v[i] < 4) continue;
    final f0 = imp.frames[i].frame;
    for (var j = i + 1; j < v.length && (imp.frames[j].frame - f0) / fps <= 0.6; j++) {
      if (v[j] < 0.3 * v[i]) {
        final f = imp.frames[j].frame;
        if (stops.isNotEmpty && (f - imp.frames[stops.last].frame) / fps < 0.6) {
          // Same swing: keep the faster.
          if (v[i] > v[peaks.last]) {
            stops[stops.length - 1] = j;
            peaks[peaks.length - 1] = i;
          }
        } else {
          stops.add(j);
          peaks.add(i);
        }
        break;
      }
    }
  }
  return stops;
}

/// Stroke spans from contacts ([findStops]): each contact is one stroke;
/// cuts sit midway between contacts, so a stroke holds its own backswing,
/// swing, contact and the time in the material after it. Edge strokes
/// extend half the typical stroke length past their contact.
List<(int, int)> segmentStrokesByStops(ImplementTrack imp, double fps) {
  final f = imp.frames;
  final stops = findStops(imp, fps);
  if (stops.isEmpty) return const [];
  final gaps = [for (var k = 1; k < stops.length; k++) stops[k] - stops[k - 1]]..sort();
  final half = gaps.isEmpty
      ? (1.5 * fps / math.max(1, f.length > 1 ? f[1].frame - f[0].frame : 1)).round()
      : gaps[gaps.length ~/ 2] ~/ 2;
  final spans = <(int, int)>[];
  for (var k = 0; k < stops.length; k++) {
    final a = k == 0 ? math.max(0, stops[k] - half) : (stops[k - 1] + stops[k]) ~/ 2 + 1;
    final b = k == stops.length - 1 ? math.min(f.length - 1, stops[k] + half) : (stops[k] + stops[k + 1]) ~/ 2;
    if (b > a) spans.add((f[a].frame, f[b].frame));
  }
  return spans;
}

/// Stroke spans from backswing tops: each top is one stroke, running from
/// the low point before it (rise) through the low after it (contact); the
/// cut between strokes sits midway through the pause between contact and
/// the next rise. Tops must stand out by 30% of the clip's height range and
/// be at least 0.5 s apart; a top whose rise is cut off by the clip start
/// only needs to stand out after it.
List<(int, int)> segmentStrokesByTops(ImplementTrack imp, double fps) {
  final f = imp.frames;
  if (f.length < 8) return const [];
  final raw = [for (final x in f) x.tip.y];
  final h = [
    for (var i = 0; i < raw.length; i++)
      [for (var j = math.max(0, i - 2); j <= math.min(raw.length - 1, i + 2); j++) raw[j]]
              .reduce((a, b) => a + b) /
          (math.min(raw.length - 1, i + 2) - math.max(0, i - 2) + 1),
  ];
  final lo = h.reduce(math.min), hi = h.reduce(math.max);
  if (hi - lo < 0.2) return const [];
  final prominence = 0.3 * (hi - lo);
  // Local maxima that rise `prominence` above the lows on both sides.
  final tops = <int>[];
  for (var i = 1; i < h.length - 1; i++) {
    if (!(h[i] >= h[i - 1] && h[i] > h[i + 1])) continue;
    var leftLow = h[i], rightLow = h[i];
    var j = i - 1;
    for (; j >= 0 && h[j] <= h[i]; j--) {
      leftLow = math.min(leftLow, h[j]);
    }
    // Reaching the clip start without a higher point: the rise was cut off
    // by the recording (clip starts mid-backswing), so the left side
    // cannot be judged and does not disqualify the top.
    final leftCut = j < 0;
    for (var k = i + 1; k < h.length && h[k] <= h[i]; k++) {
      rightLow = math.min(rightLow, h[k]);
    }
    if (h[i] - leftLow < prominence && !leftCut) continue;
    if (h[i] - rightLow < prominence) continue;
    if (tops.isNotEmpty && (f[i].frame - f[tops.last].frame) / fps < 0.5) {
      if (h[i] > h[tops.last]) tops[tops.length - 1] = i;
      continue;
    }
    tops.add(i);
  }
  if (tops.isEmpty) return const [];
  int argMin(int a, int b) {
    var best = a;
    for (var i = a; i <= b; i++) {
      if (h[i] < h[best]) best = i;
    }
    return best;
  }

  // Boundary between stroke k and k+1: after contact, where the tip has
  // risen 15% of the way back to the next top (pause and settle stay with
  // stroke k; continuous motion gets part of the lift as its recovery).
  int boundary(int k) {
    final contact = argMin(tops[k], tops[k + 1]);
    final rise = 0.15 * (h[tops[k + 1]] - h[contact]);
    final cap = contact + (tops[k + 1] - contact) ~/ 2;
    for (var i = contact; i < cap; i++) {
      if (h[i] - h[contact] >= rise) return i;
    }
    return cap;
  }

  final spans = <(int, int)>[];
  for (var k = 0; k < tops.length; k++) {
    final prevTop = k == 0 ? 0 : tops[k - 1];
    final nextTop = k == tops.length - 1 ? h.length - 1 : tops[k + 1];
    final rise = argMin(prevTop, tops[k]);
    final contact = argMin(tops[k], nextTop);
    // Need a real downswing after the top.
    if (h[tops[k]] - h[contact] < prominence) continue;
    final startIdx =
        k == 0 ? math.max(0, rise - (contact - rise) ~/ 3) : boundary(k - 1) + 1;
    final endIdx = k == tops.length - 1
        ? math.min(h.length - 1, contact + (contact - rise) ~/ 3)
        : boundary(k);
    if (endIdx <= startIdx) continue;
    spans.add((f[startIdx].frame, f[endIdx].frame));
  }
  // Keep spans disjoint.
  final out = <(int, int)>[];
  for (final s in spans) {
    if (out.isNotEmpty && s.$1 <= out.last.$2) {
      out.add((out.last.$2 + 1, s.$2));
    } else {
      out.add(s);
    }
  }
  return [for (final s in out) if (s.$2 > s.$1) s];
}

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
