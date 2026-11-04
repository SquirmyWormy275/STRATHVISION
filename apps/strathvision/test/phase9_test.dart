import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/data/database.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/inbox.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_health.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/drift_screen.dart';
import 'package:strathvision/screens/library_screen.dart';

/// Phase 9: match trend over sessions, profile health, and packages moving
/// between devices with no cloud.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late List<PackDefinition> packs;
  late PackInfo underhand;
  late Profile coach;

  setUpAll(() async {
    packs = await loadPacks(rootBundle);
    underhand = activePack(packs, 'timber/underhand');
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: underhand.analysisPack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    coach = (b.build(coachName: 'Coach', clips: q, newProfileId: 'prof-1', now: DateTime.utc(2026))
            as BuildReady)
        .profile;
  });

  Future<List<ComparisonResult>> results(List<int> styles) async => [
        for (final s in styles)
          (compare(
                  vector: ((await AnalysisEngine(
                                  pack: underhand.analysisPack,
                                  pose: StubPoseEstimator(styleSeed: s))
                              .analyze(ClipSource(clipId: 'c$s', path: '/c', durationMs: 6000, fps: 30)))
                          as AnalysisSuccess)
                      .vector,
                  profile: coach,
                  resultId: 'r$s') as ComparisonSuccess)
              .result,
      ];

  group('drift view', () {
    Future<void> pump(WidgetTester tester, DriftSummary s) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: DriftScreen(title: 'Coach · Underhand', summary: s, pack: underhand)));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the match trend over sessions', (tester) async {
      final rs = await tester.runAsync(() => results([7, 3, 42]));
      final s = summarizeDrift([
        for (var i = 0; i < 3; i++)
          DriftPoint.fromResult(DateTime(2026, 11, 1 + 2 * i, 10),
              jsonDecode(jsonEncode(rs![i].toJson())) as Map<String, Object?>),
      ]);
      expect(s.sessions, hasLength(3));
      await pump(tester, s);
      expect(find.text('${(s.sessions.last.meanScore * 100).round()}%'), findsOneWidget);
      expect(find.byKey(const Key('drift-chart')), findsOneWidget);
      expect(find.byKey(const Key('drift-direction')), findsOneWidget);
      expect(find.byKey(const Key('drift-metric-entry_slope')), findsOneWidget);
      expect(find.text('Entry slope'), findsOneWidget);

      // Tap a point: tooltip with that session.
      final chart = tester.getRect(find.byKey(const Key('drift-chart')));
      await tester.tapAt(Offset(chart.right - 14, chart.center.dy));
      await tester.pump();
      expect(find.byKey(const Key('drift-tooltip')), findsOneWidget);
      expect(find.text('Nov 5'), findsWidgets);

      // Table view for the same data.
      await tester.tap(find.byKey(const Key('drift-table-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drift-table')), findsOneWidget);
      expect(find.text('Nov 1'), findsOneWidget);
      expect(find.text('Nov 3'), findsOneWidget);
    });

    testWidgets('empty state says how to start', (tester) async {
      await pump(tester, summarizeDrift(const []));
      expect(find.byKey(const Key('drift-empty')), findsOneWidget);
    });
  });

  test('profile health flags what matters', () {
    final events = PackInfo.all(packs);
    final ok = profileHealth(
        bundle: ProfileBundle(profile: coach, patchFiles: const {}), events: events, comparisons: 3);
    expect(ok.map((h) => h.label), ['Ready', '15 of 15 clips', 'Up to date', '3 comparisons']);
    expect(ok.every((h) => h.ok), isTrue);

    final old = Profile.fromJson({...coach.toJson(), 'metric_schema_version': 'timber-underhand-0'});
    final h2 = profileHealth(
        bundle: ProfileBundle(
            profile: old,
            patchFiles: const {'slope_residual_v1.patch': '{bad'},
            adapterFiles: const {'usable_footage.paw': '{bad'}),
        events: events,
        comparisons: 0);
    final bad = {for (final h in h2.where((h) => !h.ok)) h.label};
    expect(bad, containsAll(['Needs rebuild', '1 patch rejected', 'Adapters out of date']));

    final foreign = Profile.fromJson({...coach.toJson(), 'pack_id': 'olympic_lifting'});
    expect(profileHealth(bundle: ProfileBundle(profile: foreign, patchFiles: const {}),
            events: events, comparisons: 0)
        .last
        .label, 'Pack not installed');
  });

  group('moving packages without cloud', () {
    late AppDatabase db;
    late Directory dir;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dir = Directory.systemTemp.createTempSync('sv_p9');
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('Library: export a package, trend button opens drift',
        (tester) async {
      final saved = <(String, List<int>)>[];
      await tester.runAsync(() async {
        final path = await storeProfilePackage(coach, Directory('${dir.path}/laptop'),
            patches: {'slope_residual_v1.patch': '{"x":1}'},
            research: {'mixture_edits_v1.json': '{}'});
        await db.saveProfile(await readProfilePackage(path), path);
        final rs = await results([7, 3]);
        for (var i = 0; i < rs.length; i++) {
          await db.saveComparison(projectId: 'p', result: rs[i], at: DateTime(2026, 11, 1 + i, 9));
        }
      });
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          db: db,
          packs: packs,
          workbench: (row, pack) => throw UnimplementedError(),
          saveFile: (name, bytes) async {
            saved.add((name, bytes));
            return '/usb/$name';
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-prof-1-1')));
      for (var i = 0; i < 20 && saved.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(saved.single.$1, 'Coach_v1.zip');
      final zip = ZipDecoder().decodeBytes(saved.single.$2);
      final names = zip.files.map((f) => f.name).toList();
      expect(names, containsAll(['profile.json', 'specialist_patches/slope_residual_v1.patch']));
      expect(names.where((n) => n.startsWith('carne_asada')), isEmpty,
          reason: 'coaching profile only: research stays on the laptop');

      // "Phone": the file arrives by any local means and imports cleanly.
      final phone = File('${dir.path}/phone_Coach_v1.zip')..writeAsBytesSync(saved.single.$2);
      final meta = await tester.runAsync(() => readProfilePackage(phone.path));
      expect(meta!.profileId, 'prof-1');

      await tester.tap(find.byKey(const Key('trend-prof-1-1')));
      for (var i = 0; i < 20 && find.byType(DriftScreen).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(DriftScreen), findsOneWidget);
      expect(find.text('Style match by session'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    test('shared inbox folder imports new packages once, skips bad files', () async {
      final inbox = Directory('${dir.path}/inbox')..createSync();
      final store = Directory('${dir.path}/store');
      await storeProfilePackage(coach, inbox);
      File('${inbox.path}/notes.zip').writeAsStringSync('not a zip');
      File('${inbox.path}/clip.mp4').writeAsStringSync('video');
      expect(await scanInbox(db, inbox.path, store), 1);
      expect(await scanInbox(db, inbox.path, store), 0); // already installed
      final rows = await db.allProfiles();
      expect(rows.single.profileId, 'prof-1');
      expect(rows.single.sourcePath, startsWith(store.path)); // private copy
      // The inbox can be cleaned; the Library keeps working.
      inbox.deleteSync(recursive: true);
      expect((await readProfileBundle(rows.single.sourcePath)).profile.coachName, 'Coach');
      expect(placeholderPack.packId, 'placeholder');
    });
  });
}
