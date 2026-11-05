import 'dart:math' as math;

import 'body.dart';
import 'contracts.dart';
import 'errors.dart';
import 'pack.dart';
import 'stages.dart';
import 'strokes.dart';

/// A pose track computed elsewhere (on device, by the app's pose model) and
/// handed to the engine. Lets the engine run in an isolate while the model
/// runs where the video decoder lives.
class PrecomputedPoseEstimator implements PoseEstimator {
  const PrecomputedPoseEstimator(this.track);
  final PoseTrack track;

  @override
  Future<PoseTrack> estimate(ClipSource clip) async => track;
}

/// Implement inferred from the grip: a rigid segment starting between the
/// hands and pointing along the forearms. Confidence is the better-seen
/// wrist's (both hands are on the handle).
/// (A dedicated implement detector can replace this behind the same
/// interface.)
class GripImplementTracker implements ImplementTracker {
  const GripImplementTracker({this.length = 0.75});

  /// Segment length beyond the grip, metres.
  final double length;

  @override
  Future<ImplementTrack> track(ClipSource clip, PoseTrack pose) async => ImplementTrack(frames: [
        for (final p in pose.frames)
          () {
            final lw = p.joints[Joint.leftWrist]!, rw = p.joints[Joint.rightWrist]!;
            final le = p.joints[Joint.leftElbow]!, re = p.joints[Joint.rightElbow]!;
            final grip = (lw + rw).scale(0.5);
            final dir = grip - (le + re).scale(0.5);
            final n = dir.length == 0 ? 1.0 : dir.length;
            // Both hands hold the implement: the better-seen wrist suffices.
            final conf = math.max(p.confidence[Joint.leftWrist] ?? 0, p.confidence[Joint.rightWrist] ?? 0);
            return ImplementFrame(
                frame: p.frame, grip: grip, tip: grip + dir.scale(length / n), confidence: conf);
          }(),
      ]);
}

/// Moving average over [r] samples either side.
List<double> _smooth(List<double> xs, int r) => [
      for (var i = 0; i < xs.length; i++)
        () {
          final a = math.max(0, i - r), b = math.min(xs.length - 1, i + r);
          var s = 0.0;
          for (var j = a; j <= b; j++) {
            s += xs[j];
          }
          return s / (b - a + 1);
        }(),
    ];

/// Phase boundaries from pack-declared motion events on the implement tip
/// (pack `phase_events`, one per boundary, in order):
///
/// * `low_before_top` – lowest tip point before the highest point (rise)
/// * `top` – highest tip point
/// * `fastest` – peak tip speed
/// * `low` – contact: after the fastest descent, the first point where the
///   descent has slowed to 20% (the head stopped)
/// * `settle` – first point where tip speed falls below 25% of the peak
///   after the previous boundary
/// * `reach` – end of the backswing: the turnaround (speed minimum) just
///   before the fastest point, high or flat
/// * `rise` – start of the backswing: the slowest moment before the reach
/// * `stop` – contact by speed: after the fastest point the head stops
///   (below 30% of that speed, in any direction); the boundary is the
///   midpoint between the last fast and first slow sample (unsmoothed)
/// * `release` – after the previous boundary, the first point back above
///   30% of the stroke's peak speed (the implement pulled free)
///
/// Each event is searched after the previous boundary. Without declared
/// events the clip is split evenly at confidence 0.5.
class EventPhaseDetector implements PhaseDetector {
  const EventPhaseDetector();

