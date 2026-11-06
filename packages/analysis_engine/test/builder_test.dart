import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show packJson;

/// Phase 4 acceptance: from 15+ synthetic clips of one "coach" the builder
/// produces a ready profile or a structured rejection; the profile validates
/// against INTERFACES.md; self-consistency is automated.
void main() {
  final pack = AnalysisPack.fromJson(packJson);
  final now = DateTime.utc(2026, 11, 4, 12);

  List<ClipSource> clips(String prefix, int n, {int durationMs = 6000}) => [
        for (var i = 0; i < n; i++)
          ClipSource(
              clipId: '$prefix-$i',
              path: '/clips/$prefix-$i.mp4',
              durationMs: durationMs,
              fps: 30),
      ];

  Future<List<ClipQuality>> evaluateAll(ProfileBuilder b, List<ClipSource> cs) =>
      Future.wait([for (final c in cs) b.evaluate(c, displayName: c.clipId)]);

  ProfileBuilder coach(int styleSeed, {AnalysisPack? p, double conf = 0.85}) =>
      ProfileBuilder(
          engine: AnalysisEngine(
              pack: p ?? pack,
              pose: StubPoseEstimator(styleSeed: styleSeed, confidence: conf)));

  group('clip import and quality evaluation', () {
    test('clean clip is usable with its Metric Vector', () async {
      final q = await coach(7).evaluate(clips('c', 1).single, displayName: 'c-0');
      expect(q.usable, isTrue);
      expect(q.reasons, isEmpty);
      expect(validateMetricVector(q.vector!.toJson()), isEmpty);
      expect(q.criticalPoseConfidence, greaterThan(0.6));
    });

    test('too-short clip is unusable with the Error Contract', () async {
      final q = await coach(7).evaluate(
          const ClipSource(clipId: 's', path: '/s', durationMs: 100, fps: 30),
          displayName: 's');
      expect(q.usable, isFalse);
      expect(q.error!.errorCode, 'PHASE_DETECTION_FAILED');
      expect(q.reasons.single, isNotEmpty);
    });

    test('dim clip fails the critical-phase pose gate', () async {
      final q = await coach(7, conf: 0.55)
          .evaluate(clips('d', 1).single, displayName: 'd');
      expect(q.usable, isFalse);
      expect(q.reasons.single, contains('hard to see'));
    });
  });

  group('fitting', () {
    test('center is the mean, spread the sample SD, weights average 1', () {
      MetricVector v(String id, double x, double conf) => MetricVector(
            clipId: id,
            packId: 'example_pack',
            eventId: 'example_event',
            metricSchemaVersion: 'example-1',
            phases: const {
              'phase_1': PhaseSpan(startFrame: 0, endFrame: 9, confidence: 1),
            },
            metrics: {
              'example_angle':
                  MetricValue(value: x, confidence: conf, phase: 'phase_1'),
              'example_duration':
                  MetricValue(value: 2, confidence: conf / 2, phase: 'phase_3'),
            },
            poseConfidenceSummary: 0.9,
            specialistResiduals: const {'slope_residual': 0},
          );
      final fit = fitMetrics([v('a', 10, 0.8), v('b', 12, 0.8), v('c', 14, 0.8)], pack);
      expect(fit['example_angle']!.center, 12);
      expect(fit['example_angle']!.spread, 2);
      expect(fit['example_angle']!.unit, 'deg');
      expect(fit['example_angle']!.phase, 'phase_1');
      // Constant metric: spread floored, never zero.
      expect(fit['example_duration']!.spread, greaterThan(0));
      // Lower-confidence metric weighs less; weights average 1.
      final wa = fit['example_angle']!.weight, wd = fit['example_duration']!.weight;
      expect(wa, greaterThan(wd));
      expect((wa + wd) / 2, closeTo(1, 1e-3));
      // Metrics missing from every clip are left out.
      expect(fit.containsKey('example_range'), isFalse);
    });

    test('style-match score is 1 at the center and falls with distance', () {
      const m = ProfileMetric(
          center: 10, spread: 2, weight: 1, unit: 'deg', phase: 'phase_1');
      expect(styleMatchScore({'k': 10}, {'k': m}), 1);
      expect(styleMatchScore({'k': 12}, {'k': m}), closeTo(0.6065, 1e-4));
      expect(styleMatchScore({'k': 30}, {'k': m}), lessThan(1e-6));
      expect(styleMatchScore({}, {'k': m}), isNull);
    });
  });

  group('build', () {
    test('15 clean clips of one coach → ready profile that validates', () async {
      final b = coach(42);
      final q = await evaluateAll(b, clips('coach', 16));
      final out = b.build(
          coachName: 'Synthetic Coach', clips: q, newProfileId: 'p-1', now: now);
      expect(out, isA<BuildReady>());
      final profile = (out as BuildReady).profile;
      final json = jsonDecode(jsonEncode(profile.toJson()));
      expect(validateProfile(json), isEmpty);
      expect(profile.version, 1);
      expect(profile.ready, isTrue);
      expect(profile.sourceClipCount, 16);
      expect(profile.metrics.keys, hasLength(4));
      expect(profile.referenceClips, hasLength(16));
      expect(out.consistency.passed, isTrue);
      // Round-trips.
      final back = Profile.fromJson(json as Map<String, Object?>);
      expect(jsonEncode(back.toJson()), jsonEncode(profile.toJson()));
    });

    test('package has profile.json and empty specialist_patches/ and adapters/',
        () async {
      final b = coach(42);
      final out = b.build(
          coachName: 'C',
          clips: await evaluateAll(b, clips('coach', 15)),
          newProfileId: 'p-1',
          now: now) as BuildReady;
      final entries = out.profile.packageEntries();
      expect(entries.keys,
          unorderedEquals(['profile.json', 'specialist_patches/', 'adapters/']));
      expect(entries['specialist_patches/'], isNull);
      expect(entries['adapters/'], isNull);
      expect(validateProfile(jsonDecode(entries['profile.json']!)), isEmpty);
    });

    test('rebuilding from a previous profile keeps the id, bumps the version',
        () async {
      final b = coach(42);
      final q = await evaluateAll(b, clips('coach', 15));
      final v1 = (b.build(coachName: 'C', clips: q, newProfileId: 'p-1', now: now)
              as BuildReady)
          .profile;
      final v2 = (b.build(
              coachName: 'C',
              clips: q,
              newProfileId: 'ignored',
              now: now,
              previous: v1) as BuildReady)
          .profile;
      expect(v2.profileId, 'p-1');
      expect(v2.version, 2);
    });

    test('too few usable clips → INSUFFICIENT_CLIPS rejection', () async {
      final b = coach(42);
      final q = await evaluateAll(b, [
        ...clips('coach', 12),
        ...clips('short', 3, durationMs: 100),
      ]);
      final out = b.build(coachName: 'C', clips: q, newProfileId: 'p', now: now);
      final e = (out as BuildRejected).error;
      expect(validateAnalysisError(e.toJson()), isEmpty);
      expect(e.errorCode, 'INSUFFICIENT_CLIPS');
      expect(e.message, contains('3 more'));
      final gates = e.details['gates'] as Map;
      expect(gates['clips_usable'], 12);
      expect(gates['min_clips_met'], isFalse);
      expect(e.details['unusable'] as List, hasLength(3));
    });

    test('low critical-phase pose confidence → LOW_POSE_CONFIDENCE rejection',
        () async {
      // Clips pass the per-clip bar (0.6) but the profile bar is stricter.
      final strict = AnalysisPack.fromJson(
          {...packJson, 'min_critical_pose_confidence': 0.6});
      final b = coach(42, p: strict, conf: 0.62);
      final q = await evaluateAll(b, clips('coach', 15));
      expect(q.every((c) => c.usable), isTrue);
      final stricter = ProfileBuilder(
          engine: AnalysisEngine(
              pack: AnalysisPack.fromJson(
                  {...packJson, 'min_critical_pose_confidence': 0.65})));
      final out =
          stricter.build(coachName: 'C', clips: q, newProfileId: 'p', now: now);
      expect((out as BuildRejected).error.errorCode, 'LOW_POSE_CONFIDENCE');
    });

    test('self-consistency separates one coach from mixed footage', () async {
      // A pack tolerance (min_spread) makes the held-out score meaningful:
      // one coach's clips sit inside it, unrelated clips do not.
      final tolerant = AnalysisPack.fromJson({
        ...packJson,
        'self_consistency_threshold': 0.8,
        'metrics': [
          for (final m in packJson['metrics'] as List)
            {...m as Map<String, Object?>, 'min_spread': 1.0},
        ],
      });
      final one = coach(42, p: tolerant);
      final good = one.build(
          coachName: 'C',
          clips: await evaluateAll(one, clips('coach', 15)),
          newProfileId: 'p',
          now: now);
      expect(good, isA<BuildReady>());
      expect((good as BuildReady).consistency.meanScore, greaterThan(0.8));

      // Mixed footage: every clip a different style.
      final mixed = ProfileBuilder(engine: AnalysisEngine(pack: tolerant));
      final bad = mixed.build(
          coachName: 'C',
          clips: await evaluateAll(mixed, clips('random', 15)),
          newProfileId: 'p',
          now: now);
      final e = (bad as BuildRejected).error;
      expect(e.errorCode, 'PROFILE_NOT_READY');
      final gates = e.details['gates'] as Map;
      expect(gates['self_consistency_passed'], isFalse);
      expect(gates['self_consistency_score'], lessThan(0.8));
      expect(e.details['held_out_scores'] as Map, hasLength(15));
    });

    test('previous profile from another schema → SCHEMA_MISMATCH', () async {
      final b = coach(42);
      final q = await evaluateAll(b, clips('coach', 15));
      final v1 = (b.build(coachName: 'C', clips: q, newProfileId: 'p', now: now)
              as BuildReady)
          .profile;
      final newer = ProfileBuilder(
          engine: AnalysisEngine(
              pack: AnalysisPack.fromJson(
                  {...packJson, 'metric_schema_version': 'example-2'})));
      final out = newer.build(
          coachName: 'C', clips: q, newProfileId: 'p', now: now, previous: v1);
      expect((out as BuildRejected).error.errorCode, 'SCHEMA_MISMATCH');
    });
  });

  group('validateProfile', () {
    test('reports every problem', () {
      final problems = validateProfile({
        'profile_id': '',
        'version': 0,
        'coach_name': 'C',
        'pack_id': 'p',
        'event_id': 'e',
        'metric_schema_version': 'v',
        'created_at': 'yesterday',
        'source_clip_count': 15,
        'quality_gates': {'min_clips_met': true, 'notes': ''},
        'metrics': {
          'm': {'center': 1, 'spread': -1, 'weight': 1, 'unit': 'u', 'phase': 'p'},
        },
      });
      expect(
          problems,
          containsAll([
            'profile_id is empty',
            'version must be >= 1',
            'created_at is not ISO 8601',
            'quality_gates.self_consistency_passed is missing',
            'metrics.m.spread must be >= 0',
          ]));
    });
  });
}
