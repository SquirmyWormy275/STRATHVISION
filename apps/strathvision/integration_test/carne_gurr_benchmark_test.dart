// Private real-video benchmark. Windows/frames stay local; aggregate output
// contains no pixels or per-frame poses. Frozen old references are diagnostic.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/vision/pose_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('native selected-athlete and contact benchmark on frozen windows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const input = String.fromEnvironment('WINDOWS');
      const output = String.fromEnvironment('OUT');
      expect(input, isNotEmpty);
      expect(output, isNotEmpty);
      final document = jsonDecode(await File(input).readAsString()) as Map;
      final definition = PackDefinition.parse(
        await rootBundle.loadString('assets/packs/timber.json'),
      );
      final rows = <Map<String, Object?>>[];
      final service = PoseService(maxSampleRate: 30, maxSamples: 90000);
      final file = File(output);
      await file.parent.create(recursive: true);
      Future<void> checkpoint({required bool complete}) => file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'format': 'gurr-native-benchmark/1', 'source_revision': const String.fromEnvironment('STRATHVISION_REVISION', defaultValue: 'unrecorded'), 'input_sha256': sha256.convert(File(input).readAsBytesSync()).toString(), 'complete': complete, 'expected_windows': (document['windows'] as List).length, 'windows': rows})}\n',
      );
      for (final raw in document['windows'] as List) {
        final row = raw as Map;
        final file = File(row['prepared_path'] as String);
        final info = await probeClip(file.path);
        expect(info, isNotNull);
        final clip = ClipSource(
          clipId: 'sha256:${row['clip_sha256']}',
          path: file.path,
          durationMs: info!.durationMs,
          fps: info.fps,
        );
        final xy = <int, List<double>>{};
        var width = 0, height = 0;
        final sw = Stopwatch()..start();
        final result = await service.trackAthlete(
          clip,
          sourceKey: '${clip.clipId}:${row['start_s']}:${row['duration_s']}',
          onLandmarks: (f, points, w, h) {
            xy[f] = points;
            width = w;
            height = h;
          },
        );
        final paused = result.ambiguous || !result.orientationSure;
        final pack = definition.event(row['event_id'] as String)!.analysis;
        final strokes = paused
            ? <StrokeDetail>[]
            : await analyzeContinuousTrack(pack, clip, result.track);
        final contacts = <double>[];
        for (final s in strokes) {
          final outcome = s.detail.outcome;
          if (outcome is AnalysisSuccess) {
            final entry = outcome.vector.phases['entry'];
            if (entry != null) contacts.add(entry.startFrame / clip.fps);
          }
        }
        final errors = <Map<String, Object?>>[];
        for (final anchor in (row['target_anchors'] as List)) {
          if (anchor['visible'] != true) continue;
          final t = (anchor['time_s'] as num).toDouble();
          final keys = xy.keys.toList()
            ..sort(
              (a, b) =>
                  (a / clip.fps - t).abs().compareTo((b / clip.fps - t).abs()),
            );
          if (paused ||
              keys.isEmpty ||
              (keys.first / clip.fps - t).abs() > 1 / clip.fps) {
            errors.add({'time_s': t, 'error_frame_diagonal': null});
            continue;
          }
          var x = (anchor['point'][0] as num).toDouble(),
              y = (anchor['point'][1] as num).toDouble();
          final rotation = row['reference_rotation_cw'] as int;
          for (var k = 0; k < (360 - rotation) % 360 ~/ 90; k++) {
            final old = x;
            x = 1 - y;
            y = old;
          }
          final points = xy[keys.first]!;
          final px =
              [11, 12, 23, 24].fold(0.0, (s, j) => s + points[j * 2]) / 4;
          final py =
              [11, 12, 23, 24].fold(0.0, (s, j) => s + points[j * 2 + 1]) / 4;
          final error =
              math.sqrt(
                math.pow(px - x * width, 2) + math.pow(py - y * height, 2),
              ) /
              math.sqrt(width * width + height * height);
          errors.add({'time_s': t, 'error_frame_diagonal': error});
        }
        rows.add({
          'window_id': row['window_id'],
          'clip_sha256': row['clip_sha256'],
          'prepared_clip_sha256': (await sha256.bind(file.openRead()).first)
              .toString(),
          'sample_rate_limit': 30,
          'pose_samples': result.track.frames.length,
          'paused_for_selection': paused,
          'ambiguous': result.ambiguous,
          'orientation_sure': result.orientationSure,
          'orientation_correct':
              result.target != null &&
              result.target!.quarterTurns * 90 == row['reference_rotation_cw'],
          'torso_errors': errors,
          'contact_times_s': contacts,
          'candidate_strokes': strokes.length,
          'usable_strokes': strokes.where((s) => s.usable).length,
          'elapsed_s': sw.elapsedMilliseconds / 1000,
        });
        await checkpoint(complete: false);
        // ignore: avoid_print
        print(
          'NATIVE ${row['window_id']}: ${result.track.frames.length} poses; pause=$paused; ${strokes.length} strokes',
        );
      }
      await checkpoint(complete: true);
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
