import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

/// Phase 7 acceptance (harness): a failing slope bias is patched on the
/// workbench, the patch improves the probe without regressing the others,
/// and the accept/reject rules are exactly DECISIONS.md's.
void main() {
  final timber = PackDefinition.parse(
      File('../../apps/strathvision/assets/packs/timber.json').readAsStringSync());
  final pack = timber.event('underhand')!.analysis;

  late Profile coach;
  setUpAll(() async {
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    coach = (b.build(coachName: 'C', clips: q, newProfileId: 'p', now: DateTime.utc(2026))
            as BuildReady)
        .profile;
  });

  /// The coach's own 15 reference clips, analyzed against a reference that
  /// is off by [refShift] degrees on the head target: a systematic slope
  /// bias of exactly −refShift.
  Future<List<HarnessClip>> probeClips({double refShift = 0, int n = 15}) async {
    final reference = {for (final e in coach.metrics.entries) e.key: e.value.center};
    reference['entry_slope'] = reference['entry_slope']! + refShift;
    final e = AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42));
    return [
      for (var i = 0; i < n; i++)
        HarnessClip.fromDetail(
            await e.analyzeDetailed(
                ClipSource(clipId: 'ref-$i', path: '/p', durationMs: 6000, fps: 30),
                reference: reference),
            'slope_residual',
            mark: i.isEven ? 'green' : null),
    ];
  }

  test('pack declares the DECISIONS.md acceptance rules', () {
    final a = pack.heads.single.acceptance!;
    expect(a.primaryProbe, 'slope_bias');
    expect(a.minImprovement, 0.8);
    expect(a.noRegress, ['slope_error_deg']);
    expect(a.withinFraction, {'phase_stability': 0.05, 'track_confidence_correlation': 0.05});
    expect(a.maxWeightFraction, 0.02);
  });

  test('a failing slope bias is patched; probe improves, nothing regresses',
      () async {
    final h = SpecialistHarness(
        pack: pack, headName: 'slope_residual', clips: await probeClips(refShift: 3));
    final run = h.search();
    expect(run.before['slope_bias']!, closeTo(-3, 0.01));
    expect(run.decision.accepted, isTrue, reason: run.decision.reasons.join('\n'));
    expect(run.after['slope_bias']!.abs(),
        lessThanOrEqualTo(run.before['slope_bias']!.abs() - 0.8));
    expect(run.after['slope_error_deg']!, lessThanOrEqualTo(run.before['slope_error_deg']!));
    expect(run.after['phase_stability']!,
        closeTo(run.before['phase_stability']!, 0.05 * run.before['phase_stability']!));
    final patch = run.patch!;
    expect(patch.name, 'slope_residual_v1');
    expect(patch.base, 'slope_residual/timber-underhand/v1');
    expect(patch.edits.length, lessThan(0.02 * 2113));

    // The written patch passes the phone-side loader and reproduces the
    // improvement through the normal analysis path.
    final text = jsonEncode(patch.toJson());
    final loaded = loadPatches({patch.fileName: text}, headsFor(pack));
    expect(loaded.rejected, isEmpty);
    final patchedHeads = applyPatches(headsFor(pack), loaded.applied);
    final reference = {for (final e in coach.metrics.entries) e.key: e.value.center};
    reference['entry_slope'] = reference['entry_slope']! + 3;
    final e = AnalysisEngine(
        pack: pack, pose: const StubPoseEstimator(styleSeed: 42), heads: patchedHeads);
    final samples = <ProbeSample>[];
    for (var i = 0; i < 15; i++) {
      final d = await e.analyzeDetailed(
          ClipSource(clipId: 'ref-$i', path: '/p', durationMs: 6000, fps: 30),
          reference: reference);
      samples.add(ProbeSample(
          residual: (d.outcome as AnalysisSuccess).vector.specialistResiduals['slope_residual']!,
          trackConfidence: d.implementConfidence));
    }
    expect(runProbes(pack, 'slope_residual', samples)['slope_bias'],
        closeTo(run.after['slope_bias']!, 1e-3));
  });

  test('a small bias cannot reach the 0.8° bar → rejected with the reason',
      () async {
    final h = SpecialistHarness(
        pack: pack, headName: 'slope_residual', clips: await probeClips(refShift: 0.5));
    final run = h.search();
    expect(run.decision.accepted, isFalse);
    expect(run.decision.reasons.first, contains('slope_bias must improve by at least 0.8'));
  });

  group('judge applies each rule', () {
    late SpecialistHarness h;
    setUpAll(() async => h = SpecialistHarness(
        pack: pack, headName: 'slope_residual', clips: await probeClips(refShift: 3)));
    final before = {
      'slope_error_deg': 3.0,
      'slope_bias': -3.0,
      'priority_agreement': 0.5,
      'phase_stability': 1.0,
      'track_confidence_correlation': 0.2,
    };
    Map<String, double?> after(Map<String, double?> changes) => {...before, ...changes};

    test('passes when all rules hold', () {
      final d = h.judge(before, after({'slope_bias': -2.0, 'slope_error_deg': 2.5}), 5);
      expect(d.accepted, isTrue);
    });
    test('bias must improve by ≥ 0.8', () {
      final d = h.judge(before, after({'slope_bias': -2.5}), 5);
      expect(d.accepted, isFalse);
      expect(d.reasons.first, contains('slope_bias'));
    });
    test('error must not regress', () {
      final d = h.judge(before, after({'slope_bias': 0.0, 'slope_error_deg': 3.1}), 5);
      expect(d.reasons.first, contains('slope_error_deg got worse'));
    });
    test('phase_stability and correlation within 5%', () {
      final d1 = h.judge(before, after({'slope_bias': 0.0, 'phase_stability': 1.06}), 5);
      expect(d1.reasons.first, contains('phase_stability moved more than 5%'));
      final d2 = h.judge(before,
          after({'slope_bias': 0.0, 'track_confidence_correlation': 0.25}), 5);
      expect(d2.reasons.first, contains('track_confidence_correlation'));
      final ok = h.judge(before, after({'slope_bias': 0.0, 'phase_stability': 1.04}), 5);
      expect(ok.accepted, isTrue);
    });
    test('edits must touch under 2% of weights (42 of 2,113 is 1.99%)', () {
      final d = h.judge(before, after({'slope_bias': 0.0}), 43);
      expect(d.accepted, isFalse);
      expect(d.reasons.first, contains('Touches 43 weights'));
      expect(h.judge(before, after({'slope_bias': 0.0}), 42).accepted, isTrue);
    });
  });

  test('a second run builds on the first patch (cumulative, next version)',
      () async {
    final clips = await probeClips(refShift: 6);
    final first = SpecialistHarness(pack: pack, headName: 'slope_residual', clips: clips)
        .search(rounds: 1);
    expect(first.patch, isNotNull);
    final second = SpecialistHarness(
            pack: pack, headName: 'slope_residual', clips: clips, current: first.patch)
        .search();
    if (second.patch != null) {
      expect(second.patch!.version, 2);
      expect(second.patch!.edits.length, greaterThanOrEqualTo(first.patch!.edits.length));
    }
    expect(second.before['slope_bias'], closeTo(first.after['slope_bias']!, 1e-9));
  });

  test('heads without acceptance rules cannot be patched', () {
    final p = AnalysisPack.fromJson({
      'pack_id': 'p',
      'event_id': 'e',
      'metric_schema_version': 'v',
      'phases': ['a'],
      'metrics': [
        {'key': 'm', 'kind': 'phase_duration', 'phase': 'a', 'unit': 's'},
      ],
      'heads': [
        {'name': 'h', 'kind': 'mlp_residual', 'base': 'b', 'target_metric': 'm'},
      ],
    });
    expect(() => SpecialistHarness(pack: p, headName: 'h', clips: const []),
        throwsA(isA<AnalysisError>().having((e) => e.errorCode, 'code', 'PATCH_REJECTED')));
  });
}
