import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

/// Phase 6 acceptance: the engine has no timber strings or logic, packs swap
/// without engine changes, comparison works with timber metrics, and
/// slope_residual produces a residual the probes can measure.
void main() {
  const packsDir = '../../apps/strathvision/assets/packs';
  PackDefinition load(String name) =>
      PackDefinition.parse(File('$packsDir/$name.json').readAsStringSync());

  final timber = load('timber');
  final underhand = timber.event('underhand')!.analysis;

  test('engine code contains zero timber-specific strings', () {
    final words = RegExp(
        r'timber|underhand|standing.?block|\baxe|chop|\bsaw\b|crosscut|\blogs?\b|wood|slope|stroke',
        caseSensitive: false);
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (words.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('timber pack defines both initial events with phases and metrics', () {
    expect(timber.packId, 'timber');
    expect(timber.events.map((e) => e.eventId), ['underhand', 'standing_block']);
    for (final e in timber.events) {
      final a = e.analysis;
      expect(a.phases, ['setup', 'backswing', 'downswing', 'entry', 'recovery']);
      expect(a.criticalPhases, ['downswing', 'entry']);
      expect(a.metrics.length, greaterThanOrEqualTo(8));
      for (final m in a.metrics) {
        expect(timber.metricLabels, contains(m.key));
      }
      expect(a.heads.single.name, 'slope_residual');
      expect(a.heads.single.targetMetric, 'entry_slope');
      expect(a.probes.map((p) => p.name), [
        'slope_error_deg',
        'slope_bias',
        'priority_agreement',
        'phase_stability',
        'track_confidence_correlation',
      ]);
    }
    expect(timber.topAttributes, contains('Slope'));
  });

  test('packs swap without changing the engine', () async {
    const clip = ClipSource(clipId: 'c', path: '/c', durationMs: 8000, fps: 30);
    for (final def in [load('placeholder'), timber]) {
      for (final e in def.events) {
        final out = await AnalysisEngine(pack: e.analysis).analyze(clip);
        final json = jsonDecode(jsonEncode(out.toJson()));
        expect(
            validateMetricVector(json,
                requiredResiduals: [for (final h in e.analysis.heads) h.name]),
            isEmpty,
            reason: '${def.packId}/${e.eventId}');
        expect(json['pack_id'], def.packId);
        expect((json['metrics'] as Map).keys.toSet(),
            {for (final m in e.analysis.metrics) m.key});
      }
    }
  });

  test('invalid pack files are rejected with every problem', () {
    expect(
      () => PackDefinition.fromJson({
        'format_version': 2,
        'pack_id': 'p',
        'name': 'P',
        'attributes': {'top': [], 'more': []},
        'events': [
          {
            'event_id': 'e',
            'label': 'E',
            'metric_schema_version': 'v',
            'phases': ['a'],
            'metrics': [
              {'key': 'm', 'kind': 'phase_duration', 'phase': 'a', 'unit': 's',
               'aggregate': 'end'},
            ],
            'heads': [
              {'name': 'h', 'kind': 'mlp_residual', 'base': 'b', 'target_metric': 'zz'},
            ],
          },
        ],
      }),
      throwsA(isA<AnalysisError>()
          .having((e) => e.errorCode, 'code', 'SCHEMA_MISMATCH')
          .having((e) => (e.details['problems'] as List).join('; '), 'problems',
              allOf(contains('format_version'), contains('aggregate'),
                  contains('target_metric')))),
    );
  });

  group('comparison and residual with timber metrics', () {
    Future<List<MetricVector>> clipsOf(int styleSeed, String prefix, int n) async {
      final e = AnalysisEngine(
          pack: underhand, pose: StubPoseEstimator(styleSeed: styleSeed));
      return [
        for (var i = 0; i < n; i++)
          ((await e.analyze(ClipSource(
                  clipId: '$prefix-$i', path: '/$prefix$i', durationMs: 6000, fps: 30)))
              as AnalysisSuccess)
              .vector,
      ];
    }

    late Profile coach;
    setUpAll(() async {
      final b = ProfileBuilder(
          engine: AnalysisEngine(
              pack: underhand, pose: const StubPoseEstimator(styleSeed: 42)));
      final q = await Future.wait([
        for (var i = 0; i < 15; i++)
          b.evaluate(
              ClipSource(clipId: 'ref-$i', path: '/r$i', durationMs: 6000, fps: 30),
              displayName: 'ref-$i'),
      ]);
      coach = (b.build(
              coachName: 'Coach',
              clips: q,
              newProfileId: 'p',
              now: DateTime.utc(2026)) as BuildReady)
          .profile;
    });

    test('comparison ranks timber metrics', () async {
      final athlete = (await clipsOf(2, 'ath', 1)).single;
      final r = (compare(vector: athlete, profile: coach, resultId: 'r')
              as ComparisonSuccess)
          .result;
      expect(validateComparisonResult(r.toJson()), isEmpty);
      expect(r.metricsUsed, underhand.metrics.length);
      expect(r.rankedDeltas.map((d) => d.metricKey).toSet(),
          {for (final m in underhand.metrics) m.key});
      expect(r.overallScore, lessThan(0.9));
    });

    Future<List<ProbeSample>> samples(int styleSeed, String prefix,
        {List<SpecialistPatch> patches = const [], List<String?>? marks}) async {
      final reference = {for (final e in coach.metrics.entries) e.key: e.value.center};
      final e = AnalysisEngine(
          pack: underhand,
          pose: StubPoseEstimator(styleSeed: styleSeed),
          heads: applyPatches(headsFor(underhand), patches));
      final out = <ProbeSample>[];
      for (var i = 0; i < 10; i++) {
        final d = await e.analyzeDetailed(
            ClipSource(clipId: '$prefix-$i', path: '/x', durationMs: 6000, fps: 30),
            reference: reference);
        final v = (d.outcome as AnalysisSuccess).vector;
        out.add(ProbeSample(
            residual: v.specialistResiduals['slope_residual']!,
            trackConfidence: d.implementConfidence,
            mark: marks?[i]));
      }
      return out;
    }

    test('slope_residual is the entry-slope error against the coach', () async {
      final v = (await clipsOf(7, 'ath', 1)).single;
      final d = await AnalysisEngine(
              pack: underhand, pose: const StubPoseEstimator(styleSeed: 7))
          .analyze(const ClipSource(clipId: 'ath-0', path: '/a', durationMs: 6000, fps: 30),
              reference: {'entry_slope': coach.metrics['entry_slope']!.center});
      final r = (d as AnalysisSuccess).vector.specialistResiduals['slope_residual']!;
      expect(r, closeTo(v.metrics['entry_slope']!.value - coach.metrics['entry_slope']!.center, 1e-3));
    });

    test('the five probes measure the residual', () async {
      final own = await samples(42, 'coach');
      // Style 2's entry slope sits well away from the coach's (stub geometry).
      final other = await samples(2, 'ath',
          marks: ['red', 'red', 'green', null, 'red', null, 'green', 'red', null, null]);
      final pOwn = runProbes(underhand, 'slope_residual', own);
      final pOther = runProbes(underhand, 'slope_residual', other);
      expect(pOwn.keys, [
        'slope_error_deg',
        'slope_bias',
        'priority_agreement',
        'phase_stability',
        'track_confidence_correlation',
      ]);
      // Coach's own clips sit near the reference; another style does not.
      expect(pOwn['slope_error_deg']!, lessThan(pOther['slope_error_deg']!));
      expect(pOther['slope_bias']!.abs(), greaterThan(pOwn['slope_bias']!.abs()));
      expect(pOwn['priority_agreement'], isNull); // no marks
      expect(pOther['priority_agreement'], inInclusiveRange(0, 1));
      expect(pOwn['phase_stability'], greaterThanOrEqualTo(0));
      // Stub tracker confidence is constant: correlation is undefined.
      expect(pOther['track_confidence_correlation'], isNull);
    });

    test('a patch moves slope_bias by its delta and nothing else', () async {
      final patch = parsePatch(
          'slope_residual_v1.patch',
          jsonEncode({
            'head': 'slope_residual',
            'version': 1,
            'base': 'slope_residual/timber-underhand/v1',
            'edits': [
              {'tensor': 'b2', 'index': [], 'delta': -0.8},
            ],
          }),
          {for (final h in headsFor(underhand)) h.name: h});
      final before = runProbes(underhand, 'slope_residual', await samples(7, 'ath'));
      final after = runProbes(
          underhand, 'slope_residual', await samples(7, 'ath', patches: [patch]));
      expect(after['slope_bias']! - before['slope_bias']!, closeTo(-0.8, 1e-3));
      expect(after['phase_stability'], closeTo(before['phase_stability']!, 1e-6));
    });
  });

  test('probe kinds on known samples', () {
    const pack = AnalysisPack(
      packId: 'p',
      eventId: 'e',
      metricSchemaVersion: 'v',
      phases: ['a'],
      metrics: [],
      heads: [HeadDef(name: 'h', base: 'b', targetMetric: 'm')],
      probes: [
        ProbeDef(name: 'abs', head: 'h', kind: ProbeKind.meanAbsResidual),
        ProbeDef(name: 'bias', head: 'h', kind: ProbeKind.signedMeanResidual),
        ProbeDef(name: 'agree', head: 'h', kind: ProbeKind.markAgreement,
            attribute: 'A', tolerance: 2),
        ProbeDef(name: 'var', head: 'h', kind: ProbeKind.residualVariance),
        ProbeDef(name: 'corr', head: 'h', kind: ProbeKind.confidenceCorrelation),
      ],
    );
    final p = runProbes(pack, 'h', const [
      ProbeSample(residual: 1, trackConfidence: 0.9, mark: 'green'), // agrees
      ProbeSample(residual: -3, trackConfidence: 0.6, mark: 'red'), // agrees
      ProbeSample(residual: 3, trackConfidence: 0.5, mark: 'green'), // disagrees
      ProbeSample(residual: -1, trackConfidence: 0.8),
    ]);
    expect(p['abs'], 2);
    expect(p['bias'], 0);
    expect(p['agree'], closeTo(2 / 3, 1e-9));
    expect(p['var'], 5);
    expect(p['corr']!, lessThan(-0.9)); // bigger residuals, weaker tracking
  });
}
