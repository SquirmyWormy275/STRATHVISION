// Evaluation on real coaching footage (not committed; paths passed in).
//   flutter test integration_test/gurr_eval_test.dart -d linux \
//     --dart-define=CLIPS='/path/a.MOV|/path/b.MOV' --dart-define=EVENT=standing_block \
//     --dart-define=SECONDS=25 --dart-define=OUT=/tmp/eval [--dart-define=TURNS=0|1|3 (default: automatic)] [--dart-define=RATE=15]
import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/vision/pose_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('evaluate clips', (tester) async {
    await tester.runAsync(() async {
      final packs = await loadPacks(rootBundle);
      final pack = activePack(packs, 'timber/${const String.fromEnvironment('EVENT', defaultValue: 'standing_block')}')
          .analysisPack;
      const seconds = int.fromEnvironment('SECONDS', defaultValue: 25);
      const out = String.fromEnvironment('OUT');
      await Directory(out).create(recursive: true);
      for (final path in const String.fromEnvironment('CLIPS').split('|')) {
        final name = path.split('/').last;
        final info = await probeClip(path);
        if (info == null) {
          // ignore: avoid_print
          print('EVAL $name: could not open');
          continue;
        }
        final ms = info.durationMs < seconds * 1000 ? info.durationMs : seconds * 1000;
        final clip = ClipSource(clipId: name, path: path, durationMs: ms, fps: info.fps);
        final xy = <Map<String, Object?>>[];
        var size = [0, 0];
        final sw = Stopwatch()..start();
        const turns = int.fromEnvironment('TURNS', defaultValue: -1);
        final athlete = await PoseService(
                quarterTurns: turns < 0 ? null : turns,
                maxSampleRate: const int.fromEnvironment('RATE', defaultValue: 15).toDouble())
            .trackAthlete(clip, onLandmarks: (f, pts, w, h) {
          xy.add({'f': f, 'xy': [for (final v in pts) double.parse(v.toStringAsFixed(1))]});
          size = [w, h];
        });
        final track = athlete.track;
        final engine = AnalysisEngine(
            pack: pack,
            pose: PrecomputedPoseEstimator(track),
            implement: const GripImplementTracker(),
            phases: const EventPhaseDetector(),
            perStroke: true);
        final strokes = await engine.analyzeStrokes(clip);
        final summary = await engine.analyze(clip);
        final report = {
          'clip': name,
          'size': size,
          'fps': info.fps,
          'seconds': ms / 1000,
          'pose_frames': track.frames.length,
          'ms_per_frame': sw.elapsedMilliseconds / (track.frames.isEmpty ? 1 : track.frames.length),
          'mean_confidence': track.meanConfidence,
          'target': athlete.target?.toJson(),
          'ambiguous': athlete.ambiguous,
          'orientation_sure': athlete.orientationSure,
          'candidates': [for (final b in athlete.candidates) b.toJson()],
          'strokes': [
            for (final s in strokes)
              {
                'span': [s.startFrame, s.endFrame],
                'usable': s.usable,
                'issues': [for (final i in s.issues) i.name],
                'phases': switch (s.detail.outcome) {
                  AnalysisSuccess(:final vector) => {
                      for (final e in vector.phases.entries) e.key: [e.value.startFrame, e.value.endFrame],
                    },
                  AnalysisFailure(:final error) => error.details,
                },
              },
          ],
          'summary': summary.toJson(),
          'landmarks': xy,
          // Engine-side pose (joint name → metres, confidence) for offline
          // replay of the stroke and phase stages.
          'track': [
            for (final f in track.frames)
              {
                'f': f.frame,
                'j': {for (final e in f.joints.entries) e.key.name: [e.value.x, e.value.y, e.value.z]},
                'c': {for (final e in f.confidence.entries) e.key.name: e.value},
              },
          ],
        };
        File('$out/$name.json').writeAsStringSync(jsonEncode(report));
        // ignore: avoid_print
        print('EVAL $name ${size[0]}x${size[1]} pose ${track.frames.length} frames '
            '${(report['ms_per_frame'] as double).toStringAsFixed(0)} ms/f conf ${track.meanConfidence.toStringAsFixed(2)} '
            'strokes ${strokes.length} usable ${strokes.where((s) => s.usable).length} '
            'turns ${athlete.target?.quarterTurns} ${athlete.ambiguous ? 'AMBIGUOUS ' : ''}${athlete.orientationSure ? '' : 'ORIENT? '}'
            'summary ${summary is AnalysisSuccess ? 'ok' : (summary as AnalysisFailure).error.errorCode}');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
