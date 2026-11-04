import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/main.dart';
import 'package:strathvision/packs/placeholder_pack.dart';

import 'support/fake_stage_player.dart';

/// Phase 3 acceptance through the real UI: Analyze on a clip produces a
/// Metric Vector that validates (including specialist_residuals); failures
/// come back as the Error Contract and leave the workspace usable.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<FakeStagePlayer> players;
  late List<String> clipQueue;
  late List<ClipSource> requests;
  late List<Map<String, Object?>> outputs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    players = [];
    clipQueue = [];
    requests = [];
    outputs = [];
  });
  tearDown(() => db.close());

  AnalysisRunner recording(AnalysisEngine engine) => (clip, patches, reference) async {
        requests.add(clip);
        final d = await engine.analyzeDetailed(clip);
        outputs.add(
            jsonDecode(jsonEncode(d.outcome.toJson())) as Map<String, Object?>);
        return d;
      };

  Future<void> pumpApp(WidgetTester tester, AnalysisRunner runner,
      {Size size = const Size(1600, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StrathvisionApp(
      db: db,
      pickClip: () async => clipQueue.isEmpty ? null : clipQueue.removeAt(0),
      playerFactory: () {
        final p = FakeStagePlayer();
        players.add(p);
        return p;
      },
      analysisRunner: runner,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-workspace')));
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

  final pack = placeholderPack.analysisPack;

  testWidgets('Analyze shows a valid Metric Vector for the active clip',
      (tester) async {
    await pumpApp(tester, recording(AnalysisEngine(pack: pack)));

    // No clip, no Analyze: the empty workspace stays a reviewer.
    expect(find.byKey(const Key('analyze')), findsNothing);

    clipQueue.add('/clips/session.mp4');
    await tap(tester, 'load-A');
    await tap(tester, 'analyze');

    expect(requests.single.durationMs, 20000);
    expect(requests.single.fps, 30);
    expect(requests.single.path, '/clips/session.mp4');
    final json = outputs.single;
    expect(validateMetricVector(json), isEmpty);
    expect(json['specialist_residuals'], contains('slope_residual'));

    expect(find.byKey(const Key('analysis-panel')), findsOneWidget);
    expect(find.text('Lead elbow angle'), findsOneWidget);
    expect(find.text('Phase 1'), findsWidgets);
    expect(find.byKey(const Key('residual-slope_residual')), findsOneWidget);
    for (final key in (json['metrics'] as Map).keys) {
      expect(find.byKey(Key('metric-$key')), findsOneWidget);
    }

    // The workspace still works with the panel open.
    await tap(tester, 'step-forward');
    expect(players[0].position, FakeStagePlayer.frame);

    await tap(tester, 'analysis-close');
    expect(find.byKey(const Key('analysis-panel')), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('failure shows the Error Contract and review keeps working',
      (tester) async {
    await pumpApp(
        tester,
        recording(AnalysisEngine(
            pack: pack, pose: const StubPoseEstimator(confidence: 0.2))));
    clipQueue.add('/clips/dark.mp4');
    await tap(tester, 'load-A');
    await tap(tester, 'analyze');

    expect(validateAnalysisError(outputs.single), isEmpty);
    expect(outputs.single['error_code'], 'LOW_POSE_CONFIDENCE');
    expect(find.byKey(const Key('analysis-error')), findsOneWidget);
    expect(find.text('LOW_POSE_CONFIDENCE'), findsOneWidget);
    expect(find.text('Review tools keep working without analysis.'),
        findsOneWidget);

    await tap(tester, 'step-forward');
    expect(players[0].position, FakeStagePlayer.frame);
    await unmountApp(tester);
  });

  testWidgets('narrow layout puts the panel under the video', (tester) async {
    await pumpApp(tester, recording(AnalysisEngine(pack: pack)),
        size: const Size(420, 900));
    clipQueue.add('/clips/session.mp4');
    await tap(tester, 'load-A');
    await tap(tester, 'analyze');
    final panel = tester.getRect(find.byKey(const Key('analysis-panel')));
    final stage = tester.getRect(find.byKey(const Key('stage-A')));
    expect(panel.top, greaterThan(stage.top));
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('results follow the active stage', (tester) async {
    await pumpApp(tester, recording(AnalysisEngine(pack: pack)));
    clipQueue.addAll(['/clips/a.mp4', '/clips/b.mp4']);
    await tap(tester, 'load-A');
    await tap(tester, 'analyze');
    await tap(tester, 'load-B'); // B becomes the active stage
    expect(find.text('Not analyzed yet'), findsOneWidget);
    await tap(tester, 'analyze');
    expect(requests.map((r) => r.path), ['/clips/a.mp4', '/clips/b.mp4']);
    expect(requests[0].clipId, isNot(requests[1].clipId));
    await unmountApp(tester);
  });

  test('isolate runner returns a valid Metric Vector', () async {
    final out = await isolateRunner(pack)(const ClipSource(
        clipId: 'c1', path: '/clips/a.mp4', durationMs: 8000, fps: 25), const [], const {});
    expect(out.outcome, isA<AnalysisSuccess>());
    expect(validateMetricVector(out.outcome.toJson()), isEmpty);
    expect(out.features, hasLength(featureWidth));
  });

  test('placeholder pack analysis section is valid and domain-neutral', () {
    expect(pack.phases, hasLength(3));
    expect(pack.metrics, hasLength(4));
    for (final m in pack.metrics) {
      expect(placeholderPack.metricLabel(m.key), isNot(m.key));
    }
  });
}
