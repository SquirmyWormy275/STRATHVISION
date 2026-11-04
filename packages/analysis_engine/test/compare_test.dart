import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show packJson;

/// Phase 5 acceptance: deterministic scoring, top deltas = largest measured
/// differences, low confidence → warnings, applied patches in the result.
void main() {
  Profile profile({
    Map<String, ProfileMetric>? metrics,
    bool ready = true,
    String schema = 'example-1',
    List<ReferenceClip> refs = const [],
  }) =>
      Profile(
        profileId: 'prof-1',
        version: 2,
        coachName: 'Coach',
        packId: 'example_pack',
        eventId: 'example_event',
        metricSchemaVersion: schema,
        createdAt: DateTime.utc(2026, 11, 1),
        sourceClipCount: 15,
        minClipsMet: ready,
        selfConsistencyPassed: true,
        notes: '',
        metrics: metrics ??
            const {
              'a': ProfileMetric(center: 100, spread: 5, weight: 1, unit: 'deg', phase: 'p1'),
              'b': ProfileMetric(center: 50, spread: 2, weight: 1, unit: 'deg', phase: 'p2'),
              'c': ProfileMetric(center: 1.0, spread: 0.1, weight: 1, unit: 's', phase: 'p2'),
            },
        referenceClips: refs,
      );

  MetricVector vector(Map<String, double> values,
          {double conf = 0.9, double phaseConf = 0.9, double pose = 0.9}) =>
      MetricVector(
        clipId: 'clip-1',
        packId: 'example_pack',
        eventId: 'example_event',
        metricSchemaVersion: 'example-1',
        phases: {
          'p1': PhaseSpan(startFrame: 0, endFrame: 9, confidence: phaseConf),
          'p2': PhaseSpan(startFrame: 10, endFrame: 19, confidence: 0.9),
        },
        metrics: {
          for (final e in values.entries)
            e.key: MetricValue(
                value: e.value, confidence: conf, phase: e.key == 'a' ? 'p1' : 'p2'),
        },
        poseConfidenceSummary: pose,
        specialistResiduals: const {'slope_residual': 0.1},
      );

  ComparisonResult ok(ComparisonOutcome o) => (o as ComparisonSuccess).result;

  test('result validates against the Comparison Result schema', () {
    final r = compare(
        vector: vector({'a': 104, 'b': 50, 'c': 1.25}),
        profile: profile(),
        resultId: 'r1');
    final json = jsonDecode(jsonEncode(r.toJson()));
    expect(validateComparisonResult(json), isEmpty);
  });

  test('scoring is deterministic for the same inputs', () {
    final v = vector({'a': 104, 'b': 47, 'c': 1.25});
    final r1 = ok(compare(vector: v, profile: profile(), resultId: 'x')).toJson();
    final r2 = ok(compare(vector: v, profile: profile(), resultId: 'x')).toJson();
    expect(jsonEncode(r1), jsonEncode(r2));
  });

  test('top deltas are the largest measured differences', () {
    // a: 0.8 spreads, b: 3 spreads lower, c: 2.5 spreads higher.
    final r = ok(compare(
        vector: vector({'a': 104, 'b': 44, 'c': 1.25}),
        profile: profile(),
        resultId: 'r'));
    expect(r.rankedDeltas.map((d) => d.metricKey), ['b', 'c', 'a']);
    final b = r.rankedDeltas.first;
    expect(b.distanceSpreads, closeTo(3, 1e-9));
    expect(b.direction, 'lower');
    expect(b.userValue, 44);
    expect(b.coachCenter, 50);
    expect(b.coachSpread, 2);
    expect(b.phase, 'p2');
    expect(r.rankedDeltas[1].direction, 'higher');
    // Score and contributions add up to 1.
    final sum = r.rankedDeltas.fold(0.0, (a, d) => a + d.contribution);
    expect(r.overallScore + sum, closeTo(1, 1e-3));
  });

  test('weights scale contributions', () {
    final r = ok(compare(
        vector: vector({'a': 110, 'b': 54}), // both 2 spreads off
        profile: profile(metrics: const {
          'a': ProfileMetric(center: 100, spread: 5, weight: 3, unit: 'deg', phase: 'p1'),
          'b': ProfileMetric(center: 50, spread: 2, weight: 1, unit: 'deg', phase: 'p2'),
        }),
        resultId: 'r'));
    expect(r.rankedDeltas.first.metricKey, 'a');
    expect(r.rankedDeltas.first.contribution,
        closeTo(3 * r.rankedDeltas.last.contribution, 1e-3));
  });

  test('a perfect match scores 1 with neutral deltas and no warnings', () {
    final r = ok(compare(
        vector: vector({'a': 100, 'b': 50, 'c': 1.0}),
        profile: profile(),
        resultId: 'r'));
    expect(r.overallScore, 1);
    expect(r.rankedDeltas.every((d) => d.direction == 'neutral'), isTrue);
    expect(r.warnings, isEmpty);
  });

  test('low-confidence inputs produce warnings, not silent high scores', () {
    final r = ok(compare(
        vector: vector({'a': 100, 'b': 50, 'c': 1.0},
            conf: 0.3, phaseConf: 0.4, pose: 0.45),
        profile: profile(),
        resultId: 'r'));
    expect(r.overallScore, 1);
    expect(r.lowConfidencePhases, ['p1']);
    expect(r.warnings, hasLength(3));
    expect(r.warnings.join(' '), contains('Body tracking was weak'));
    expect(r.warnings.join(' '), contains('uncertain for p1'));
    expect(r.warnings.join(' '), contains('Low-confidence measurements: a, b, c'));
  });

  test('missing metrics are reported in coverage and warnings', () {
    final r = ok(compare(
        vector: vector({'a': 100}), profile: profile(), resultId: 'r'));
    expect(r.metricsUsed, 1);
    expect(r.metricsMissing, ['b', 'c']);
    expect(r.warnings.single, contains('Not measured in this clip: b, c'));
  });

  test('nearest reference clips are ordered by distance', () {
    final r = ok(compare(
        vector: vector({'a': 100, 'b': 50, 'c': 1.0}),
        profile: profile(refs: const [
          ReferenceClip(clipId: 'far', metrics: {'a': 120, 'b': 40, 'c': 1.5}),
          ReferenceClip(clipId: 'near', metrics: {'a': 101, 'b': 50, 'c': 1.0}),
          ReferenceClip(clipId: 'mid', metrics: {'a': 110, 'b': 52, 'c': 1.1}),
          ReferenceClip(clipId: 'mid2', metrics: {'a': 111, 'b': 52, 'c': 1.1}),
        ]),
        resultId: 'r'));
    expect(r.nearestReferenceClipIds, ['near', 'mid', 'mid2']);
  });

  group('errors', () {
    test('other schema → SCHEMA_MISMATCH', () {
      final o = compare(
          vector: vector({'a': 1}), profile: profile(schema: 'example-2'), resultId: 'r');
      expect((o as ComparisonFailure).error.errorCode, 'SCHEMA_MISMATCH');
      expect(validateAnalysisError(o.toJson()), isEmpty);
    });

    test('not-ready profile → PROFILE_NOT_READY', () {
      final o = compare(vector: vector({'a': 1}), profile: profile(ready: false), resultId: 'r');
      expect((o as ComparisonFailure).error.errorCode, 'PROFILE_NOT_READY');
    });

    test('no shared metrics → SCHEMA_MISMATCH', () {
      final o = compare(vector: vector({'z': 1}), profile: profile(), resultId: 'r');
      expect((o as ComparisonFailure).error.errorCode, 'SCHEMA_MISMATCH');
    });
  });

  group('specialist patches', () {
    final heads = defaultHeads();
    String patch(int version, List<Map<String, Object?>> edits,
            {String base = 'slope_residual/stub/v0', String head = 'slope_residual'}) =>
        jsonEncode({'head': head, 'version': version, 'base': base, 'edits': edits});

    test('valid patch is applied and changes the residual', () async {
      final set = loadPatches({
        'slope_residual_v1.patch': patch(1, [
          {'tensor': 'b2', 'index': [], 'delta': 0.5},
        ]),
        'slope_residual_v3.patch': patch(3, [
          {'tensor': 'b2', 'index': [], 'delta': 1.0},
          {'tensor': 'w1', 'index': [4, 17], 'delta': 0.01},
        ]),
      }, heads);
      expect(set.rejected, isEmpty);
      expect(set.appliedNames, ['slope_residual_v3']);

      final pack = AnalysisPack.fromJson(packJson);
      const clip = ClipSource(clipId: 'c', path: '/c', durationMs: 6000, fps: 30);
      final base = (await AnalysisEngine(pack: pack).analyze(clip)) as AnalysisSuccess;
      final patched = (await AnalysisEngine(
              pack: pack, heads: applyPatches(heads, set.applied))
          .analyze(clip)) as AnalysisSuccess;
      final d = patched.vector.specialistResiduals['slope_residual']! -
          base.vector.specialistResiduals['slope_residual']!;
      expect(d, greaterThan(0.9)); // b2 + 1.0 (plus a tiny w1 effect)
      // Metrics are untouched by head patches.
      expect(jsonEncode(patched.vector.metrics), jsonEncode(base.vector.metrics));
    });

    test('applied patches appear in the result', () {
      final r = ok(compare(
          vector: vector({'a': 100}),
          profile: profile(),
          resultId: 'r',
          appliedPatches: const ['slope_residual_v3']));
      expect(r.appliedPatches, ['slope_residual_v3']);
      expect(r.toJson()['applied_patches'], ['slope_residual_v3']);
    });

    test('bad patches are rejected with PATCH_REJECTED and every problem', () {
      final set = loadPatches({
        'slope_residual_v2.patch': patch(2, [
          {'tensor': 'w1', 'index': [40, 1], 'delta': 0.1},
          {'tensor': 'w9', 'index': [0], 'delta': 0.1},
        ], base: 'other/base'),
        'mystery_v1.patch': patch(1, [{'tensor': 'b2', 'index': [], 'delta': 1}], head: 'mystery'),
        'wrong_name.patch': patch(1, [{'tensor': 'b2', 'index': [], 'delta': 1}]),
        'broken_v1.patch': '{nope',
        'slope_residual_v4.patch': patch(4, [
          for (var i = 0; i < 43; i++) {'tensor': 'w1', 'index': [i % 32, i ~/ 32], 'delta': 0.001},
        ]),
      }, heads);
      expect(set.applied, isEmpty);
      expect(set.rejected, hasLength(5));
      for (final e in set.rejected) {
        expect(e.errorCode, 'PATCH_REJECTED');
        expect(validateAnalysisError(e.toJson()), isEmpty);
      }
      String problems(String file) => (set.rejected
              .firstWhere((e) => e.details['file'] == file)
              .details['problems'] as List)
          .join('; ');
      expect(problems('slope_residual_v2.patch'), allOf(contains('base'),
          contains('out of range'), contains('tensor must be')));
      expect(problems('mystery_v1.patch'), contains('unknown head'));
      expect(problems('wrong_name.patch'), contains('file name must be'));
      expect(problems('broken_v1.patch'), contains('not valid JSON'));
      expect(problems('slope_residual_v4.patch'), contains('under 2%'));
    });

    test('a rejected higher version falls back to the best valid one', () {
      final set = loadPatches({
        'slope_residual_v1.patch': patch(1, [{'tensor': 'b2', 'index': [], 'delta': 0.5}]),
        'slope_residual_v2.patch': patch(2, [
          {'tensor': 'b2', 'index': [], 'delta': 0.1},
          {'tensor': 'b2', 'index': [], 'delta': 1}, // duplicate edit
        ]),
      }, heads);
      expect(set.appliedNames, ['slope_residual_v1']);
      expect(set.rejected.single.details['file'], 'slope_residual_v2.patch');
    });
  });

  test('metric definitions are generic and readable', () {
    final pack = AnalysisPack.fromJson(packJson);
    final text = describeMetric(pack.metrics.first, phaseLabel: (p) => 'Phase 1');
    expect(text,
        'Average angle at the left elbow (left shoulder · left elbow · left wrist) during Phase 1.');
    expect(describeMetric(pack.metrics.last), 'How long phase_3 lasts.');
  });
}
