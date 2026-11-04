import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

/// Hand-set weights that satisfy the timber specs: proves the specs are
/// satisfiable and stands in for the LLM in tests.
class ScriptedCompiler implements AdapterCompiler {
  ScriptedCompiler({this.failFirst = false});
  final bool failFirst;
  final List<List<String>> feedbackSeen = [];
  int calls = 0;

  @override
  String get id => 'scripted-test';

  @override
  Future<Map<String, AdapterOutput>> propose(
      AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      {List<String> feedback = const []}) async {
    calls++;
    feedbackSeen.add(feedback);
    if (spec.name == 'usable_footage') {
      if (failFirst && calls == 1) {
        return {'usable': const AdapterOutput(bias: 5, weights: {})}; // always yes
      }
      return {
        'usable': const AdapterOutput(bias: -20, weights: {
          'pose_confidence': 10,
          'implement_confidence': 10,
          'phase_confidence.downswing': 6,
          'phase_confidence.entry': 6,
        }),
      };
    }
    final groups = {
      'Slope': ['entry_slope', 'downswing_slope'],
      'Hinge': ['hinge_at_entry'],
      'Spacing': [
        for (final k in ['lead_knee_at_entry', 'trail_knee_at_entry', 'lead_elbow_at_entry'])
          if (pack.metrics.any((m) => m.key == k)) k,
      ],
      'Path': ['trail_elbow_downswing', 'shoulder_lift_backswing'],
    };
    return {
      for (final e in groups.entries)
        e.key: AdapterOutput(
            bias: 0, weights: {for (final k in e.value) 'abs_delta.$k': 0.5 / e.value.length}),
    };
  }
}

void main() {
  final timber = PackDefinition.parse(
      File('../../apps/strathvision/assets/packs/timber.json').readAsStringSync());
  final now = DateTime.utc(2026, 11, 4);

  test('timber events declare usable_footage and priority_scorer specs', () {
    for (final e in timber.events) {
      final names = e.analysis.adapters.map((a) => a.name);
      expect(names, ['usable_footage', 'priority_scorer']);
      final usable = e.analysis.adapters.first;
      expect(usable.threshold, 0.5);
      expect(usable.examples, hasLength(5));
    }
  });

  for (final event in ['underhand', 'standing_block']) {
    test('$event: compiled adapters satisfy their examples and run locally',
        () async {
      final pack = timber.event(event)!.analysis;
      for (final spec in pack.adapters) {
        final a = await compileAdapter(spec, pack, ScriptedCompiler(), now: now);
        expect(checkExamples(spec, a), isEmpty);
        // Round-trip through the .paw file and run with no compiler at all.
        final loaded = CompiledAdapter.parse(a.fileName, jsonEncode(a.toJson()));
        expect(checkExamples(spec, loaded), isEmpty);
        expect(loaded.specHash, spec.specHash);
        expect(loaded.compiledBy, 'scripted-test');
      }
    });
  }

  test('compile feeds example mismatches back and retries', () async {
    final pack = timber.event('underhand')!.analysis;
    final c = ScriptedCompiler(failFirst: true);
    final a = await compileAdapter(pack.adapters.first, pack, c, now: now);
    expect(c.calls, 2);
    expect(c.feedbackSeen[1], isNotEmpty);
    expect(c.feedbackSeen[1].first, contains('expected usable=false'));
    expect(a.decide({'pose_confidence': 0.2})['usable'], isFalse);
  });

  test('a compiler that never satisfies the examples → ADAPTER_COMPILE_FAILED',
      () async {
    final pack = timber.event('underhand')!.analysis;
    final bad = _Constant();
    expect(
        () => compileAdapter(pack.adapters.first, pack, bad, now: now),
        throwsA(isA<AnalysisError>()
            .having((e) => e.errorCode, 'code', 'ADAPTER_COMPILE_FAILED')
            .having((e) => e.details['problems'], 'problems', isNotEmpty)));
  });

  test('unknown inputs and wrong outputs are rejected', () async {
    final pack = timber.event('underhand')!.analysis;
    try {
      await compileAdapter(pack.adapters.first, pack, _Wrong(), now: now, attempts: 1);
      fail('expected failure');
    } on AnalysisError catch (e) {
      final p = (e.details['problems'] as List).join('; ');
      expect(p, contains('outputs must be exactly usable'));
      expect(p, contains('unknown input "made_up"'));
    }
  });

  group('loading from a package', () {
    late Map<String, String> files;
    late AnalysisPack pack;
    setUp(() async {
      pack = timber.event('underhand')!.analysis;
      files = {
        for (final s in pack.adapters)
          '${s.name}.paw': jsonEncode(
              (await compileAdapter(s, pack, ScriptedCompiler(), now: now)).toJson()),
      };
    });

    test('loads both adapters for the matching event', () {
      final set = loadAdapters(files, pack, pack.adapters);
      expect(set.adapters.keys, unorderedEquals(['usable_footage', 'priority_scorer']));
      expect(set.rejected, isEmpty);
    });

    test('stale, foreign, and broken adapters are skipped with reasons', () {
      final other = timber.event('standing_block')!.analysis;
      final set = loadAdapters({...files, 'junk.paw': '{oops'}, other, other.adapters);
      expect(set.adapters, isEmpty);
      expect(set.rejected.where((r) => r.contains('another event')), hasLength(2));
      expect(set.rejected.where((r) => r.contains('could not be read')), hasLength(1));

      final changed = AdapterSpec(
          name: 'usable_footage',
          spec: '${pack.adapters.first.spec} Changed.',
          outputs: const ['usable'],
          threshold: 0.5,
          examples: const []);
      final stale = loadAdapters(files, pack, [changed, pack.adapters[1]]);
      expect(stale.rejected.single, contains('out of date'));
      expect(stale.adapters.keys, ['priority_scorer']);
    });
  });

  test('adapter inputs come from analysis and comparison', () async {
    final pack = timber.event('underhand')!.analysis;
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'r$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    final profile = (b.build(coachName: 'C', clips: q, newProfileId: 'p', now: now)
            as BuildReady)
        .profile;
    final d = await AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 2))
        .analyzeDetailed(const ClipSource(clipId: 'a', path: '/a', durationMs: 6000, fps: 30));
    final v = (d.outcome as AnalysisSuccess).vector;
    final r = (compare(vector: v, profile: profile, resultId: 'x') as ComparisonSuccess).result;
    final x = adapterInputs(v, implementConfidence: d.implementConfidence, comparison: r);
    final names = adapterInputNames(pack, withComparison: true);
    expect(x.keys.toSet().difference(names.toSet()), isEmpty);
    expect(x['abs_delta.entry_slope'], greaterThan(1));
    final scorer = await compileAdapter(pack.adapters[1], pack, ScriptedCompiler(), now: now);
    expect(scorer.outputs.keys, contains(scorer.top(x)));
  });
}

class _Constant implements AdapterCompiler {
  int calls = 0;
  @override
  String get id => 'constant';
  @override
  Future<Map<String, AdapterOutput>> propose(AdapterSpec spec, AnalysisPack pack,
      List<String> inputNames, {List<String> feedback = const []}) async {
    calls++;
    return {'usable': const AdapterOutput(bias: 3, weights: {})};
  }
}

class _Wrong implements AdapterCompiler {
  @override
  String get id => 'wrong';
  @override
  Future<Map<String, AdapterOutput>> propose(AdapterSpec spec, AnalysisPack pack,
          List<String> inputNames, {List<String> feedback = const []}) async =>
      {'yes': const AdapterOutput(bias: 0, weights: {'made_up': 1})};
}
