// Run on an actual native target, including the iOS Simulator in CI.
// Synthetic input verifies linking/model compatibility. The licensed video
// then exercises the production decoder, athlete tracking and analysis UI.
// Neither check establishes coaching accuracy.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/media/picked_video.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/screens/workspace_screen.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/athlete_choices.dart';
import 'package:strathvision/vision/blazepose.dart';
import 'package:strathvision/vision/frame_grabber.dart';
import 'package:strathvision/vision/person_detector.dart';
import 'package:strathvision/vision/pose_math.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/stage_player.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

class _MemoryProjectStore implements ProjectStore {
  @override
  Future<void> saveProject(Project project) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('native runtime loads and executes both shipped models', (
    tester,
  ) async {
    await tester.runAsync(() async {
      ensureOrtEnv();
      expect(OrtEnv.version, '1.15.1');
      final pose = BlazePose.load(
        (await rootBundle.load('assets/models/pose_landmark_full.onnx')).buffer
            .asUint8List(),
      );
      try {
        final result = await pose.infer(
          Float32List(poseInputSize * poseInputSize * 3),
        );
        expect(result.landmarks, hasLength(39 * 5));
        expect(result.world, hasLength(39 * 3));
        expect(result.presence, inInclusiveRange(0.0, 1.0));
        expect(
          [
            ...result.landmarks,
            ...result.world,
          ].every((value) => value.isFinite),
          isTrue,
        );
      } finally {
        pose.release();
      }
      final detector = PersonDetector.load(
        (await rootBundle.load('assets/models/yolox_nano.onnx')).buffer
            .asUint8List(),
      );
      try {
        final frame = VideoFrame(Uint8List(64 * 64 * 4), 64, 64, 64 * 4);
        expect(await detector.detect(frame), isEmpty);
      } finally {
        detector.release();
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('licensed video produces measurements through the phone UI', (
    tester,
  ) async {
    // test_ios_runtime.sh adds this single test-only asset temporarily. Copy it
    // into the app sandbox: host checkout paths are not accessible on iOS.
    final work = await tester.runAsync(() async {
      final parent = await getTemporaryDirectory();
      final dir = await parent.createTemp('native_analysis_');
      try {
        final bytes = await rootBundle.load(
          'integration_test/assets/cleave.webm',
        );
        await File('${dir.path}/cleave.webm').writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        return dir;
      } catch (_) {
        await dir.delete(recursive: true);
        rethrow;
      }
    });
    final exported = File('${work!.path}/cleave.webm');
    String? retainedPath;
    addTearDown(() async {
      if (Platform.isIOS &&
          retainedPath != null &&
          retainedPath != exported.path) {
        // This unique imported-clip directory was created by this test. Never
        // remove the shared imported_clips folder or other user imports.
        await File(retainedPath).parent.delete(recursive: true);
      }
      if (await work.exists()) await work.delete(recursive: true);
    });
    retainedPath = await tester.runAsync(
      () => retainPickedVideo(exported.path),
    );
    expect(retainedPath, isNotNull);
    if (Platform.isIOS) {
      expect(retainedPath, isNot(exported.path));
      await tester.runAsync(() async {
        expect(
          await File(retainedPath!).readAsBytes(),
          await exported.readAsBytes(),
        );
        await exported.delete();
      });
    } else {
      expect(retainedPath, exported.path);
    }
    final packs = await tester.runAsync(() => loadPacks(rootBundle));
    final pack = activePack(packs!, 'timber/underhand');
    final a = MediaKitStagePlayer(), b = MediaKitStagePlayer();
    final workspace = WorkspaceController(
      project: const Project(
        projectId: 'native-analysis',
        name: 'Licensed video check',
      ),
      store: _MemoryProjectStore(),
      playerA: a,
      playerB: b,
      attributes: pack.topAttributes,
      packId: pack.packId,
      eventId: pack.eventId,
    );
    final athletes = AthleteChoices(
      targetFor: (id) {
        final value = workspace.athleteFor(id);
        return value == null ? null : AthleteTarget.fromJson(value);
      },
    );
    final analysis = AnalysisController(
      workspace: workspace,
      pack: pack.analysisPack,
      run: visionRunner(pack.analysisPack, athletes: athletes),
      athletes: athletes,
      listProfiles: () async => const [],
    );
    final capture = GlobalKey();
    const screenshot = String.fromEnvironment('NATIVE_ANALYSIS_OUT');
    Future<void> captureScreen(String path) async {
      if (screenshot.isEmpty) return;
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      );
      try {
        final bytes = await image!.toByteData(format: ui.ImageByteFormat.png);
        await tester.runAsync(() async {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      } finally {
        image?.dispose();
      }
    }

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    try {
      // VideoController initializes after the first Flutter frame. Mount the
      // real screen before awaiting open, as the app route does in production.
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            home: WorkspaceScreen(
              controller: workspace,
              analysis: analysis,
              pack: pack,
              eventConfirmed: true,
            ),
          ),
        ),
      );
      // Native video textures can continue scheduling frames while paused.
      // Use a bounded pump instead of waiting for the renderer to become idle.
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('NATIVE_ANALYSIS: opening the sandboxed video');
      await tester.runAsync(() => workspace.loadClip(Stage.a, retainedPath!));
      expect(a.hasMedia, isTrue);
      expect(a.duration.inMilliseconds, greaterThan(1000));
      final fps = await tester.runAsync(a.frameRate);
      expect(fps, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('analyze')), findsOneWidget);
      await captureScreen('$screenshot.before.png');
      final elapsed = Stopwatch()..start();
      debugPrint('NATIVE_ANALYSIS: tapping Analyze');
      await tester.tap(find.byKey(const Key('analyze')));
      await tester.pump();
      expect(analysis.running, isTrue);
      expect(find.byKey(const Key('analysis-running')), findsOneWidget);
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (analysis.running && DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      elapsed.stop();
      expect(
        analysis.running,
        isFalse,
        reason: 'Native video analysis timed out.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      final result = analysis.result;
      expect(result, isA<AnalysisSuccess>(), reason: '${result?.toJson()}');
      final vector = (result as AnalysisSuccess).vector;
      expect(
        validateMetricVector(
          vector.toJson(),
          requiredResiduals: ['slope_residual'],
        ),
        isEmpty,
      );
      expect(vector.metrics, isNotEmpty);
      expect(
        vector.metrics.values.every((metric) => metric.value.isFinite),
        isTrue,
      );
      expect(analysis.analysis!.usableStrokes, greaterThanOrEqualTo(1));
      expect(analysis.selectedProfile, isNull);
      expect(analysis.comparison, isNull);
      expect(find.byKey(const Key('analysis-metrics')), findsOneWidget);
      expect(find.byKey(const Key('analysis-error')), findsNothing);
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_ANALYSIS_OK: ${analysis.analysis!.usableStrokes} usable strokes; '
        '${vector.metrics.length} real metrics in ${elapsed.elapsedMilliseconds} ms; '
        'fps=$fps; duration_ms=${a.duration.inMilliseconds}',
      );

      await captureScreen(screenshot);
      await tester.tap(find.byKey(const Key('analysis-close')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('analysis-panel')), findsNothing);
      expect(find.byKey(const Key('stage-A')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      analysis.dispose();
      athletes.dispose();
      workspace.dispose();
      await tester.runAsync(() async {
        await a.dispose();
        await b.dispose();
      });
      tester.view.reset();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
