import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/workspace_route.dart';
import 'package:strathvision/screens/workspace_screen.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

import 'support/fake_stage_player.dart';

class _Store implements ProjectStore {
  @override
  Future<void> saveProject(Project p) async {}
}

/// Phase 5 through the UI: compare with an installed profile, see the score
/// and ranked deltas, expand one, patches applied, result stored.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final pack = placeholderPack.analysisPack;

  /// A ready profile fitted from 15 synthetic clips of one coach.
  Future<Profile> coachProfile() async {
    final b = ProfileBuilder(
        engine: AnalysisEngine(
            pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(
            ClipSource(clipId: 'ref-$i', path: '/r$i', durationMs: 6000, fps: 30),
            displayName: 'ref-$i'),
    ]);
    return (b.build(
            coachName: 'Coach',
            clips: q,
            newProfileId: 'prof-1',
            now: DateTime.utc(2026, 11, 4)) as BuildReady)
        .profile;
  }

  String patchV2() => jsonEncode({
        'head': 'slope_residual',
        'version': 2,
        'base': 'slope_residual/stub/v0',
        'edits': [
          {'tensor': 'b2', 'index': [], 'delta': 0.25},
        ],
      });

  group('UI', () {
    late WorkspaceController ws;
    late AnalysisController analysis;
    late List<ComparisonResult> saved;
    late List<List<SpecialistPatch>> patchesSeen;
    late Profile profile;

    setUpAll(() async => profile = await coachProfile());

    Future<void> pump(WidgetTester tester,
        {List<ProfileChoice>? choices, Map<String, String>? patches}) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      saved = [];
      patchesSeen = [];
      ws = WorkspaceController(
        project: const Project(projectId: 'p', name: 'Review'),
        store: _Store(),
        playerA: FakeStagePlayer(clipDuration: const Duration(seconds: 6)),
        playerB: FakeStagePlayer(),
        attributes: const ['Timing'],
      );
      analysis = AnalysisController(
        workspace: ws,
        run: (clip, p) {
          patchesSeen.add(p);
          return AnalysisEngine(
                  pack: pack,
                  // The athlete: a different style from the coach.
                  pose: const StubPoseEstimator(styleSeed: 7),
                  heads: applyPatches(defaultHeads(), p))
              .analyze(clip);
        },
        listProfiles: () async => choices ??
            const [
              ProfileChoice(
                  profileId: 'prof-1', version: 1, label: 'Coach · v1', path: '/coach.zip'),
            ],
        loadBundle: (path) async =>
            ProfileBundle(profile: profile, patchFiles: patches ?? const {}),
        saveResult: (r) async => saved.add(r),
      );
      addTearDown(() {
        analysis.dispose();
        ws.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        home: WorkspaceScreen(
          controller: ws,
          analysis: analysis,
          pickClip: () async => '/clips/athlete.mp4',
        ),
      ));
      await tester.tap(find.byKey(const Key('load-A')));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('score and ranked deltas against the selected profile',
        (tester) async {
      await pump(tester, patches: {'slope_residual_v2.patch': patchV2()});
      await tap(tester, 'analyze');

      expect(find.text('Compare with'), findsOneWidget);
      expect(find.text('Coach · v1'), findsOneWidget);
      expect(find.byKey(const Key('comparison')), findsOneWidget);

      final r = saved.single;
      expect(validateComparisonResult(r.toJson()), isEmpty);
      expect(find.text('${(r.overallScore * 100).round()}%'), findsOneWidget);
      expect(find.text('style match with Coach · v1'), findsOneWidget);

      // Ranked deltas render in result order.
      final keys = r.rankedDeltas.map((d) => d.metricKey).toList();
      final tops = [
        for (final k in keys) tester.getTopLeft(find.byKey(Key('delta-$k'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));

      // Patches applied to the heads and named in the result.
      expect(patchesSeen.single.single.name, 'slope_residual_v2');
      expect(r.appliedPatches, ['slope_residual_v2']);
      expect(find.textContaining('patches: slope_residual_v2'), findsOneWidget);

      // Stub phases are low-confidence: the result warns rather than hides it.
      expect(r.warnings, isNotEmpty);
      expect(find.byKey(const Key('warning-0')), findsOneWidget);

      // Expand the top delta: definition, values, phase.
      final top = r.rankedDeltas.first;
      expect(find.byKey(Key('definition-${top.metricKey}')), findsNothing);
      await tap(tester, 'delta-${top.metricKey}');
      expect(find.byKey(Key('definition-${top.metricKey}')), findsOneWidget);
      expect(find.byKey(Key('user-${top.metricKey}')), findsOneWidget);
      expect(find.byKey(Key('coach-${top.metricKey}')), findsOneWidget);
      final coachText = tester
          .widget<Text>(find.byKey(Key('coach-${top.metricKey}')))
          .data!;
      expect(coachText, contains(top.coachCenter.toStringAsFixed(1)));
    });

    testWidgets('"Nobody" shows measurements only; no profiles → hint',
        (tester) async {
      await pump(tester);
      await tap(tester, 'analyze');
      expect(find.byKey(const Key('comparison')), findsOneWidget);
      await tap(tester, 'profile-select');
      await tester.tap(find.text('Nobody').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comparison')), findsNothing);
      expect(find.byKey(const Key('analysis-metrics')), findsOneWidget);
      expect(saved, hasLength(1)); // only the compared run is stored
    });

    testWidgets('without installed profiles the panel says how to get one',
        (tester) async {
      await pump(tester, choices: const []);
      await tap(tester, 'analyze');
      expect(find.byKey(const Key('no-profiles')), findsOneWidget);
      expect(find.byKey(const Key('comparison')), findsNothing);
    });

    testWidgets('a rejected patch is skipped and warned about', (tester) async {
      await pump(tester, patches: {
        'slope_residual_v2.patch': patchV2(),
        'slope_residual_v3.patch': '{broken',
      });
      await tap(tester, 'analyze');
      final r = saved.single;
      expect(r.appliedPatches, ['slope_residual_v2']);
      expect(r.warnings.last,
          'Specialist patch slope_residual_v3.patch was rejected and not applied.');
    });

    testWidgets('same clip, same profile → same score (deterministic)',
        (tester) async {
      await pump(tester);
      await tap(tester, 'analyze');
      await tap(tester, 'analysis-rerun');
      expect(saved, hasLength(2));
      expect(jsonEncode({...saved[0].toJson(), 'result_id': ''}),
          jsonEncode({...saved[1].toJson(), 'result_id': ''}));
    });
  });

  group('storage', () {
    late AppDatabase db;
    late Directory dir;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dir = Directory.systemTemp.createTempSync('sv_cmp');
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('bundle reader returns the profile and its patches from a zip', () async {
      final profile = await coachProfile();
      final archive = Archive()
        ..add(ArchiveFile.bytes('coach/profile.json',
            utf8.encode(jsonEncode(profile.toJson()))))
        ..add(ArchiveFile.directory('coach/specialist_patches/'))
        ..add(ArchiveFile.bytes(
            'coach/specialist_patches/slope_residual_v2.patch', utf8.encode(patchV2())))
        ..add(ArchiveFile.directory('coach/adapters/'));
      final path = '${dir.path}/coach.zip';
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      final bundle = await readProfileBundle(path);
      expect(bundle.profile.profileId, profile.profileId);
      expect(bundle.profile.referenceClips, hasLength(15));
      expect(bundle.patchFiles.keys, ['slope_residual_v2.patch']);
    });

    test('bundle reader handles package directories and builder zips', () async {
      final profile = await coachProfile();
      final zip = await storeProfilePackage(profile, dir);
      expect((await readProfileBundle(zip)).patchFiles, isEmpty);
      final pkg = Directory('${dir.path}/pkg/specialist_patches')
        ..createSync(recursive: true);
      File('${dir.path}/pkg/profile.json')
          .writeAsStringSync(jsonEncode(profile.toJson()));
      File('${pkg.path}/slope_residual_v2.patch').writeAsStringSync(patchV2());
      final b = await readProfileBundle('${dir.path}/pkg');
      expect(b.patchFiles.keys, ['slope_residual_v2.patch']);
    });

    test('compatible profiles: ready and same pack/event only', () async {
      final profile = await coachProfile();
      final zip = await storeProfilePackage(profile, dir);
      await db.saveProfile(await readProfilePackage(zip), zip);
      // Another event's profile is not offered.
      final other = await readProfilePackage('test/fixtures/dummy_profile.json');
      await db.saveProfile(other, 'test/fixtures/dummy_profile.json');
      final choices = await compatibleProfiles(db, placeholderPack);
      expect(choices.map((c) => c.label), ['Coach · v1']);
      expect(choices.single.path, zip);
    });

    test('comparison results are stored for drift', () async {
      final profile = await coachProfile();
      final v = (await AnalysisEngine(
                  pack: pack, pose: const StubPoseEstimator(styleSeed: 42))
              .analyze(const ClipSource(
                  clipId: 'c', path: '/c', durationMs: 6000, fps: 30)))
          as AnalysisSuccess;
      for (var i = 0; i < 2; i++) {
        final r = (compare(vector: v.vector, profile: profile, resultId: 'r$i')
                as ComparisonSuccess)
            .result;
        await db.saveComparison(
            projectId: 'p', result: r, at: DateTime.utc(2026, 11, 4, i));
      }
      final rows = await db.comparisonsForProfile('prof-1');
      expect(rows.map((r) => r.resultId), ['r0', 'r1']);
      expect(validateComparisonResult(jsonDecode(rows.first.json)), isEmpty);
      expect(rows.first.clipId, 'c');
    });
  });
}
