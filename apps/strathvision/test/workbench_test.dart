import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/screens/library_screen.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/workbench_screen.dart';
import 'package:strathvision/workbench/claude_compiler.dart';
import 'package:strathvision/workbench/workbench_controller.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

import 'support/fake_stage_player.dart';

class _Store implements ProjectStore {
  @override
  Future<void> saveProject(Project p) async {}
}

/// Hand-set weights satisfying the timber specs (stands in for Claude).
class _Scripted implements AdapterCompiler {
  int calls = 0;
  @override
  String get id => 'scripted-test';
  @override
  Future<Map<String, AdapterOutput>> propose(
      AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      {List<String> feedback = const []}) async {
    calls++;
    if (spec.name == 'usable_footage') {
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
      'Spacing': ['lead_knee_at_entry', 'trail_knee_at_entry'],
      'Path': ['trail_elbow_downswing', 'shoulder_lift_backswing'],
    };
    return {
      for (final e in groups.entries)
        e.key: AdapterOutput(
            bias: 0, weights: {for (final k in e.value) 'abs_delta.$k': 0.5 / e.value.length}),
    };
  }
}

/// Phase 7 acceptance in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AnalysisPack pack;
  late Profile coach;

  setUpAll(() async {
    final packs = await loadPacks(rootBundle);
    pack = activePack(packs, 'timber/underhand').analysisPack;
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    final fitted =
        (b.build(coachName: 'Coach', clips: q, newProfileId: 'prof-1', now: DateTime.utc(2026))
                as BuildReady)
            .profile;
    // A reference 3° off on entry slope: the coach's own clips show a
    // systematic slope bias the head should learn to remove.
    final m = fitted.metrics['entry_slope']!;
    coach = Profile.fromJson({
      ...fitted.toJson(),
      'metrics': {
        ...fitted.toJson()['metrics'] as Map,
        'entry_slope': ProfileMetric(
                center: m.center + 3, spread: m.spread, weight: m.weight,
                unit: m.unit, phase: m.phase)
            .toJson(),
      },
    });
  });

  ({Profile profile, Map<String, String> patches, Map<String, String> adapters})? written;
  WorkbenchController controller({AdapterCompiler? compiler, VersionWriter? write}) => WorkbenchController(
        pack: pack,
        bundle: ProfileBundle(profile: coach, patchFiles: const {}),
        probe: (path) async => const ClipInfo(durationMs: 6000, fps: 30),
        // Coach clips: same style as the reference clips.
        analyze: (clip, reference, patches) => AnalysisEngine(
                pack: pack,
                pose: const StubPoseEstimator(styleSeed: 42),
                heads: applyPatches(headsFor(pack), patches))
            .analyzeDetailed(clip, reference: reference),
        compiler: compiler,
        write: write ?? (profile, patches, adapters) async {
          written = (profile: profile, patches: patches, adapters: adapters);
          return '/store/${profile.profileId}_v${profile.version}.zip';
        },
        clock: () => DateTime.utc(2026, 11, 4),
        // Deterministic ids: the stub pose is seeded by clip id.
        clipId: (path) => 'ref-${path.replaceAll(RegExp(r'[^0-9]'), '')}',
      );

  Future<void> pump(WidgetTester tester, WorkbenchController c, List<String> clips) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchScreen(controller: c, title: 'Coach · v1', pickClips: () async => clips),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('failing slope bias is patched on the workbench, saved as v2',
      (tester) async {
    written = null;
    final compiler = _Scripted();
    final c = controller(compiler: compiler);
    await pump(tester, c, [for (var i = 0; i < 15; i++) '/coach/swing_$i.mp4']);

    await tap(tester, 'add-probe-clips');
    expect(find.text('15 clips'), findsOneWidget);
    expect(find.byKey(const Key('probe-table')), findsOneWidget);
    final before = c.baseline!;
    expect(before['slope_bias']!.abs(), greaterThan(1.5)); // failing

    await tap(tester, 'run-harness');
    expect(find.byKey(const Key('patch-accepted')), findsOneWidget,
        reason: c.run!.decision.reasons.join('\n'));
    final run = c.run!;
    expect(run.after['slope_bias']!.abs(), lessThanOrEqualTo(before['slope_bias']!.abs() - 0.8));
    expect(run.after['slope_error_deg']!, lessThanOrEqualTo(before['slope_error_deg']!));
    expect(run.after['phase_stability']!,
        closeTo(before['phase_stability']!, 0.05 * before['phase_stability']!));

    // Compile both adapters (once, here), then save the next version.
    expect(find.text('Not compiled'), findsNWidgets(2));
    await tap(tester, 'compile-usable_footage');
    await tap(tester, 'compile-priority_scorer');
    expect(find.text('Compiled · save to add it'), findsNWidgets(2));
    expect(compiler.calls, 2);

    await tap(tester, 'save-version');
    expect(find.byKey(const Key('workbench-saved')), findsOneWidget);
    final w = written!;
    expect(w.profile.version, 2);
    expect(w.profile.profileId, 'prof-1');
    expect(w.patches.keys, ['slope_residual_v1.patch']);
    expect(w.adapters.keys, unorderedEquals(['usable_footage.paw', 'priority_scorer.paw']));
    expect(validateProfile(w.profile.toJson()), isEmpty);
    c.dispose();
  });

  testWidgets('no API key: compile is unavailable and says why', (tester) async {
    final c = controller();
    await pump(tester, c, const []);
    expect(find.textContaining('ANTHROPIC_API_KEY'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('compile-usable_footage'))).onPressed,
        isNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('save-version'))).onPressed, isNull);
    c.dispose();
  });

  testWidgets('occupied-version failure is visible and retains pending work', (tester) async {
    final c = controller(compiler: _Scripted(), write: (_, _, _) async {
      throw StateError('Version 2 already exists. Open the latest version.');
    });
    await pump(tester, c, const []);
    await tap(tester, 'compile-usable_footage');
    await tap(tester, 'save-version');
    expect(find.byKey(const Key('workbench-save-error')), findsOneWidget);
    expect(find.textContaining('Open the latest version'), findsOneWidget);
    expect(c.savedPath, isNull);
    expect(c.hasChanges, isTrue);
    expect(c.saving, isFalse);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  test('package with patch + adapters imports cleanly and runs on the phone path '
      '(adapters local, no compiler)', () async {
    final c = controller(compiler: _Scripted());
    await c.addProbeClips([for (var i = 0; i < 15; i++) '/coach/s$i.mp4']);
    c.runHarness();
    expect(c.run!.decision.accepted, isTrue);
    for (final s in pack.adapters) {
      await c.compile(s);
    }
    await c.save();
    final w = written!;

    // Write and re-read through the importer, as a phone would.
    final dir = Directory.systemTemp.createTempSync('sv_wb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = await storeProfilePackage(w.profile, dir,
        patches: w.patches, adapters: w.adapters);
    final meta = await readProfilePackage(path);
    expect(meta.version, 2);
    final bundle = await readProfileBundle(path);
    expect(bundle.patchFiles.keys, ['slope_residual_v1.patch']);
    expect(bundle.adapterFiles, hasLength(2));

    // Phone-side analysis: no compiler exists here at all.
    final ws = WorkspaceController(
      project: const Project(projectId: 'p', name: 'R'),
      store: _Store(),
      playerA: FakeStagePlayer(clipDuration: const Duration(seconds: 6)),
      playerB: FakeStagePlayer(),
      attributes: const ['Slope'],
    );
    final saved = <ComparisonResult>[];
    final analysis = AnalysisController(
      workspace: ws,
      pack: pack,
      run: (clip, patches, reference) => AnalysisEngine(
              pack: pack,
              pose: const StubPoseEstimator(styleSeed: 2),
              heads: applyPatches(headsFor(pack), patches))
          .analyzeDetailed(clip, reference: reference),
      listProfiles: () async => [
        ProfileChoice(profileId: 'prof-1', version: 2, label: 'Coach · v2', path: path),
      ],
      loadBundle: (_) async => bundle,
      saveResult: (r) async => saved.add(r),
    );
    await ws.loadClip(Stage.a, '/clips/athlete.mp4');
    await analysis.analyze();
    final r = saved.single;
    expect(r.appliedPatches, ['slope_residual_v1']);
    expect(analysis.analysis!.focus, isNull,
        reason: 'adapter priority cannot override uncertain phase measurements');
    // Stub tracker confidence is 0.8 and stub phases 0.5: usable.
    expect(analysis.analysis!.usable, isTrue);
    expect(r.warnings.where((x) => x.contains('usable threshold')), isEmpty);
    analysis.dispose();
    ws.dispose();
    c.dispose();
  });

  testWidgets('Library profile tile opens the workbench', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final packs = await tester.runAsync(() => loadPacks(rootBundle));
    final db = AppDatabase(NativeDatabase.memory());
    final dir = Directory.systemTemp.createTempSync('sv_lib');
    final path = await tester.runAsync(() async {
      final path = await storeProfilePackage(coach, dir);
      await db.saveProfile(await readProfilePackage(path), path);
      return path;
    });
    expect(path, isNotNull);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        db: db,
        packs: packs!,
        workbench: (row, active) async {
          opened = '${row.profileId}@${row.version} ${active.key}';
          return controller();
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workbench-prof-1-1')));
    await tester.pumpAndSettle();
    expect(opened, 'prof-1@1 timber/underhand');
    expect(find.text('Workbench · Coach · v1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
    dir.deleteSync(recursive: true);
  });

  group('Claude compiler (raw HTTP)', () {
    late List<(Uri, Map<String, String>, Map<String, Object?>)> requests;
    ClaudeAdapterCompiler compiler(Object response, {int status = 200}) =>
        ClaudeAdapterCompiler(
          apiKey: 'test-key',
          post: (url, headers, body) async {
            requests.add((url, headers, jsonDecode(body) as Map<String, Object?>));
            return (status, jsonEncode(response));
          },
        );
    setUp(() => requests = []);

    Map<String, Object?> reply(Object json) => {
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'thinking', 'thinking': ''},
            {'type': 'text', 'text': jsonEncode(json)},
          ],
        };

    test('sends one structured-output request and parses the weights', () async {
      final spec = pack.adapters.first;
      final names = adapterInputNames(pack, withComparison: true);
      final c = compiler(reply({
        'outputs': [
          {
            'name': 'usable',
            'bias': -20,
            'weights': [
              {'input': 'pose_confidence', 'weight': 10},
              {'input': 'implement_confidence', 'weight': 10},
              {'input': 'phase_confidence.downswing', 'weight': 6},
              {'input': 'phase_confidence.entry', 'weight': 6},
            ],
          },
        ],
      }));
      final adapter = await compileAdapter(spec, pack, c, now: DateTime.utc(2026));
      expect(adapter.compiledBy, 'claude-opus-5-5');
      expect(requests, hasLength(1));
      final (url, headers, body) = requests.single;
      expect(url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(headers['x-api-key'], 'test-key');
      expect(headers['anthropic-version'], '2026-10-21');
      expect(headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      expect(body['model'], 'claude-opus-5-5');
      expect(body['fallbacks'], 'default');
      expect(body.containsKey('thinking'), isFalse);
      final format = (body['output_config'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      final itemProps = ((((format['schema'] as Map)['properties'] as Map)['outputs']
          as Map)['items'] as Map)['properties'] as Map;
      expect((itemProps['name'] as Map)['enum'], ['usable']);
      final weightItem = ((itemProps['weights'] as Map)['items'] as Map)['properties'] as Map;
      expect((weightItem['input'] as Map)['enum'], names);
      final prompt = ((body['messages'] as List).single as Map)['content'] as String;
      expect(prompt, contains(spec.spec));
      expect(prompt, contains('"usable": false'));
    });

    test('refusal and HTTP errors become ADAPTER_COMPILE_FAILED', () async {
      for (final (c, why) in [
        (compiler({'stop_reason': 'refusal', 'stop_details': {'category': null}, 'content': []}),
            'declined'),
        (compiler({'error': {'type': 'overloaded_error'}}, status: 529), '529'),
      ]) {
        await expectLater(
            compileAdapter(pack.adapters.first, pack, c, now: DateTime.utc(2026)),
            throwsA(isA<AnalysisError>()
                .having((e) => e.errorCode, 'code', 'ADAPTER_COMPILE_FAILED')
                .having((e) => e.message, 'message', contains(why))));
      }
    });
  });
}
