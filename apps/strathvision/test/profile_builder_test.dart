import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/builder_controller.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/library_screen.dart';

/// Phase 4 through the UI: import reference clips, see each judged, build,
/// get a ready profile in the Library (or a structured rejection), and the
/// stored package matches the contract.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory store;
  late List<String> pickQueue;
  late List<(String, List<int>)> saved;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = Directory.systemTemp.createTempSync('sv_profiles');
    pickQueue = [];
    saved = [];
  });
  tearDown(() async {
    await db.close();
    store.deleteSync(recursive: true);
  });

  final pack = placeholderPack.analysisPack;
  // One synthetic "coach": every clip shares a style.
  final engine = AnalysisEngine(
    pack: pack,
    pose: const StubPoseEstimator(styleSeed: 42),
  );

  late ProfileBuilderController ctl;
  ProfileBuilderController controller(AppDatabase db, PackInfo active) =>
      ctl = ProfileBuilderController(
        pack: pack,
        fingerprint: (path) async => path, // synthetic fixture identity
        probe: (path) async => path.contains('broken')
            ? null
            : const ClipInfo(durationMs: 6000, fps: 30),
        evaluate: (clip, name) =>
            ProfileBuilder(engine: engine).evaluate(clip, displayName: name),
        store: (profile) => storeProfilePackage(profile, store),
        save: (name, bytes) async {
          saved.add((name, bytes));
          return '/saved/$name';
        },
        install: (meta, path) => db.saveProfile(meta, path),
        clock: () => DateTime.utc(2026, 11, 4, 12),
      );

  /// Build writes and re-reads the package on disk: real I/O.
  Future<void> build(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('build')));
    await tester.pump();
    for (var i = 0; i < 500 && ctl.building; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ctl.building, isFalse, reason: 'build did not finish');
    await tester.pumpAndSettle();
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          db: db,
          profileBuilder: controller,
          pickClips: () async {
            final out = [...pickQueue];
            pickQueue.clear();
            return out;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)).first);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('15 clean clips → ready profile in the Library + valid package', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tap(tester, 'build-profile');
    expect(find.text('Add 15 or more clips of one person'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('build'))).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('coach-name')),
      'Synthetic Coach',
    );
    pickQueue.addAll([
      for (var i = 0; i < 15; i++) '/ref/swing_$i.mp4',
      '/ref/broken.mp4',
    ]);
    await tap(tester, 'add-clips');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('15 clean clips · enough to build'), findsOneWidget);
    expect(
      find.text('This file could not be opened as video.'),
      findsOneWidget,
    );

    await build(tester);
    expect(find.byKey(const Key('build-ready')), findsOneWidget);
    expect(find.text('Synthetic Coach · v1 is ready'), findsOneWidget);

    // Stored package: zip with profile.json + empty specialist_patches/ and
    // adapters/, and the manifest validates against INTERFACES.md.
    final files = store.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final zip = ZipDecoder().decodeBytes(files.single.readAsBytesSync());
    final names = zip.files.map((f) => f.name).toList();
    expect(
      names,
      containsAll(['profile.json', 'specialist_patches/', 'adapters/']),
    );
    final manifest = jsonDecode(
      utf8.decode(
        zip.files.firstWhere((f) => f.name == 'profile.json').content
            as List<int>,
      ),
    );
    expect(validateProfile(manifest), isEmpty);
    expect(manifest['source_clip_count'], 15);
    expect(manifest['quality_gates']['self_consistency_passed'], isTrue);
    expect(manifest['metrics'], hasLength(pack.metrics.length));
    // The importer accepts it too.
    final meta = await tester.runAsync(
      () => readProfilePackage(files.single.path),
    );
    expect(meta!.coachName, 'Synthetic Coach');

    await tap(tester, 'save-package');
    expect(saved.single.$1, 'Synthetic_Coach_v1.zip');
    expect(find.byKey(const Key('saved')), findsOneWidget);

    // Back in the Library the profile is listed and ready.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Coach · v1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('too few clean clips → structured rejection, nothing stored', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tap(tester, 'build-profile');
    await tester.enterText(find.byKey(const Key('coach-name')), 'Coach');
    pickQueue.addAll([for (var i = 0; i < 9; i++) '/ref/s_$i.mp4']);
    await tap(tester, 'add-clips');
    expect(find.text('9 of 15 clean clips'), findsOneWidget);

    await build(tester);
    expect(find.byKey(const Key('build-rejected')), findsOneWidget);
    expect(find.text('INSUFFICIENT_CLIPS'), findsOneWidget);
    expect(
      find.text('Add 6 more clean clips to build this profile.'),
      findsOneWidget,
    );
    expect(store.listSync(), isEmpty);

    // Adding clips clears the old verdict.
    pickQueue.addAll([for (var i = 9; i < 15; i++) '/ref/s_$i.mp4']);
    await tap(tester, 'add-clips');
    expect(find.byKey(const Key('build-rejected')), findsNothing);
    await build(tester);
    expect(find.byKey(const Key('build-ready')), findsOneWidget);
    await unmount(tester);
  });

  test('package file name is filesystem-safe', () {
    final p = Profile(
      profileId: 'id',
      version: 3,
      coachName: ' Jo / "Ace" ',
      packId: 'p',
      eventId: 'e',
      metricSchemaVersion: 'v',
      createdAt: DateTime.utc(2026),
      sourceClipCount: 15,
      minClipsMet: true,
      selfConsistencyPassed: true,
      notes: '',
      metrics: const {},
    );
    expect(packageFileName(p), 'Jo_Ace_v3.zip');
  });

  test('isolate evaluator judges a clip off the UI isolate', () async {
    final q = await isolateEvaluator(pack)(
      const ClipSource(clipId: 'c', path: '/x.mp4', durationMs: 6000, fps: 30),
      'x',
    );
    expect(q.usable, isTrue);
  });
}
