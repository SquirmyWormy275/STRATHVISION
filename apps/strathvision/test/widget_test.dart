import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/main.dart';
import 'package:strathvision/profiles/profile_package.dart';

import 'support/fake_stage_player.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = Directory.systemTemp.createTempSync('sv-widget-');
  });
  tearDown(() async { await db.close(); store.deleteSync(recursive: true); });

  Future<void> pumpApp(WidgetTester tester, {String? path}) async {
    await tester.pumpWidget(StrathvisionApp(
      db: db,
      profileStore: () async => store,
      pickPath: () async => path,
      playerFactory: FakeStagePlayer.new,
    ));
    await tester.pumpAndSettle();
  }

  // Drift schedules a zero-length timer when a query stream closes; unmount
  // the app and flush it so the test does not end with pending timers.
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('Library navigates to Workspace and back', (tester) async {
    await pumpApp(tester);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Add a clip to start'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-workspace')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Review '), findsOneWidget);
    expect(find.text('Single view'), findsOneWidget);
    expect(find.byKey(const Key('stage-A')), findsOneWidget);
    expect(find.byKey(const Key('stage-B')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('importing the dummy profile lists its metadata', (tester) async {
    final path = File('test/fixtures/dummy_profile.json').absolute.path;
    await pumpApp(tester, path: path);

    // File reads must run outside the fake-async zone.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import-profile')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Dummy Coach · v1'), findsOneWidget);
    expect(find.textContaining('example_pack / example_event'), findsOneWidget);
    expect(find.textContaining('15 clips · 1 metrics'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('invalid profile shows the error and stores nothing',
      (tester) async {
    final bad = File('${Directory.systemTemp.createTempSync().path}/bad.json')
      ..writeAsStringSync('{"version": 1}');
    await pumpApp(tester, path: bad.path);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import-profile')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.textContaining('not a valid profile package'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.profiles).get()), isEmpty);
    await unmountApp(tester);
  });

  test('metadata persists across database reopen', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/sv.db');
    final meta =
        await readProfilePackage('test/fixtures/dummy_profile.json');

    final first = AppDatabase(NativeDatabase(file));
    await first.saveProfile(meta, 'dummy_profile.json');
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    final rows = await second.select(second.profiles).get();
    expect(rows.single.coachName, 'Dummy Coach');
    expect(rows.single.metricCount, 1);
    await second.close();
  });
}