  @override
  Map<String, PhaseSpan> detect(
      ClipSource clip, PoseTrack pose, ImplementTrack implement, AnalysisPack pack) {
    final events = pack.phaseEvents;
    if (events.isEmpty) {
      return const StubPhaseDetector().detect(clip, pose, implement, pack);
    }
    final start = clip.startFrame, end = clip.spanEnd;
    final imp = implement.frames.where((f) => f.frame >= start && f.frame <= end).toList();
    AnalysisError fail(String why) => AnalysisError(ErrorCode.phaseDetectionFailed,
        'The phases of this movement could not be found.', {'reason': why});
    if (imp.length < pack.phases.length * 2) throw fail('too few tracked frames');

    final h = _smooth([for (final f in imp) f.tip.y], 2);
    final v = _smooth([
      0.0,
      for (var i = 1; i < imp.length; i++)
        (imp[i].tip - imp[i - 1].tip).length /
            math.max(1, imp[i].frame - imp[i - 1].frame) *
            clip.fps,
    ], 2);
    // Vertical tip velocity (m/s), smoothed harder: it decides contact.
    final vy = _smooth([
      0.0,
      for (var i = 1; i < imp.length; i++)
        (h[i] - h[i - 1]) / math.max(1, imp[i].frame - imp[i - 1].frame) * clip.fps,
    ], 3);
    int argBy(int from, int to, double Function(int) key, {bool max = true}) {
      var best = from;
      for (var i = from; i <= to; i++) {
        if (max ? key(i) > key(best) : key(i) < key(best)) best = i;
      }
      return best;
    }

    final last = imp.length - 1;
    // Lightly smoothed speed on de-glitched tips: a stop in the material
    // is sharp (one or two samples) and heavier smoothing hides it.
    final tips = despikedTips(ImplementTrack(frames: imp));
    final v1 = tipSpeed(ImplementTrack(frames: imp), tips, clip.fps);
    final raw = tipSpeed(ImplementTrack(frames: imp), tips, clip.fps, r: 0);
    // Contact by speed.
    int stopAfter(int from) {
      final peak = argBy(from, last, (i) => v1[i]);
      for (var i = peak + 1; i <= last; i++) {
        if (v1[i] < 0.3 * v1[peak]) return i;
      }
      return argBy(peak, last, (i) => v1[i], max: false);
    }

    // End of the backswing: the turnaround before the fastest point, where
    // the tip is slowest just before it accelerates into the swing (high or
    // flat swings alike).
    int reachFrom(int from) {
      final peak = argBy(from, last, (i) => v1[i]);
      var j = peak;
      while (j - 1 >= from && v1[j - 1] <= v1[j]) {
        j--;
      }
      return j;
    }

    final cuts = <int>[];
    // Boundary frame per cut when it falls between two samples (contact).
    final cutFrames = <int, int>{};
    var cursor = 0;
    for (var ei = 0; ei < events.length; ei++) {
      final e = events[ei];
      final from = cursor + 1;
      if (from >= last) {
        // Only the final boundary may be cut off by the end of the stroke:
        // the last phase then runs to the end (counted as cut short).
        if (ei == events.length - 1 && cursor < last) {
          cuts.add(last);
          break;
        }
        throw fail('ran out of movement before "$e"');
      }
      final idx = switch (e) {
        'top' => argBy(from, last, (i) => h[i]),
        'fastest' => argBy(from, last, (i) => v[i]),
        'low' => () {
            // Contact: after the fastest descent, the first moment the
            // descent has slowed to 20% of it (the head stopped).
            final down = argBy(from, last, (i) => vy[i], max: false);
            if (vy[down] >= 0) return argBy(from, last, (i) => h[i], max: false);
            for (var i = down + 1; i <= last; i++) {
              if (vy[i] > 0.2 * vy[down]) return i;
            }
            return last;
          }(),
        'settle' => () {
            final peak = v.sublist(from - 1).reduce(math.max);
            for (var i = from; i <= last; i++) {
              if (v[i] < 0.25 * peak) return i;
            }
            return last;
          }(),
        'stop' => () {
            // Contact lies between the last fast sample and the first slow
            // one (unsmoothed speed): the boundary frame is their midpoint.
            // Smoothed speed alone placed it about 3 frames late.
            final s1 = stopAfter(from);
            var p = s1;
            for (var i = s1; i >= from; i--) {
              if (v1[i] > v1[p]) p = i;
              if (v1[i] < 0.3 * v1[p]) break;
            }
            var r = p + 1;
            while (r <= last && raw[r] >= 0.3 * v1[p]) {
              r++;
            }
            if (r > last || r <= from) return s1;
            cutFrames[cuts.length] = (imp[r - 1].frame + imp[r].frame) ~/ 2;
            return r;
          }(),
        'reach' => reachFrom(from),
        'rise' => () {
            // Start of the backswing: the slowest moment between the stroke
            // start and the reach (at least two samples before it).
            final r = reachFrom(from);
            return r - 2 <= from ? from : argBy(from, r - 2, (i) => v[i], max: false);
          }(),
        'release' => () {
            // Pulled free: after the stop, the first moment the tip moves
            // at 30% of the stroke's peak speed again.
            final peak = v1.reduce(math.max);
            for (var i = from; i <= last; i++) {
              if (v1[i] > 0.3 * peak) return i;
            }
            return last;
          }(),
        'low_before_top' => () {
            final top = argBy(from, last, (i) => h[i]);
            return top <= from ? from : argBy(from, top - 1, (i) => h[i], max: false);
          }(),
        _ => throw fail('unknown event "$e"'),
      };
      cuts.add(idx);
      cursor = idx;
    }
    if (cuts.length < events.length) throw fail('not every boundary was found');
    // Sample indices → clip frames; phases must have room.
    final bounds = [
      start,
      for (var k = 0; k < cuts.length; k++) cutFrames[k] ?? imp[cuts[k]].frame,
      end + 1,
    ];
    // Middle phases need full length. The first and last may be cut short
    // by the recording (clip starts mid-backswing, ends just after contact);
    // they need one frame and count at half confidence.
    final short = <int>{};
    for (var i = 1; i < bounds.length; i++) {
      final n = bounds[i] - bounds[i - 1];
      final edge = i == 1 || i == bounds.length - 1;
      if (n < 1 || (!edge && n < pack.minPhaseFrames)) {
        throw fail('phase ${pack.phases[i - 1]} is too short');
      }
      if (n < pack.minPhaseFrames) short.add(i - 1);
    }
    // Confidence: how clearly the tip moves (range vs body scale) × tracking.
    final range = h.reduce(math.max) - h.reduce(math.min);
    final clarity = (range / 0.6).clamp(0.0, 1.0);
    final track = imp.map((f) => f.confidence).reduce((a, b) => a + b) / imp.length;
    final conf = double.parse((clarity * track).toStringAsFixed(4));
    return {
      for (var i = 0; i < pack.phases.length; i++)
        pack.phases[i]: PhaseSpan(
            startFrame: bounds[i],
            endFrame: bounds[i + 1] - 1,
            confidence: short.contains(i) ? double.parse((conf / 2).toStringAsFixed(4)) : conf,
            cutShort: short.contains(i)),
    };
  }
}

