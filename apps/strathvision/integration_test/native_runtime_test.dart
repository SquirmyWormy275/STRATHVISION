// Run on an actual native target, including the iOS Simulator in CI.
// Synthetic input verifies linking/model compatibility. The licensed video
// then exercises the production decoder, athlete tracking and analysis UI.
// Neither check establishes coaching accuracy.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:drift/native.dart';
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
import 'package:strathvision/data/database.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/workspace_route.dart';
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

  testWidgets(
    'phone imports video and profile, analyzes, compares and persists results',
    (tester) async {
      // test_ios_runtime.sh adds these test-only assets temporarily. Copy them
      // into the app sandbox: host checkout paths are not accessible on iOS.
      final work = await tester.runAsync(() async {
        final parent = await getTemporaryDirectory();
        final dir = await parent.createTemp('native_analysis_');
        try {
          for (final name in ['cleave.webm', 'coach_package.zip']) {
            final bytes = await rootBundle.load(
              'integration_test/assets/$name',
            );
            await File('${dir.path}/$name').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
              flush: true,
            );
          }
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
      final databaseFile = File('${work.path}/review.sqlite');
      final db = AppDatabase(NativeDatabase(databaseFile));
      var databaseClosed = false;
      final a = MediaKitStagePlayer(), b = MediaKitStagePlayer();
      final workspace = WorkspaceController(
        project: const Project(
          projectId: 'native-analysis',
          name: 'Licensed video check',
        ),
        store: db,
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
        listProfiles: () => compatibleProfiles(db, pack),
        saveResult: (result) => db.saveComparison(
          projectId: workspace.project.projectId,
          result: result,
        ),
      );
      final capture = GlobalKey();
      const screenshot = String.fromEnvironment('NATIVE_ANALYSIS_OUT');
      Future<void> captureScreen(String path) async {
        if (screenshot.isEmpty) return;
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
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
      addTearDown(tester.view.reset);
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
        // The shipping comparison path must use actual extracted measurements,
        // the installed package, patched heads, adapters and SQLite persistence.
        await tester.runAsync(() async {
          final packagePath = '${work.path}/coach_package.zip';
          final metadata = await readProfilePackage(packagePath);
          await applyImport(
            db,
            packagePath,
            metadata,
            null,
            () async => Directory('${work.path}/profiles'),
          );
          await File(packagePath).delete();
          await analysis.refreshProfiles();
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(analysis.choices, hasLength(1));
        expect(analysis.selectedProfile!.label, 'Laptop Coach · v1');
        await tester.tap(find.byKey(const Key('analyze')));
        await tester.pump();
        final comparisonDeadline = DateTime.now().add(
          const Duration(minutes: 2),
        );
        while (analysis.running &&
            DateTime.now().isBefore(comparisonDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(analysis.running, isFalse);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          analysis.comparison,
          isA<ComparisonSuccess>(),
          reason: '${analysis.result?.toJson()} / ${analysis.profileError}',
        );
        final comparison = (analysis.comparison as ComparisonSuccess).result;
        expect(validateComparisonResult(comparison.toJson()), isEmpty);
        expect(comparison.appliedPatches, ['slope_residual_v1']);
        expect(comparison.metricsUsed, greaterThan(0));
        expect(find.byKey(const Key('overall-score')), findsOneWidget);
        await tester.runAsync(() async {
          final stored = await db.comparisonsForProfile(comparison.profileId);
          expect(stored, hasLength(1));
          expect(jsonDecode(stored.single.json), comparison.toJson());
        });
        debugPrint(
          'NATIVE_COMPARISON_OK: ${comparison.metricsUsed} real measurements; '
          'patches=${comparison.appliedPatches}; saved history=1',
        );
        await tester.tap(find.byKey(const Key('analysis-close')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('analysis-panel')), findsNothing);
        expect(find.byKey(const Key('stage-A')), findsOneWidget);
        await tester.runAsync(() async {
          await db.close();
          databaseClosed = true;
          // Reopen the actual database, rather than inspecting only in-memory state.
          final reopened = AppDatabase(NativeDatabase(databaseFile));
          try {
            final profiles = await reopened.allProfiles();
            expect(profiles, hasLength(1));
            final history = await reopened.comparisonsForProfile(
              profiles.single.profileId,
            );
            expect(history, hasLength(1));
            expect(
              validateComparisonResult(jsonDecode(history.single.json)),
              isEmpty,
            );
            expect(await File(profiles.single.sourcePath).exists(), isTrue);
            final savedProject = await reopened.loadProject('native-analysis');
            expect(savedProject, isNotNull);
            expect(savedProject!.clips.single.path, retainedPath);
            expect(await File(savedProject.clips.single.path).exists(), isTrue);
          } finally {
            await reopened.close();
          }
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        analysis.dispose();
        athletes.dispose();
        workspace.dispose();
        await tester.runAsync(() async {
          await a.dispose();
          await b.dispose();
          if (!databaseClosed) await db.close();
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
  testWidgets(
    'native decoder handles HDR, rotation and footage without a person',
    (tester) async {
      await tester.runAsync(() async {
        final work = await (await getTemporaryDirectory()).createTemp(
          'native_formats_',
        );
        try {
          for (final name in [
            'hdr_hlg.mov',
            'cleave_sideways.webm',
            'clip25.mp4',
          ]) {
            final bytes = await rootBundle.load(
              'integration_test/assets/$name',
            );
            await File('${work.path}/$name').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          }
          final hdr = await FrameGrabber.open('${work.path}/hdr_hlg.mov');
          expect(hdr, isNotNull);
          try {
            expect(hdr!.toneMapped, isTrue);
            expect(await hdr.frameIndex(10, fps: 30), isNotNull);
          } finally {
            await hdr?.close();
          }
          final sideways = await FrameGrabber.open(
            '${work.path}/cleave_sideways.webm',
          );
          expect(sideways, isNotNull);
          try {
            expect(await sideways!.frameIndex(10, fps: 30), isNotNull);
          } finally {
            await sideways?.close();
          }
          final path = '${work.path}/clip25.mp4';
          final info = await probeClip(path);
          expect(info, isNotNull);
          final packs = await loadPacks(rootBundle);
          final pack = activePack(packs, 'timber/underhand').analysisPack;
          final result = await visionRunner(pack)(
            ClipSource(
              clipId: 'no-person',
              path: path,
              durationMs: info!.durationMs,
              fps: info.fps,
            ),
            const [],
            const {},
          );
          expect(result.outcome, isA<AnalysisFailure>());
          expect(
            (result.outcome as AnalysisFailure).error.code,
            ErrorCode.lowPoseConfidence,
          );
          // Native decoding errors must return a rejection, never measurements.
          final broken = File('${work.path}/broken.mp4');
          await broken.writeAsString('not a video');
          expect(await probeClip(broken.path), isNull);
          debugPrint(
            'NATIVE_FORMATS_OK: HDR and sideways decoded; no-person and corrupt clips rejected',
          );
        } finally {
          await work.delete(recursive: true);
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
