import 'contracts.dart';
import 'errors.dart';
import 'features.dart';
import 'heads.dart';
import 'pack.dart';
import 'body.dart';
import 'stages.dart';
import 'vision_stages.dart';
import 'strokes.dart';

/// Success payload or Error Contract, never both.
sealed class AnalysisOutcome {
  const AnalysisOutcome();

  /// The wire JSON: a Metric Vector or an Error Contract object.
  Map<String, Object?> toJson();
}

class AnalysisSuccess extends AnalysisOutcome {
  const AnalysisSuccess(this.vector);
  final MetricVector vector;
  @override
  Map<String, Object?> toJson() => vector.toJson();
}

class AnalysisFailure extends AnalysisOutcome {
  const AnalysisFailure(this.error);
  final AnalysisError error;
  @override
  Map<String, Object?> toJson() => error.toJson();
}

class AnalysisDetail {
  const AnalysisDetail(this.outcome, this.phasePoseConfidence,
      {this.implementConfidence = 0,
      this.features = const [],
      this.headBases = const {}});
  final AnalysisOutcome outcome;

  /// The feature vector given to the heads (harness input).
  final List<double> features;

  /// Per head: the measured error it started from (target − reference).
  final Map<String, double> headBases;

  /// Mean implement-track confidence over the clip (probe input).
  final double implementConfidence;

  /// Mean joint confidence inside each phase. Empty on failure.
  final Map<String, double> phasePoseConfidence;
}

/// Clip → Metric Vector, following the pipeline in ARCHITECTURE.md:
/// pose + implement → phases → metrics → feature vector → specialist heads.
class AnalysisEngine {
  AnalysisEngine({
    required this.pack,
    this.pose = const StubPoseEstimator(),
    this.implement = const StubImplementTracker(),
    this.phases = const StubPhaseDetector(),
    List<SpecialistHead>? heads,
    this.perStroke = false,
  }) : heads = heads ?? headsFor(pack);

  /// Analyze each stroke and summarize (median of strokes), instead of the
  /// whole clip as one movement. Used with real pose; falls back to the
  /// whole clip when no strokes are found.
  final bool perStroke;

  final AnalysisPack pack;
  final PoseEstimator pose;
  final ImplementTracker implement;
  final PhaseDetector phases;
  final List<SpecialistHead> heads;

  /// [reference] holds the coach's metric centers when comparing with a
  /// profile; heads measure their target's error against it.
  Future<AnalysisOutcome> analyze(ClipSource clip,
          {Map<String, double> reference = const {}}) async =>
      (await analyzeDetailed(clip, reference: reference)).outcome;

  /// [analyze] plus internals the profile builder needs (per-phase pose
  /// confidence). The Metric Vector contract is unchanged.
  Future<AnalysisDetail> analyzeDetailed(ClipSource clip,
      {Map<String, double> reference = const {}}) async {
    if (perStroke) {
      final strokes = await analyzeStrokes(clip, reference: reference);
      final good = [
        for (final s in strokes)
          if (s.usable && s.detail.outcome is AnalysisSuccess) s,
      ];
      if (good.isNotEmpty) {
        final vectors = [for (final s in good) (s.detail.outcome as AnalysisSuccess).vector];
        final summary = summarizeStrokes(vectors);
        final problems = validateMetricVector(summary.toJson(),
            requiredResiduals: [for (final h in pack.heads) h.name]);
        if (problems.isEmpty) {
          final first = good.first.detail;
          return AnalysisDetail(AnalysisSuccess(summary), {
            for (final p in pack.phases)
              p: _r(good.map((s) => s.detail.phasePoseConfidence[p] ?? 0).reduce((a, b) => a + b) /
                  good.length),
          },
              implementConfidence: _r(
                  good.map((s) => s.detail.implementConfidence).reduce((a, b) => a + b) / good.length),
              features: first.features,
              headBases: first.headBases);
        }
      }
    }
    try {
      if (clip.durationMs <= 0 || clip.fps <= 0) {
        throw AnalysisError(
          ErrorCode.phaseDetectionFailed,
          'The clip has no frames to analyze.',
          {'duration_ms': clip.durationMs, 'fps': clip.fps},
        );
      }
      final track = await pose.estimate(clip);
      final poseConf = track.meanConfidence;
      if (poseConf < pack.minPoseConfidence) {
        throw AnalysisError(
          ErrorCode.lowPoseConfidence,
          'The body is not visible clearly enough in this clip.',
          {
            'pose_confidence_summary': _r(poseConf),
            'threshold': pack.minPoseConfidence,
          },
        );
      }
      final imp = await implement.track(clip, track);
      return _spanDetail(clip, track, imp, reference, poseConf);
    } on AnalysisError catch (e) {
      return AnalysisDetail(AnalysisFailure(e), const {});
    }
  }


