import 'dart:async';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/design/sv_theme.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/screens/workspace_screen.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

import 'support/fake_stage_player.dart';

class _Store implements ProjectStore {
  Project? project;
  @override
  Future<void> saveProject(Project value) async {
    project = value;
  }
}

/// Actual Flutter screenshots with deterministic player doubles, not native footage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Source Sans 3': [
        'SourceSans3-Regular.ttf',
        'SourceSans3-Semibold.ttf',
        'SourceSans3-Bold.ttf',
      ],
      'Barlow Semi Condensed': [
        'BarlowSemiCondensed-Bold.ttf',
        'BarlowSemiCondensed-ExtraBoldItalic.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
  });
  test('critical colors meet ordinary-text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
    }

    for (final fill in [SvColors.cobalt, SvColors.good, SvColors.needsWork]) {
      expect(contrast(fill, SvColors.white), greaterThanOrEqualTo(4.5));
    }
    expect(contrast(SvColors.ink, SvColors.chalk), greaterThanOrEqualTo(4.5));
    expect(
      contrast(SvColors.paleCobalt, SvColors.slate),
      greaterThanOrEqualTo(4.5),
    );
  });
  for (final spec in [
    (name: 'phone-light', size: const Size(390, 844), scale: 1.0, dark: false),
    (name: 'desktop-dark', size: const Size(1440, 900), scale: 1.0, dark: true),
    (
      name: 'phone-large-text',
      size: const Size(390, 844),
      scale: 2.0,
      dark: false,
    ),
    (
      name: 'small-landscape',
      size: const Size(780, 420),
      scale: 1.0,
      dark: true,
    ),
  ]) {
    testWidgets('${spec.name}: single, compare, resize and mark', (
      tester,
    ) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _Store(), a = FakeStagePlayer(), b = FakeStagePlayer();
      final c = WorkspaceController(
        project: const Project(projectId: 'review', name: 'Movement review'),
        store: store,
        playerA: a,
        playerB: b,
        attributes: placeholderPack.topAttributes,
      );
      await c.loadClip(Stage.a, '/fixture/current.mp4');
      a.jumpTo(const Duration(milliseconds: 5860));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('ui-capture'),
          child: MaterialApp(
            theme: spec.dark ? SvTheme.dark() : SvTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(spec.scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: WorkspaceScreen(
              controller: c,
              pickClip: () async => '/fixture/reference.mp4',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-A')), findsOneWidget);
      expect(find.byKey(const Key('stage-B')), findsNothing);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Needs work'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
          find.byKey(const Key('ui-capture')),
          matchesGoldenFile('goldens/candidates/${spec.name}-single.png'),
        );
      }
      await tester.ensureVisible(find.byKey(const Key('load-B')));
      await tester.tap(find.byKey(const Key('load-B')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-B')), findsOneWidget);
      final opens = [...a.log.where((s) => s.startsWith('open '))];
      tester.view.physicalSize = Size(spec.size.height, spec.size.width);
      await tester.pumpAndSettle();
      expect(a.log.where((s) => s.startsWith('open ')), opens);
      expect(a.position.inMilliseconds, 5860);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = spec.size;
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
          find.byKey(const Key('ui-capture')),
          matchesGoldenFile('goldens/candidates/${spec.name}-comparison.png'),
        );
      }
      await tester.ensureVisible(find.byKey(const Key('mark-green')));
      await tester.tap(find.byKey(const Key('mark-green')));
      await tester.pumpAndSettle();
      expect(store.project!.marks.single.label, MarkLabel.green);
      await tester.ensureVisible(find.byKey(const Key('undo')));
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(store.project!.marks, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      c.dispose();
      await a.dispose();
      await b.dispose();
    });
  }
  testWidgets('analysis never locks playback controls', (tester) async {
    final a = FakeStagePlayer(), b = FakeStagePlayer();
    final c = WorkspaceController(
      project: const Project(projectId: 'p', name: 'Review'),
      store: _Store(),
      playerA: a,
      playerB: b,
      attributes: placeholderPack.topAttributes,
    );
    await c.loadClip(Stage.a, '/fixture/clip.mp4');
    final gate = Completer<AnalysisDetail>();
    final analysis = AnalysisController(
      workspace: c,
      pack: placeholderPack.analysisPack,
      run: (_, _, _) => gate.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SvTheme.light(),
        home: WorkspaceScreen(controller: c, analysis: analysis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('analyze')));
    await tester.pump();
    expect(analysis.running, isTrue);
    await tester.tap(find.byKey(const Key('step-forward')));
    await tester.pump();
    expect(a.position, FakeStagePlayer.frame);
    gate.complete(
      await AnalysisEngine(pack: placeholderPack.analysisPack).analyzeDetailed(
        const ClipSource(
          clipId: 'fixture',
          path: '/fixture/clip.mp4',
          durationMs: 20000,
          fps: 30,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    analysis.dispose();
    c.dispose();
    await a.dispose();
    await b.dispose();
  });
  testWidgets('typing a note cannot trigger global shortcuts', (tester) async {
    final store = _Store(), a = FakeStagePlayer(), b = FakeStagePlayer();
    final c = WorkspaceController(
      project: const Project(projectId: 'p', name: 'Review'),
      store: store,
      playerA: a,
      playerB: b,
      attributes: placeholderPack.topAttributes,
    );
    await c.loadClip(Stage.a, '/fixture/clip.mp4');
    await tester.pumpWidget(
      MaterialApp(
        theme: SvTheme.light(),
        home: WorkspaceScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('annotate')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('annotation-text')),
      'good rhythm',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.project.marks, isEmpty);
    expect(a.playing, isFalse);
    await tester.tap(find.byKey(const Key('annotation-save')));
    await tester.pumpAndSettle();
    expect(c.project.annotations, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    c.dispose();
    await a.dispose();
    await b.dispose();
  });
}
