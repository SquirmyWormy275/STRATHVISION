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

/// Phase 6 in the app: pack files load at runtime, the active event is
/// chosen in the Library and persists, and its attributes and metrics drive
/// the workspace.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled pack files load from assets next to the placeholder', () async {
    final packs = await loadPacks(rootBundle);
    expect(packs.map((p) => p.packId), ['placeholder', 'timber']);
    final all = PackInfo.all(packs).map((p) => p.key);
    expect(all, ['placeholder/placeholder', 'timber/underhand', 'timber/standing_block', 'timber/springboard']);
  });

  test('active pack: saved choice, else first domain event, else placeholder',
      () async {
    final packs = await loadPacks(rootBundle);
    expect(activePack(packs, null).key, 'timber/underhand');
    expect(activePack(packs, 'timber/standing_block').key, 'timber/standing_block');
    expect(activePack(packs, 'gone/event').key, 'timber/underhand');
    expect(activePack([placeholderDefinition], null).key, 'placeholder/placeholder');
  });

  testWidgets('event picker switches the pack the workspace uses',
      (tester) async {
    final packs = await tester.runAsync(() => loadPacks(rootBundle));
    final db = AppDatabase(NativeDatabase.memory());
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final runs = <ClipSource>[];
    await tester.pumpWidget(StrathvisionApp(
      db: db,
      packs: packs!,
      pickClip: () async => '/clips/session.mp4',
      playerFactory: FakeStagePlayer.new,
      analysisRunner: (clip, patches, reference) {
        runs.add(clip);
        final key = tester
            .widget<Text>(find.byKey(const Key('active-event'), skipOffstage: false))
            .data;
        final pack = activePack(packs,
                key == 'Underhand' ? 'timber/underhand' : 'timber/standing_block')
            .analysisPack;
        return AnalysisEngine(pack: pack).analyzeDetailed(clip);
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Underhand'), findsOneWidget);

    // Timber attributes in the mark bar, timber metrics in Analyze.
    await tester.tap(find.byKey(const Key('open-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load-A')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attr-Slope')), findsOneWidget);
    expect(find.byKey(const Key('attr-Timing')), findsNothing);
    await tester.tap(find.byKey(const Key('analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Entry slope'), findsOneWidget);
    expect(find.text('Hinge at entry'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Switch to Standing block; the choice persists.
    await tester.tap(find.byKey(const Key('event-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-timber/standing_block')));
    await tester.pumpAndSettle();
    expect(find.text('Standing block'), findsOneWidget);
    final saved = await tester.runAsync(
        () => db.watchSetting(AppDatabase.activeEventKey).first);
    expect(saved, 'timber/standing_block');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
