import 'package:analysis_engine/analysis_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/data/database.dart';
import 'package:strathvision/main.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'support/fake_stage_player.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled pack files load from assets next to the placeholder', () async {
    final packs = await loadPacks(rootBundle);
    expect(packs.map((p) => p.packId), ['placeholder', 'timber']);
    expect(PackInfo.all(packs).map((p) => p.key), [
      'placeholder/placeholder', 'timber/underhand',
      'timber/standing_block', 'timber/springboard',
    ]);
  });

  test('active pack: saved choice, else first domain event, else placeholder', () async {
    final packs = await loadPacks(rootBundle);
    expect(activePack(packs, null).key, 'timber/underhand');
    expect(activePack(packs, 'timber/standing_block').key, 'timber/standing_block');
    expect(activePack(packs, 'gone/event').key, 'timber/underhand');
    expect(activePack([placeholderDefinition], null).key, 'placeholder/placeholder');
  });

  testWidgets('event picker selects new reviews without relabeling old ones', (tester) async {
    final packs = await tester.runAsync(() => loadPacks(rootBundle));
    final db = AppDatabase(NativeDatabase.memory());
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(db.close);
    });
    final runs = <ClipSource>[];
    await tester.pumpWidget(StrathvisionApp(
      db: db,
      sourceSignature: (path) async => 'test:$path',
      packs: packs!,
      pickClip: () async => '/clips/session.mp4',
      playerFactory: FakeStagePlayer.new,
      analysisRunner: (clip, patches, reference) {
        runs.add(clip);
        // This fixture deliberately analyzes the first review's chosen event.
        return AnalysisEngine(pack: activePack(packs, 'timber/underhand').analysisPack)
            .analyzeDetailed(clip);
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Just video'), findsOneWidget);

    Future<void> tapKey(String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    await tapKey('event-picker');
    await tapKey('event-timber/underhand');
    expect(find.text('Underhand'), findsOneWidget);
    await tapKey('open-workspace');
    expect(find.byKey(const Key('attr-Slope')), findsOneWidget);
    expect(find.byKey(const Key('attr-Timing')), findsNothing);
    await tapKey('analyze');
    final measurementScroll = find.descendant(
      of: find.byKey(const Key('analysis-metrics')),
      matching: find.byType(Scrollable),
    ).first;
    for (final label in ['Entry slope', 'Hinge at entry']) {
      await tester.scrollUntilVisible(find.text(label), 100, scrollable: measurementScroll);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    }
    expect(runs, hasLength(1));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapKey('event-picker');
    await tapKey('event-timber/standing_block');
    expect(find.text('Standing block'), findsOneWidget);
    final saved = await tester.runAsync(() => db.watchSetting(AppDatabase.activeEventKey).first);
    expect(saved, 'timber/standing_block');
    final project = (await tester.runAsync(() => db.select(db.projectRows).get()))!.single;
    await tapKey('project-${project.projectId}');
    expect(find.text('Underhand'), findsOneWidget);
    expect(find.byKey(const Key('attr-Slope')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
