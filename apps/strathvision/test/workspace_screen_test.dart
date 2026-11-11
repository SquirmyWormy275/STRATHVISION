import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/main.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/workspace/project.dart';

import 'support/fake_stage_player.dart';

/// Phase 2 acceptance through the real UI: load two clips, align, play locked
/// at 0.25x, mark, leave, re-open — sync, rate, and marks are intact.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<FakeStagePlayer> players;
  late List<String> clipQueue;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    players = [];
    clipQueue = [];
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => db.setSetting(AppDatabase.activeEventKey, placeholderPack.key),
    );
    await tester.pumpWidget(
      StrathvisionApp(
        db: db,
        packs: [placeholderDefinition],
        sourceSignature: (path) async => 'test:$path',
        pickClip: () async => clipQueue.isEmpty ? null : clipQueue.removeAt(0),
        playerFactory: () {
          final p = FakeStagePlayer();
          players.add(p);
          return p;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('align, play locked at 0.25x, mark, re-open with sync intact', (
    tester,
  ) async {
    await pumpApp(tester);
    clipQueue.add('/clips/coach.mp4');
    await tap(tester, 'open-workspace');
    final a = players[0], b = players[1];

    // Load both stages. Advanced controls appear only once there are two clips.
    expect(find.byKey(const Key('set-sync')), findsNothing);
    clipQueue.add('/clips/athlete.mp4');
    expect(find.text('Single view'), findsOneWidget);
    await tap(tester, 'load-B');
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.textContaining('coach'), findsWidgets);
    expect(find.textContaining('athlete'), findsWidgets);

    // Align: put B 1.5 s ahead of A, then one tap on "Sync here".
    a.jumpTo(const Duration(milliseconds: 500));
    b.jumpTo(const Duration(milliseconds: 2000));
    await tap(tester, 'set-sync');
    expect(find.text('Linked · B +1.50 s'), findsOneWidget);

    // 0.25x, play locked.
    await tester.tap(find.text('.25×'));
    await tester.pumpAndSettle();
    expect(a.rate, 0.25);
    expect(b.rate, 0.25);
    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    expect(a.playing && b.playing, isTrue);
    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    expect(a.playing || b.playing, isFalse);

    // Frame step the locked pair.
    await tap(tester, 'step-forward');
    expect(b.position - a.position, const Duration(milliseconds: 1500));

    // Mirror B keeps sync.
    await tap(tester, 'mirror');
    expect(find.byKey(const Key('fake-video-mirrored')), findsOneWidget);
    expect(find.text('Linked · B +1.50 s'), findsOneWidget);

    // Red/green on the selected attribute.
    await tap(tester, 'attr-Path');
    await tap(tester, 'mark-green');
    await tap(tester, 'mark-red');
    var saved = (await db.select(db.projectRows).get()).single;
    expect(saved.json, contains('"label":"green"'));
    expect(saved.json, contains('"attribute":"Path"'));

    // Undo removes the red mark.
    await tap(tester, 'undo');
    saved = (await db.select(db.projectRows).get()).single;
    expect(saved.json, isNot(contains('"label":"red"')));

    // Leave and re-open the project from the Library.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(a.disposed && b.disposed, isTrue);
    await tester.tap(find.byKey(Key('project-${saved.projectId}')));
    await tester.pumpAndSettle();

    final a2 = players[2], b2 = players[3];
    expect(a2.openedPath, '/clips/coach.mp4');
    expect(b2.openedPath, '/clips/athlete.mp4');
    expect(find.text('Linked · B +1.50 s'), findsOneWidget);
    expect(a2.rate, 0.25);
    expect(find.byKey(const Key('fake-video-mirrored')), findsOneWidget);

    // Locked scrub still holds the offset after re-open.
    a2.jumpTo(const Duration(seconds: 3));
    await tap(tester, 'step-forward');
    expect(b2.position - a2.position, const Duration(milliseconds: 1500));

    final reopened = Project.fromJson(
      (await db.loadProject(saved.projectId))!.toJson(),
    );
    expect(reopened.marks.single.label, MarkLabel.green);

    await unmountApp(tester);
  });

  testWidgets('Clear sync returns to independent and hides lock controls', (
    tester,
  ) async {
    await pumpApp(tester);
    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);
    await tap(tester, 'open-workspace');
    await tap(tester, 'load-B');
    await tap(tester, 'set-sync');
    expect(find.byKey(const Key('lock')), findsOneWidget);
    await tap(tester, 'clear-sync');
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.byKey(const Key('lock')), findsNothing);
    expect(find.byKey(const Key('set-sync')), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('swap keeps the pair locked with the offset reversed', (
    tester,
  ) async {
    await pumpApp(tester);
    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);
    await tap(tester, 'open-workspace');
    final a = players[0], b = players[1];
    await tap(tester, 'load-B');
    b.jumpTo(const Duration(milliseconds: 750));
    await tap(tester, 'set-sync');
    await tap(tester, 'swap');
    expect(find.text('Linked · B −0.75 s'), findsOneWidget);
    expect(a.openedPath, '/clips/two.mp4');
    expect(b.openedPath, '/clips/one.mp4');
    await unmountApp(tester);
  });

  testWidgets('annotation is saved at the current position', (tester) async {
    await pumpApp(tester);
    clipQueue.add('/clips/one.mp4');
    await tap(tester, 'open-workspace');
    players[0].jumpTo(const Duration(milliseconds: 1200));
    await tap(tester, 'annotate');
    await tester.enterText(find.byKey(const Key('annotation-text')), 'early');
    await tap(tester, 'annotation-save');
    final row = (await db.select(db.projectRows).get()).single;
    final project = Project.fromJson(
      (await db.loadProject(row.projectId))!.toJson(),
    );
    expect(project.annotations.single.text, 'early');
    expect(project.annotations.single.timeMs, 1200);
    await unmountApp(tester);
  });
}
