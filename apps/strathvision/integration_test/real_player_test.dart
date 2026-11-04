// Phase 2 check against the real decoder (media_kit / libmpv) on a device.
//
//   Linux:   flutter test integration_test -d linux \
//              --dart-define=CLIP_DIR=$PWD/integration_test/assets
//   Android: scripts/run_android_player_test.sh
//            (CLIP_DIR=android: the test creates the app's external files dir,
//             prints "CLIPS_DIR <path>", and waits for the clips to be pushed.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:analysis_engine/analysis_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/stage_player.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

const clipDir = String.fromEnvironment('CLIP_DIR');

class _Store implements ProjectStore {
  Project? saved;
  @override
  Future<void> saveProject(Project p) async => saved = p;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  Future<void> waitUntil(WidgetTester tester, bool Function() ok,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for decoder');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<String> resolveClipDir(WidgetTester tester) async {
    expect(clipDir, isNotEmpty, reason: 'pass --dart-define=CLIP_DIR=...');
    var dir = clipDir;
    if (clipDir == 'android') {
      dir = (await tester.runAsync(getExternalStorageDirectory))!.path;
      // ignore: avoid_print
      print('CLIPS_DIR $dir');
      await tester.runAsync(() async {
        final end = DateTime.now().add(const Duration(seconds: 120));
        while (!File('$dir/clip25.mp4').existsSync() ||
            File('$dir/clip25.mp4').lengthSync() < 1000000) {
          if (DateTime.now().isAfter(end)) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
    }
    return dir;
  }

  testWidgets('real decoder: sync, locked scrub, frame step, 0.25x, mirror',
      (tester) async {
    final dir = await resolveClipDir(tester);
    final clip30 = '$dir/clip30.mp4', clip25 = '$dir/clip25.mp4';
    expect(File(clip30).existsSync(), isTrue, reason: clip30);

    final a = MediaKitStagePlayer(), b = MediaKitStagePlayer();
    final c = WorkspaceController(
      project: const Project(projectId: 'it', name: 'Integration'),
      store: _Store(),
      playerA: a,
      playerB: b,
      attributes: const ['Timing'],
    );
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        Expanded(child: a.view(mirror: false)),
        Expanded(child: b.view(mirror: true)),
      ]),
    ));

    await c.loadClip(Stage.a, clip30);
    await c.loadClip(Stage.b, clip25);
    await waitUntil(tester,
        () => a.duration > Duration.zero && b.duration > Duration.zero);
    expect(a.duration.inMilliseconds, closeTo(10000, 100));
    expect(b.duration.inMilliseconds, closeTo(12000, 100));

    // Exact seeks.
    await c.scrub(Stage.a, const Duration(milliseconds: 2000));
    await c.scrub(Stage.b, const Duration(milliseconds: 3200));
    await waitUntil(tester,
        () => (a.decoderPosition.inMilliseconds - 2000).abs() < 40 &&
            (b.decoderPosition.inMilliseconds - 3200).abs() < 40);

    await c.setSyncPoint();
    final offset = c.sync!.offsetMs;
    expect(offset, closeTo(1200, 40));
    expect(c.locked, isTrue);

    // Locked scrub of A puts B at A + offset.
    await c.scrub(Stage.a, const Duration(milliseconds: 5000));
    await waitUntil(tester,
        () => (b.decoderPosition.inMilliseconds - (5000 + offset)).abs() < 45);

    // Frame step: A moves by one 30 fps frame, B re-aligns.
    await tester.pump(const Duration(milliseconds: 200));
    final before = a.decoderPosition;
    await c.stepFrame(forward: true);
    await waitUntil(tester, () => a.decoderPosition > before);
    final stepped = (a.decoderPosition - before).inMilliseconds;
    expect(stepped, inInclusiveRange(25, 45), reason: 'one frame at 30 fps');
    await waitUntil(tester,
        () => (b.decoderPosition - a.decoderPosition).inMilliseconds - offset < 45);

    // Locked playback at 0.25x: rate is right, and after decoder start-up the
    // pair settles within frame resolution of the offset.
    await c.setRate(0.25);
    final start = a.decoderPosition;
    final wall = Stopwatch()..start();
    await c.play();
    final drifts = <int>[];
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        drifts.add((b.decoderPosition - a.decoderPosition).inMilliseconds - offset);
      }
    });
    wall.stop();
    final advanced = (a.decoderPosition - start).inMilliseconds;
    final expected = wall.elapsedMilliseconds * 0.25;
    await c.pause();
    final settled = drifts.skip(15).map((d) => d.abs()).toList()..sort();
    final median = settled[settled.length ~/ 2];
    // ignore: avoid_print
    print('0.25x: wall=${wall.elapsedMilliseconds}ms advanced=${advanced}ms '
        'expected~${expected.round()}ms settled-drift median=${median}ms '
        'max=${settled.last}ms samples=$drifts');
    expect(advanced, inInclusiveRange(expected * 0.6, expected * 1.15));
    expect(median, lessThanOrEqualTo(45), reason: 'within ~1 frame');
    expect(settled.last, lessThan(120));

    // After pause the pair is re-aligned exactly.
    await waitUntil(tester,
        () => ((b.decoderPosition - a.decoderPosition).inMilliseconds - offset).abs() < 45);

    c.dispose();
    await a.dispose();
    await b.dispose();
  });

  testWidgets('Analyze on a real clip returns a valid Metric Vector',
      (tester) async {
    final dir = await resolveClipDir(tester);
    final a = MediaKitStagePlayer(), b = MediaKitStagePlayer();
    final c = WorkspaceController(
      project: const Project(projectId: 'it2', name: 'Analyze'),
      store: _Store(),
      playerA: a,
      playerB: b,
      attributes: const ['Timing'],
    );
    final analysis = AnalysisController(
        workspace: c, run: isolateRunner(placeholderPack.analysisPack));
    await tester.pumpWidget(MaterialApp(home: a.view(mirror: false)));
    await c.loadClip(Stage.a, '$dir/clip25.mp4');
    await waitUntil(tester, () => a.duration > Duration.zero);

    await tester.runAsync(analysis.analyze);
    final out = analysis.result;
    expect(out, isA<AnalysisSuccess>(), reason: '${out?.toJson()}');
    final json = out!.toJson();
    expect(validateMetricVector(json), isEmpty);
    expect(analysis.fps, closeTo(25, 0.01), reason: 'container-fps');
    final v = (out as AnalysisSuccess).vector;
    expect(v.phases.values.last.endFrame, closeTo(12 * 25 - 1, 3));
    expect(v.specialistResiduals['slope_residual']!.isFinite, isTrue);
    // ignore: avoid_print
    print('analyze: fps=${analysis.fps} phases=${v.phases.length} '
        'metrics=${v.metrics.length} residuals=${v.specialistResiduals}');

    analysis.dispose();
    c.dispose();
    await a.dispose();
    await b.dispose();
  });

  testWidgets('headless probe reads duration and frame rate', (tester) async {
    final dir = await resolveClipDir(tester);
    final info30 = await tester.runAsync(() => probeClip('$dir/clip30.mp4'));
    final info25 = await tester.runAsync(() => probeClip('$dir/clip25.mp4'));
    expect(info30!.durationMs, closeTo(10000, 100));
    expect(info30.fps, closeTo(30, 0.01));
    expect(info25!.durationMs, closeTo(12000, 100));
    expect(info25.fps, closeTo(25, 0.01));
    final missing =
        await tester.runAsync(() => probeClip('$dir/does_not_exist.mp4'));
    expect(missing, isNull);
  });
}
