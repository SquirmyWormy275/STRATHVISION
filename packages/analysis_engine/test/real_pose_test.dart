import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

/// The engine on real human motion (BlazePose output recorded from openly
/// licensed footage; see test/fixtures/README.md).
PoseTrack loadTrack(String file) {
  final j = jsonDecode(File('test/fixtures/$file').readAsStringSync()) as Map;
  List<double> d(Object? l) => [for (final x in l! as List) (x as num).toDouble()];
  return PoseTrack(fps: (j['fps'] as num).toDouble(), frames: [
    for (final s in (j['samples'] as List).cast<Map>())
      poseFrameFromBlazePose(s['f'] as int, d(s['w']), d(s['v']), d(s['p'])),
  ]);
}

void main() {
  final timber = PackDefinition.parse(
      File('../../apps/strathvision/assets/packs/timber.json').readAsStringSync());
  final underhand = timber.event('underhand')!.analysis;
  final cleave = loadTrack('cleave_pose.json');
  const clip = ClipSource(clipId: 'cleave', path: '/x', durationMs: 8144, fps: 29.97);

  AnalysisEngine engine(AnalysisPack pack, PoseTrack track, {bool perStroke = false}) =>
      AnalysisEngine(
          pack: pack,
          pose: PrecomputedPoseEstimator(track),
          implement: const GripImplementTracker(),
          phases: const EventPhaseDetector(),
          perStroke: perStroke);

  test('BlazePose mapping: root-relative, y up, plausible body', () {
    final f = cleave.frames[10];
    expect(f.joints[Joint.pelvis]!.length, lessThan(0.05)); // hip-centred
    expect(f.joints[Joint.neck]!.y, greaterThan(0.3)); // shoulders above hips
    expect(f.joints[Joint.leftAnkle]!.y, lessThan(-0.6)); // ankles below
    final thigh = (f.joints[Joint.leftHip]! - f.joints[Joint.leftKnee]!).length;
    expect(thigh, inInclusiveRange(0.3, 0.6)); // metres
    expect(cleave.meanConfidence, greaterThan(0.6));
  });

  test('two overhead strokes are found from backswing tops', () async {
    final strokes = await engine(underhand, cleave).analyzeStrokes(clip);
    expect(strokes, hasLength(2));
    expect(strokes.every((s) => s.usable), isTrue,
        reason: strokes.map((s) => s.issues).join(','));
  });

  test('phases follow the swing: rise, top, contact, settle', () async {
    final s = (await engine(underhand, cleave).analyzeStrokes(clip)).first;
    final p = (s.detail.outcome as AnalysisSuccess).vector.phases;
    // Hand-checked against the clip: top of backswing ~frame 28, head stops
    // (contact) ~frame 72-80.
    expect(p['downswing']!.startFrame, inInclusiveRange(20, 36));
    expect(p['entry']!.startFrame, inInclusiveRange(70, 82));
    final order = ['setup', 'backswing', 'downswing', 'entry', 'recovery'];
    for (var i = 1; i < order.length; i++) {
      expect(p[order[i]]!.startFrame, p[order[i - 1]]!.endFrame + 1);
    }
  });

  test('per-stroke summary is a valid Metric Vector with plausible values', () async {
    final out = await engine(underhand, cleave, perStroke: true).analyze(clip);
    expect(out, isA<AnalysisSuccess>(), reason: '${out.toJson()}');
    final v = (out as AnalysisSuccess).vector;
    expect(validateMetricVector(v.toJson(), requiredResiduals: ['slope_residual']), isEmpty);
    // The maul points down at impact; knees and hinge are human-range.
    expect(v.metrics['entry_slope']!.value, inInclusiveRange(-80, -10));
    expect(v.metrics['hinge_at_entry']!.value, inInclusiveRange(90, 180));
    expect(v.metrics['lead_knee_at_entry']!.value, inInclusiveRange(100, 180));
    expect(v.metrics['backswing_time']!.value, inInclusiveRange(0.3, 3));
    expect(v.poseConfidenceSummary, greaterThan(0.5));
    // The detail reports how many strokes were found and measured.
    final d = await engine(underhand, cleave, perStroke: true).analyzeDetailed(clip);
    final strokes = await engine(underhand, cleave).analyzeStrokes(clip);
    expect(d.strokes, strokes.length);
    expect(d.usableStrokes, strokes.where((s) => s.usable).length);
    expect(d.usableStrokes, greaterThan(0));
  });

  test('hard footage fails with the Error Contract, not a crash', () async {
    final sb = loadTrack('standing_block_pose.json');
    final out = await engine(timber.event('standing_block')!.analysis, sb, perStroke: true)
        .analyze(const ClipSource(clipId: 'sb', path: '/x', durationMs: 12000, fps: 30));
    if (out is AnalysisFailure) {
      expect(validateAnalysisError(out.toJson()), isEmpty);
    } else {
      expect(validateMetricVector((out as AnalysisSuccess).vector.toJson()), isEmpty);
    }
  });

  test('a profile can be built from real strokes and scored', () async {
    // Each stroke of the clip as its own "reference clip" (ids differ).
    final strokes = await engine(underhand, cleave).analyzeStrokes(clip);
    final vectors = [for (final s in strokes) (s.detail.outcome as AnalysisSuccess).vector];
    final fit = fitMetrics([...vectors, ...vectors], underhand);
    expect(fit['entry_slope']!.spread, greaterThan(0));
    final p = Profile(
      profileId: 'p', version: 1, coachName: 'C', packId: 'timber', eventId: 'underhand',
      metricSchemaVersion: underhand.metricSchemaVersion, createdAt: DateTime.utc(2026),
      sourceClipCount: 15, minClipsMet: true, selfConsistencyPassed: true, notes: '', metrics: fit,
    );
    final r = compare(vector: vectors.first, profile: p, resultId: 'r');
    expect(r, isA<ComparisonSuccess>());
    expect(validateComparisonResult(r.toJson()), isEmpty);
  });
}
