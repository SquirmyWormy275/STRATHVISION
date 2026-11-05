// Real 3D pose on the device: BlazePose (ONNX Runtime) on decoded frames of
// a real clip, checked against an independent Python run of the same model,
// then the full analysis on top.
//   flutter test integration_test/real_pose_test.dart -d linux \
//     --dart-define=CLIP_DIR=$PWD/integration_test/assets \
//     --dart-define=REF=$PWD/../../packages/analysis_engine/test/fixtures/cleave_pose.json
//   Android: FILES="cleave.webm cleave_sideways.webm" \
//     scripts/run_android_player_test.sh "" integration_test/real_pose_test.dart
//            (CLIP_DIR=android: the test prints "CLIPS_DIR <path>" and waits
//             for the clips to be pushed; no reference comparison.)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/vision/pose_service.dart';

const refPath = String.fromEnvironment('REF');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('BlazePose on device matches the reference and drives analysis',
      (tester) async {
    await tester.runAsync(() async {
      var clipDir = const String.fromEnvironment('CLIP_DIR');
      if (clipDir == 'android') {
        clipDir = (await getExternalStorageDirectory())!.path;
        // ignore: avoid_print
        print('CLIPS_DIR $clipDir');
        final end = DateTime.now().add(const Duration(seconds: 120));
        while (!File('$clipDir/cleave_sideways.webm').existsSync() ||
            File('$clipDir/cleave_sideways.webm').lengthSync() < 1900000) {
          if (DateTime.now().isAfter(end)) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final info = await probeClip('$clipDir/cleave.webm');
      expect(info, isNotNull);
      final clip = ClipSource(
          clipId: 'cleave', path: '$clipDir/cleave.webm', durationMs: info!.durationMs, fps: info.fps);
      final sw = Stopwatch()..start();
      final track = await PoseService(maxSampleRate: 15).track(clip);
      sw.stop();
      // ignore: avoid_print
      print('pose: ${track.frames.length} frames in ${sw.elapsedMilliseconds} ms '
          '(${(sw.elapsedMilliseconds / math.max(1, track.frames.length)).toStringAsFixed(0)} ms/frame), '
          'mean confidence ${track.meanConfidence.toStringAsFixed(2)}');
      expect(track.frames.length, greaterThan(100));

      // Same clip, same frames, same pose: tracking is deterministic.
      final again = await PoseService(maxSampleRate: 15).track(clip);
      final a = {for (final f in track.frames) f.frame}, b = {for (final f in again.frames) f.frame};
      expect(again.frames.length, track.frames.length,
          reason: 'only first run: ${a.difference(b)}, only second: ${b.difference(a)}');
      for (var i = 0; i < track.frames.length; i++) {
        expect((again.frames[i].joints[Joint.leftWrist]! - track.frames[i].joints[Joint.leftWrist]!).length,
            lessThan(1e-9), reason: 'frame ${track.frames[i].frame}');
      }

      // The same clip filmed sideways (person lying in the picture, no
      // rotation metadata), turned upright with quarterTurns, gives the
      // same pose.
      final side = await probeClip('$clipDir/cleave_sideways.webm');
      expect(side, isNotNull);
      final sideTrack = await PoseService(maxSampleRate: 15, quarterTurns: 3).track(ClipSource(
          clipId: 'cleave_sideways',
          path: '$clipDir/cleave_sideways.webm',
          durationMs: side!.durationMs,
          fps: side.fps));
      final upright = {for (final f in track.frames) f.frame: f};
      final sideErrs = <double>[];
      for (final f in sideTrack.frames) {
        final u = upright[f.frame];
        if (u == null) continue;
        for (final j in [Joint.leftWrist, Joint.rightWrist, Joint.leftKnee, Joint.rightKnee]) {
          sideErrs.add((f.joints[j]! - u.joints[j]!).length);
        }
      }
      sideErrs.sort();
      // ignore: avoid_print
      print('sideways: ${sideTrack.frames.length} frames, median joint difference to upright '
          '${(sideErrs[sideErrs.length ~/ 2] * 100).toStringAsFixed(1)} cm');
      expect(sideTrack.frames.length, greaterThan(track.frames.length * 0.9));
      expect(sideErrs[sideErrs.length ~/ 2], lessThan(0.08));

      // Compare with the Python reference run (every frame there).
      if (refPath.isNotEmpty) {
        final ref = jsonDecode(File(refPath).readAsStringSync()) as Map;
        List<double> d(Object? l) => [for (final x in l! as List) (x as num).toDouble()];
        final byFrame = {
          for (final s in (ref['samples'] as List).cast<Map>())
            s['f'] as int: poseFrameFromBlazePose(s['f'] as int, d(s['w']), d(s['v']), d(s['p'])),
        };
        final errs = <double>[];
        for (final f in track.frames) {
          final r = byFrame[f.frame];
          if (r == null) continue;
          for (final j in [Joint.leftWrist, Joint.rightWrist, Joint.leftKnee, Joint.rightKnee,
              Joint.leftShoulder, Joint.rightShoulder]) {
            errs.add((f.joints[j]! - r.joints[j]!).length);
          }
        }
        errs.sort();
        final median = errs[errs.length ~/ 2];
        // ignore: avoid_print
        print('vs reference: median joint difference ${(median * 100).toStringAsFixed(1)} cm, '
            '90th ${(errs[(errs.length * 0.9).floor()] * 100).toStringAsFixed(1)} cm');
        expect(median, lessThan(0.05), reason: 'within 5 cm of the reference run');
      }

      // Full analysis on the real track.
      final packs = await loadPacks(rootBundle);
      final pack = activePack(packs, 'timber/underhand').analysisPack;
      final out = await AnalysisEngine(
              pack: pack,
              pose: PrecomputedPoseEstimator(track),
              implement: const GripImplementTracker(),
              phases: const EventPhaseDetector(),
              perStroke: true)
          .analyzeStrokes(clip);
      // ignore: avoid_print
      print('strokes: ${out.length} usable: ${out.where((s) => s.usable).length}');
      expect(out.where((s) => s.usable).length, greaterThanOrEqualTo(1));
      final summary = await AnalysisEngine(
              pack: pack,
              pose: PrecomputedPoseEstimator(track),
              implement: const GripImplementTracker(),
              phases: const EventPhaseDetector(),
              perStroke: true)
          .analyze(clip);
      expect(summary, isA<AnalysisSuccess>(), reason: '${summary.toJson()}');
      final v = (summary as AnalysisSuccess).vector;
      expect(validateMetricVector(v.toJson(), requiredResiduals: ['slope_residual']), isEmpty);
      // ignore: avoid_print
      print('entry_slope=${v.metrics['entry_slope']!.value} hinge=${v.metrics['hinge_at_entry']!.value} '
          'downswing_time=${v.metrics['downswing_time']!.value}');
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
