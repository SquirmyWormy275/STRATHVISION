import 'dart:typed_data';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/screens/analysis_panel.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/athlete_choices.dart';
import 'package:strathvision/vision/person_detector.dart';
import 'package:strathvision/vision/pose_service.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

import 'support/fake_stage_player.dart';

class _Store implements ProjectStore {
  Project? saved;
  @override
  Future<void> saveProject(Project project) async => saved = project;
}

/// Two people in the offered frame: a spectator on the left, the chopper
/// on the right.
const spectator = PersonBox(0.05, 0.2, 0.35, 0.9, 0.8);
const chopper = PersonBox(0.55, 0.1, 0.95, 0.95, 0.7);

void main() {
  late _Store store;
  late WorkspaceController ws;
  late AthleteChoices athletes;
  late AnalysisController analysis;
  late List<AthleteTarget?> runTargets;
  late List<int> loadedTurns;

  Future<PeopleFrame?> loadPeople(ClipSource clip, int frame, int turns) async {
    loadedTurns.add(turns);
    return PeopleFrame(
        rgba: Uint8List(40 * 80 * 4)..fillRange(0, 40 * 80 * 4, 128),
        width: 80,
        height: 40,
        people: turns == 0 ? const [spectator, chopper] : const []);
  }

  setUp(() async {
    store = _Store();
    runTargets = [];
    loadedTurns = [];
    ws = WorkspaceController(
      project: Project(projectId: 'p', name: 'p', clips: [
        Clip(clipId: 'c1', path: '/clip.mov', displayName: 'clip', addedAt: DateTime.utc(2026, 11, 4)),
      ]),
      store: store,
      playerA: FakeStagePlayer(),
      playerB: FakeStagePlayer(),
    );
    await ws.loadClip(Stage.a, '/clip.mov');
    athletes = AthleteChoices(
      targetFor: (id) {
        final j = ws.athleteFor(id);
        return j == null ? null : AthleteTarget.fromJson(j);
      },
      loadPeople: loadPeople,
    );
    // Stands in for the vision runner: unsure until the user chooses.
    final pack = placeholderPack.analysisPack;
    analysis = AnalysisController(
      workspace: ws,
      pack: pack,
      athletes: athletes,
      run: (clip, patches, reference) async {
        final target = athletes.targetFor(clip.clipId);
        runTargets.add(target);
        athletes.record(
            clip,
            AthleteTrack(
              track: const PoseTrack(fps: 30, frames: []),
              target: target ?? const AthleteTarget(quarterTurns: 0, frame: 12, x: 0.2, y: 0.55),
              ambiguous: target == null,
              orientationSure: true,
              candidatesFrame: 12,
              candidates: const [spectator, chopper],
            ));
        return AnalysisEngine(pack: pack).analyzeDetailed(clip);
      },
    );
  });

  tearDown(() {
    analysis.dispose();
    athletes.dispose();
    ws.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: analysis,
          builder: (_, _) => SizedBox(
              width: 520, height: 900, child: AnalysisPanel(analysis: analysis, pack: placeholderPack)),
        ),
      ),
    ));
  }

  /// Lets the picker load and decode its frame (real async work).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('unsure pick asks; tapping the chopper re-measures them and is saved', (tester) async {
    await pumpPanel(tester);
    await tester.runAsync(analysis.analyze);
    await tester.pump();
    expect(find.byKey(const Key('athlete-question')), findsOneWidget);

    await tester.tap(find.byKey(const Key('athlete-ask')));
    await tester.pump();
    await settle(tester);
    expect(find.byKey(const Key('athlete-picker')), findsOneWidget);
    expect(find.text('Who is the athlete?'), findsOneWidget);
    expect(find.text('2 people found. Tap one.'), findsOneWidget);
    // Nothing selected yet: cannot confirm.
    expect(tester.widget<FilledButton>(find.byKey(const Key('athlete-confirm'))).onPressed, isNull);

    // Tap inside the chopper's box (right side of the image).
    final image = find.byKey(const Key('athlete-picker-image'));
    final r = tester.getRect(image);
    await tester.tapAt(Offset(r.left + r.width * 0.75, r.top + r.height * 0.5));
    await tester.pump();
    expect(find.text('Selected.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('athlete-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // Saved with the project and used for the new analysis.
    final saved = AthleteTarget.fromJson(store.saved!.clipById(ws.clipOn(Stage.a)!.clipId)!.athlete!);
    expect(saved, AthleteTarget(quarterTurns: 0, frame: 12, x: chopper.cx, y: chopper.cy));
    expect(runTargets.last, saved);
    expect(find.byKey(const Key('athlete-question')), findsNothing);
    expect(find.text('Measuring the person you chose.'), findsOneWidget);
  });

  testWidgets('a sideways picture can be turned; back to automatic clears the choice', (tester) async {
    await ws.setAthlete(ws.clipOn(Stage.a)!.clipId,
        AthleteTarget(quarterTurns: 0, frame: 12, x: chopper.cx, y: chopper.cy).toJson());
    await pumpPanel(tester);
    await tester.runAsync(analysis.analyze);
    await tester.pump();
    expect(find.text('Measuring the person you chose.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('athlete-wrong')));
    await tester.pump();
    await settle(tester);
    expect(find.text('Choose the athlete'), findsOneWidget);
    // The current choice is pre-selected.
    expect(find.text('Selected.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('athlete-turn-right')));
    await tester.pump();
    await settle(tester);
    expect(loadedTurns, [0, 1]);
    expect(find.text('Nobody found in this view.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('athlete-automatic')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(ws.athleteFor(ws.clipOn(Stage.a)!.clipId), isNull);
    expect(runTargets.last, isNull);
    expect(find.byKey(const Key('athlete-question')), findsOneWidget);
  });

  testWidgets('blurred swings: suggests filming at a higher frame rate', (tester) async {
    Future<void> show(int found, int measured) async {
      analysis.dispose();
      analysis = AnalysisController(
        workspace: ws,
        pack: placeholderPack.analysisPack,
        run: (clip, patches, reference) async => AnalysisDetail(
            AnalysisFailure(AnalysisError(ErrorCode.phaseDetectionFailed, 'None measured.', const {})),
            const {},
            strokes: found,
            usableStrokes: measured),
      );
      await pumpPanel(tester);
      await tester.runAsync(analysis.analyze);
      await tester.pump();
    }

    await show(6, 1);
    expect(find.byKey(const Key('filming-tip')), findsOneWidget);
    expect(find.textContaining('1 of 6 swings could be measured'), findsOneWidget);
    // Most swings measured: no tip.
    await show(6, 5);
    expect(find.byKey(const Key('filming-tip')), findsNothing);
  });

  test('the frame-rate tip needs blur-like failures at a low frame rate', () {
    final out = AnalysisFailure(AnalysisError(ErrorCode.phaseDetectionFailed, 'x', const {}));
    expect(suggestHigherFrameRate(ClipAnalysis(outcome: out, strokes: 10, usableStrokes: 3), 30), isTrue);
    expect(suggestHigherFrameRate(ClipAnalysis(outcome: out, strokes: 10, usableStrokes: 3), 60), isFalse);
    expect(suggestHigherFrameRate(ClipAnalysis(outcome: out, strokes: 2, usableStrokes: 0), 30), isFalse);
    expect(suggestHigherFrameRate(ClipAnalysis(outcome: out, strokes: 10, usableStrokes: 6), 30), isFalse);
  });

  test('the athlete choice round-trips through the project JSON', () {
    final c = Clip(
        clipId: 'c', path: '/p', displayName: 'd', addedAt: DateTime.utc(2026), athlete: const {'x': 0.5});
    expect(Clip.fromJson(c.toJson()).athlete, {'x': 0.5});
    // Clips without a choice keep the original contract shape.
    expect(Clip(clipId: 'c', path: '/p', displayName: 'd', addedAt: DateTime.utc(2026)).toJson(),
        isNot(contains('athlete')));
  });
}