  /// Splits [clip] into strokes (implement-speed peaks) and analyzes each.
  /// Pose and implement are estimated once. A clip whose body cannot be
  /// tracked at all returns an empty list.
  Future<List<StrokeDetail>> analyzeStrokes(ClipSource clip,
      {Map<String, double> reference = const {}}) async {
    if (clip.durationMs <= 0 || clip.fps <= 0) return const [];
    final track = await pose.estimate(clip);
    final imp = await implement.track(clip, track);
    final spans = pack.strokeSignal == 'tops'
        ? segmentStrokesByTops(imp, clip.fps)
        : segmentStrokes(imp, clip.fps);
    final clipDropout = longestDropout(imp, clip.fps, 0, clip.frameCount - 1);
    final out = <StrokeDetail>[];
    for (var i = 0; i < spans.length; i++) {
      final (start, end) = spans[i];
      final span = clip.withSpan(start, end);
      final frames = track.frames.where((f) => f.frame >= start && f.frame <= end);
      final poseConf = frames.isEmpty
          ? 0.0
          : PoseTrack(fps: track.fps, frames: frames.toList()).meanConfidence;
      final dropout = longestDropout(imp, clip.fps, start, end);
      AnalysisDetail detail;
      try {
        detail = _spanDetail(span, track, imp, reference, poseConf);
      } on AnalysisError catch (e) {
        detail = AnalysisDetail(AnalysisFailure(e), const {});
      }
      out.add(StrokeDetail(
        clipId: clip.clipId,
        index: i,
        startFrame: start,
        endFrame: end,
        fps: clip.fps,
        detail: detail,
        dropoutSeconds: dropout,
        clipDropoutSeconds: clipDropout,
        pack: pack,
      ));
    }
    return out;
  }

  /// Phases → metrics → features → heads for [clip]'s span, given the
  /// tracks. Throws [AnalysisError].
  AnalysisDetail _spanDetail(ClipSource clip, PoseTrack track, ImplementTrack imp,
      Map<String, double> reference, double poseConf) {
      final spans = phases.detect(clip, track, imp, pack);
      final missing = pack.phases.where((p) => !spans.containsKey(p)).toList();
      if (missing.isNotEmpty) {
        throw AnalysisError(ErrorCode.phaseDetectionFailed,
            'Some phases were not found.', {'missing_phases': missing});
      }
      final metrics = extractMetrics(
          pack: pack, pose: track, implement: imp, phases: spans);
      final features = featureVector(
          pack: pack,
          pose: track,
          implement: imp,
          phases: spans,
          metrics: metrics);
      final targets = {for (final d in pack.heads) d.name: d.targetMetric};
      final residuals = <String, double>{};
      final bases = <String, double>{};
      for (final h in heads) {
        final target = targets[h.name];
        final measured = target == null ? null : metrics[target]?.value;
        final ref = target == null ? null : reference[target];
        final base = measured == null || ref == null ? 0.0 : measured - ref;
        bases[h.name] = base;
        residuals[h.name] = _r(h.evaluate(features, base: base));
      }
      final vector = MetricVector(
        clipId: clip.clipId,
        packId: pack.packId,
        eventId: pack.eventId,
        metricSchemaVersion: pack.metricSchemaVersion,
        phases: spans,
        metrics: metrics,
        poseConfidenceSummary: _r(poseConf),
        specialistResiduals: residuals,
      );
      // The engine never hands out a payload that breaks the contract.
      final problems = validateMetricVector(vector.toJson(),
          requiredResiduals: [for (final h in pack.heads) h.name]);
      if (problems.isNotEmpty) {
        throw AnalysisError(ErrorCode.schemaMismatch,
            'Analysis produced an invalid Metric Vector.', {'problems': problems});
      }
      final trackConf = imp.frames.isEmpty
          ? 0.0
          : imp.frames.map((f) => f.confidence).reduce((a, b) => a + b) /
              imp.frames.length;
      return AnalysisDetail(AnalysisSuccess(vector), {
        for (final e in spans.entries)
          e.key: _r(_phasePoseConfidence(track, e.value)),
      },
          implementConfidence: _r(trackConf),
          features: features,
          headBases: bases);
  }

  static double _phasePoseConfidence(PoseTrack track, PhaseSpan span) {
    var sum = 0.0, n = 0;
    for (final f in track.frames) {
      if (f.frame < span.startFrame || f.frame > span.endFrame) continue;
      for (final c in f.confidence.values) {
        sum += c;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  static double _r(double v) => (v * 1e4).roundToDouble() / 1e4;
}
