import 'dart:math' as math;

import 'body.dart';
import 'contracts.dart';
import 'pack.dart';

/// Computes the pack's metric catalog from pose + implement + phases.
/// Generic: every metric is one of [MetricKind].
Map<String, MetricValue> extractMetrics({
  required AnalysisPack pack,
  required PoseTrack pose,
  required ImplementTrack implement,
  required Map<String, PhaseSpan> phases,
}) {
  final out = <String, MetricValue>{};
  for (final m in pack.metrics) {
    final span = phases[m.phase]!;
    bool inSpan(int f) => f >= span.startFrame && f <= span.endFrame;
    final frames = pose.frames.where((p) => inSpan(p.frame)).toList();
    double value;
    double conf;
    switch (m.kind) {
      case MetricKind.jointAngle || MetricKind.jointRange:
        final [a, b, c] = m.joints;
        final angles = [
          for (final f in frames) angleDeg(f.joints[a]!, f.joints[b]!, f.joints[c]!),
        ];
        if (angles.isEmpty) {
          value = 0;
        } else if (m.kind == MetricKind.jointAngle) {
          value = angles.reduce((x, y) => x + y) / angles.length;
        } else {
          value = angles.reduce(math.max) - angles.reduce(math.min);
        }
        conf = _meanMin(frames, [a, b, c]);
      case MetricKind.implementInclination:
        final imp = implement.frames.where((i) => inSpan(i.frame)).toList();
        value = imp.isEmpty
            ? 0
            : imp.map((i) => i.inclinationDeg).reduce((x, y) => x + y) / imp.length;
        conf = imp.isEmpty
            ? 0
            : imp.map((i) => i.confidence).reduce((x, y) => x + y) / imp.length;
      case MetricKind.phaseDuration:
        value = (span.endFrame - span.startFrame + 1) / pose.fps;
        conf = 1;
    }
    out[m.key] = MetricValue(
      value: _round(value),
      confidence: _round((conf * span.confidence).clamp(0.0, 1.0)),
      phase: m.phase,
    );
  }
  return out;
}

/// Mean over frames of the weakest joint confidence among [joints].
double _meanMin(List<PoseFrame> frames, List<Joint> joints) {
  if (frames.isEmpty) return 0;
  var sum = 0.0;
  for (final f in frames) {
    sum += joints.map((j) => f.confidence[j] ?? 0).reduce(math.min);
  }
  return sum / frames.length;
}

double _round(double v) => (v * 1e4).roundToDouble() / 1e4;

/// Width of the feature vector that specialist heads consume.
const featureWidth = 64;

/// Fixed-width feature vector for specialist heads:
/// [normalized metrics in pack order] + [mean implement inclination per
/// phase / 90] + [mean root-relative joint positions], zero-padded or
/// truncated to [featureWidth].
List<double> featureVector({
  required AnalysisPack pack,
  required PoseTrack pose,
  required ImplementTrack implement,
  required Map<String, PhaseSpan> phases,
  required Map<String, MetricValue> metrics,
}) {
  final v = <double>[];
  for (final m in pack.metrics) {
    final x = metrics[m.key]!.value;
    v.add(switch (m.kind) {
      MetricKind.phaseDuration => x / 10,
      _ => x / 180,
    });
  }
  for (final p in pack.phases) {
    final s = phases[p]!;
    final imp = implement.frames
        .where((i) => i.frame >= s.startFrame && i.frame <= s.endFrame)
        .toList();
    v.add(imp.isEmpty
        ? 0
        : imp.map((i) => i.inclinationDeg).reduce((a, b) => a + b) /
            imp.length /
            90);
  }
  if (pose.frames.isNotEmpty) {
    for (final j in Joint.values) {
      var sum = const Vec3(0, 0, 0);
      for (final f in pose.frames) {
        sum = sum + f.joints[j]!;
      }
      final m = sum.scale(1 / pose.frames.length);
      v.addAll([m.x, m.y, m.z]);
    }
  }
  if (v.length >= featureWidth) return v.sublist(0, featureWidth);
  return [...v, ...List.filled(featureWidth - v.length, 0.0)];
}