/// Median-of-strokes summary: one Metric Vector for a clip of many strokes.
/// Each metric is the median over usable strokes (confidence: their mean);
/// phases come from the stroke nearest the median.
MetricVector summarizeStrokes(List<MetricVector> strokes) {
  double median(List<double> xs) {
    final s = [...xs]..sort();
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  }

  double r(double v) => (v * 1e4).roundToDouble() / 1e4;
  final keys = {for (final v in strokes) ...v.metrics.keys};
  final metrics = <String, MetricValue>{};
  for (final k in keys) {
    final vals = [for (final v in strokes) if (v.metrics[k] != null) v.metrics[k]!];
    metrics[k] = MetricValue(
      value: r(median([for (final m in vals) m.value])),
      confidence: r(vals.map((m) => m.confidence).reduce((a, b) => a + b) / vals.length),
      phase: vals.first.phase,
    );
  }
  // Representative stroke: smallest summed distance to the medians.
  MetricVector rep = strokes.first;
  var best = double.infinity;
  for (final v in strokes) {
    var d = 0.0;
    for (final k in keys) {
      final m = v.metrics[k];
      if (m != null) d += (m.value - metrics[k]!.value).abs();
    }
    if (d < best) {
      best = d;
      rep = v;
    }
  }
  final residuals = <String, double>{};
  for (final k in strokes.first.specialistResiduals.keys) {
    residuals[k] = r(median([for (final v in strokes) v.specialistResiduals[k] ?? 0]));
  }
  return MetricVector(
    clipId: strokes.first.clipId,
    packId: strokes.first.packId,
    eventId: strokes.first.eventId,
    metricSchemaVersion: strokes.first.metricSchemaVersion,
    phases: rep.phases,
    metrics: metrics,
    poseConfidenceSummary:
        r(strokes.map((v) => v.poseConfidenceSummary).reduce((a, b) => a + b) / strokes.length),
    specialistResiduals: residuals,
  );
}
