import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

const packJson = {
  'pack_id': 'example_pack',
  'event_id': 'example_event',
  'metric_schema_version': 'example-1',
  'phases': ['phase_1', 'phase_2', 'phase_3'],
  'metrics': [
    {
      'key': 'example_angle',
      'kind': 'joint_angle',
      'phase': 'phase_1',
      'unit': 'deg',
      'joints': ['left_shoulder', 'left_elbow', 'left_wrist'],
    },
    {
      'key': 'example_range',
      'kind': 'joint_range',
      'phase': 'phase_2',
      'unit': 'deg',
      'joints': ['left_hip', 'left_knee', 'left_ankle'],
    },
    {
      'key': 'example_inclination',
      'kind': 'implement_inclination',
      'phase': 'phase_2',
      'unit': 'deg',
    },
    {
      'key': 'example_duration',
      'kind': 'phase_duration',
      'phase': 'phase_3',
      'unit': 's',
    },
  ],
};

const clip = ClipSource(
    clipId: '0b7e7c1e-0000-4000-8000-000000000001',
    path: '/clips/a.mp4',
    durationMs: 10000,
    fps: 30);

class _ThrowingPhases implements PhaseDetector {
  @override
  Map<String, PhaseSpan> detect(ClipSource c, PoseTrack p, ImplementTrack i,
          AnalysisPack pack) =>
      {'phase_1': const PhaseSpan(startFrame: 0, endFrame: 10, confidence: 1)};
}

void main() {
  final pack = AnalysisPack.fromJson(packJson);

  group('analyze (stub pipeline)', () {
    test('returns a Metric Vector that validates against the schema', () async {
      final out = await AnalysisEngine(pack: pack).analyze(clip);
      expect(out, isA<AnalysisSuccess>());
      // Round-trip through JSON text, as a consumer would see it.
      final json = jsonDecode(jsonEncode(out.toJson()));
      expect(validateMetricVector(json), isEmpty);
      final v = MetricVector.fromJson(json as Map<String, Object?>);
      expect(v.clipId, clip.clipId);
      expect(v.packId, 'example_pack');
      expect(v.eventId, 'example_event');
      expect(v.metricSchemaVersion, 'example-1');
      expect(v.phases.keys, ['phase_1', 'phase_2', 'phase_3']);
      expect(v.metrics.keys, containsAll(<String>[
        'example_angle',
        'example_range',
        'example_inclination',
        'example_duration',
      ]));
      expect(v.specialistResiduals, contains('slope_residual'));
      expect(v.specialistResiduals['slope_residual']!.isFinite, isTrue);
    });

    test('phases tile the clip in order', () async {
      final v = ((await AnalysisEngine(pack: pack).analyze(clip))
              as AnalysisSuccess)
          .vector;
      final spans = v.phases.values.toList();
      expect(spans.first.startFrame, 0);
      expect(spans.last.endFrame, clip.frameCount - 1);
      for (var i = 1; i < spans.length; i++) {
        expect(spans[i].startFrame, spans[i - 1].endFrame + 1);
      }
    });

    test('metric values are plausible', () async {
      final v = ((await AnalysisEngine(pack: pack).analyze(clip))
              as AnalysisSuccess)
          .vector;
      expect(v.metrics['example_angle']!.value, inInclusiveRange(0, 180));
      expect(v.metrics['example_range']!.value, greaterThan(0));
      expect(v.metrics['example_inclination']!.value, inInclusiveRange(-90, 90));
      expect(v.metrics['example_duration']!.value, closeTo(10 / 3, 0.05));
      expect(v.poseConfidenceSummary, inInclusiveRange(0.5, 1));
    });

    test('is deterministic per clip and differs across clips', () async {
      final e = AnalysisEngine(pack: pack);
      final a1 = jsonEncode((await e.analyze(clip)).toJson());
      final a2 = jsonEncode((await e.analyze(clip)).toJson());
      expect(a1, a2);
      const other = ClipSource(
          clipId: 'another-clip', path: '/clips/b.mp4', durationMs: 10000, fps: 30);
      final b = jsonEncode((await e.analyze(other)).toJson());
      expect(b, isNot(a1));
    });

    test('long clips are sampled, not processed frame by frame', () async {
      const long = ClipSource(
          clipId: 'long', path: '/x', durationMs: 20 * 60 * 1000, fps: 60);
      final track = await const StubPoseEstimator().estimate(long);
      expect(track.frames.length, lessThanOrEqualTo(maxPoseSamples));
      final out = await AnalysisEngine(pack: pack).analyze(long);
      expect(validateMetricVector(out.toJson()), isEmpty);
    });
  });

  group('failure cases return the Error Contract', () {
    Future<AnalysisError> fail(AnalysisEngine e, ClipSource c) async {
      final out = await e.analyze(c);
      expect(out, isA<AnalysisFailure>());
      final json = jsonDecode(jsonEncode(out.toJson()));
      expect(validateAnalysisError(json), isEmpty);
      return AnalysisError.fromJson(json as Map<String, Object?>);
    }

    test('empty clip → PHASE_DETECTION_FAILED', () async {
      const empty =
          ClipSource(clipId: 'e', path: '/x', durationMs: 0, fps: 30);
      final e = await fail(AnalysisEngine(pack: pack), empty);
      expect(e.errorCode, 'PHASE_DETECTION_FAILED');
    });

    test('clip too short for every phase → PHASE_DETECTION_FAILED', () async {
      const short =
          ClipSource(clipId: 's', path: '/x', durationMs: 200, fps: 30);
      final e = await fail(AnalysisEngine(pack: pack), short);
      expect(e.errorCode, 'PHASE_DETECTION_FAILED');
      expect(e.details['frame_count'], 6);
    });

    test('poor pose → LOW_POSE_CONFIDENCE', () async {
      final e = await fail(
          AnalysisEngine(
              pack: pack, pose: const StubPoseEstimator(confidence: 0.2)),
          clip);
      expect(e.errorCode, 'LOW_POSE_CONFIDENCE');
      expect(e.details['threshold'], 0.5);
    });

    test('detector missing a phase → PHASE_DETECTION_FAILED', () async {
      final e = await fail(
          AnalysisEngine(pack: pack, phases: _ThrowingPhases()), clip);
      expect(e.errorCode, 'PHASE_DETECTION_FAILED');
      expect(e.details['missing_phases'], ['phase_2', 'phase_3']);
    });

    test('invalid pack → SCHEMA_MISMATCH with every problem', () {
      expect(
        () => AnalysisPack.fromJson({
          'pack_id': 'p',
          'event_id': '',
          'metric_schema_version': 'v',
          'phases': ['a'],
          'metrics': [
            {'key': 'm', 'kind': 'joint_angle', 'phase': 'b', 'unit': 'deg'},
          ],
        }),
        throwsA(isA<AnalysisError>()
            .having((e) => e.errorCode, 'code', 'SCHEMA_MISMATCH')
            .having((e) => e.details['problems'], 'problems', hasLength(3))),
      );
    });
  });

  group('slope_residual stub head', () {
    test('has the DECISIONS.md shape and returns a number', () {
      final h = stubSlopeResidualHead();
      expect(h.name, 'slope_residual');
      expect(h.parameterCount, 2113);
      expect(h.parameterCount, lessThan(10000));
      final y = h.evaluate(List.filled(featureWidth, 0.3));
      expect(y.isFinite, isTrue);
      expect(y, isNot(0));
    });

    test('rejects a feature vector of the wrong width', () {
      expect(() => stubSlopeResidualHead().evaluate([1, 2, 3]),
          throwsArgumentError);
    });
  });

  group('validators', () {
    late Map<String, Object?> good;
    setUp(() async {
      good = jsonDecode(jsonEncode(
              (await AnalysisEngine(pack: pack).analyze(clip)).toJson()))
          as Map<String, Object?>;
    });

    test('missing specialist_residuals.slope_residual is invalid', () {
      good['specialist_residuals'] = <String, Object?>{};
      expect(validateMetricVector(good),
          contains('specialist_residuals.slope_residual is required'));
    });

    test('metric referencing an unknown phase is invalid', () {
      (good['metrics'] as Map)['example_angle']['phase'] = 'nope';
      expect(validateMetricVector(good).single, contains('not in phases'));
    });

    test('confidence out of range and reversed span are invalid', () {
      (good['phases'] as Map)['phase_1']['confidence'] = 1.5;
      (good['phases'] as Map)['phase_2']['end_frame'] = 0;
      expect(validateMetricVector(good), hasLength(2));
    });

    test('non-object is invalid', () {
      expect(validateMetricVector([]), isNotEmpty);
    });

    test('comparison result contract', () {
      const r = ComparisonResult(
        resultId: 'r',
        clipId: 'c',
        profileId: 'p',
        profileVersion: 1,
        overallScore: 0.8,
        rankedDeltas: [
          RankedDelta(
            metricKey: 'example_angle',
            userValue: 1,
            coachCenter: 2,
            coachSpread: 0.5,
            distanceSpreads: 2,
            contribution: 0.4,
            phase: 'phase_1',
            direction: 'lower',
          ),
        ],
        metricsUsed: 1,
        metricsMissing: [],
        lowConfidencePhases: [],
        nearestReferenceClipIds: [],
        warnings: [],
        appliedPatches: ['slope_residual_v3'],
      );
      final json = jsonDecode(jsonEncode(r.toJson()));
      expect(validateComparisonResult(json), isEmpty);
      (json as Map)['ranked_deltas'][0]['direction'] = 'up';
      json['score_meaning'] = 'quality';
      expect(validateComparisonResult(json), hasLength(2));
    });

    test('error contract rejects unknown codes', () {
      expect(validateAnalysisError(
              {'error_code': 'OOPS', 'message': 'm', 'details': {}}),
          hasLength(1));
    });
  });
}
