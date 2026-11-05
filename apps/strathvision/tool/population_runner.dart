// Private full-recording native runner. Build once in release mode; launch one
// process per recording. Inputs, poses and measurements stay outside the repo.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/pose_service.dart';
import 'package:strathvision/workbench/carne_athletes.dart';

Future<void> atomicJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.pending');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

Map<String, Object?> selection(AthleteTrack value) => {
  'target': value.target?.toJson(),
  'ambiguous': value.ambiguous,
  'orientation_sure': value.orientationSure,
  'candidate_count': value.candidates.length,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final env = Platform.environment;
  final document =
      jsonDecode(await File(env['SV_POP_INPUT']!).readAsString()) as Map;
  final row =
      (document['clips'] as List)[int.parse(env['SV_POP_INDEX']!)] as Map;
  final directory = Directory('${env['SV_POP_OUTPUT']}/${row['sha256']}');
  await directory.create(recursive: true);
  final resultFile = File('${directory.path}/result.json');
  final key = env['SV_POP_RUNTIME_KEY']!;
  final clock = Stopwatch()..start();
  final source = File(row['path'] as String);
  final base = <String, Object?>{
    'format': 'gurr-population-clip/1',
    'runtime_key': key,
    'clip_sha256': row['sha256'],
    'source_name': row['relative_path'],
    'inventory_duration_s': row['duration_s'],
    'supported_event_hint': row['supported_event_hint'],
    'event_hint_provenance': row['event_hint_provenance'],
  };
  try {
    if ((await sha256.bind(source.openRead()).first).toString() !=
        row['sha256']) {
      throw StateError('Source content changed');
    }
    final info = await probeClip(source.path);
    if (info == null) {
      throw StateError('Native decoder could not open recording');
    }
    final clip = ClipSource(
      clipId: 'sha256:${row['sha256']}',
      path: source.path,
      durationMs: info.durationMs,
      fps: info.fps,
    );
    final service = PoseService(maxSampleRate: 30, maxSamples: 90000);
    final state = CarneAthleteState();
    var deferred = false;
    Map<String, Object?>? preflight;
    var lastProgress = 0.0, lastLogMs = -5000;
    final sparseXY = <Map<String, Object?>>[];
    var lastXY = -1000000;
    Future<AthleteTrack> load(ClipSource source, AthleteTarget? target) async {
      final full = source.durationMs == clip.durationMs;
      final result = await service.trackAthlete(
        source,
        sourceKey: source.clipId,
        target: target,
        onProgress: (p) {
          if (full) lastProgress = math.max(lastProgress, p);
          if (clock.elapsedMilliseconds - lastLogMs > 5000) {
            lastLogMs = clock.elapsedMilliseconds;
            final progress = {
              ...base,
              'status': full ? 'tracking' : 'selection',
              'fraction': full ? lastProgress : p,
              'elapsed_s': clock.elapsedMilliseconds / 1000,
            };
            // Synchronous replacement prevents concurrent progress writes.
            final f = File('${directory.path}/progress.pending');
            f.writeAsStringSync(jsonEncode(progress));
            f.renameSync('${directory.path}/progress.json');
          }
        },
        onLandmarks: full
            ? (frame, xy, width, height) {
                if (frame - lastXY >= clip.fps) {
                  sparseXY.add({
                    'frame': frame,
                    'xy': xy,
                    'size': [width, height],
                  });
                  lastXY = frame;
                }
              }
            : null,
      );
      if (!full) preflight = selection(result);
      return result;
    }

    AthleteTrack athlete;
    try {
      athlete = await loadCarneTrack(clip, state, load: load);
    } on CarneAthleteChoiceNeeded {
      deferred = true;
      // Diagnostic coverage continues despite the production selection gate.
      // Its measurements remain quarantined from the production-eligible pile.
      athlete = await load(clip, null);
    }
    final track = athlete.track;
    final step = math.max(
      math.max(1, (clip.fps / 30).round()),
      (clip.frameCount / 90000).ceil(),
    );
    final expected = (clip.frameCount / step).ceil();
    var longestGapFrames = track.frames.isEmpty
        ? clip.frameCount
        : track.frames.first.frame;
    var previous = -step;
    for (final frame in track.frames) {
      longestGapFrames = math.max(
        longestGapFrames,
        frame.frame - previous - step,
      );
      previous = frame.frame;
    }
    longestGapFrames = math.max(
      longestGapFrames,
      clip.frameCount - previous - step,
    );
    final definition = PackDefinition.parse(
      await rootBundle.loadString('assets/packs/timber.json'),
    );
    final events = <String, Object?>{};
    final measurements = <String, Object?>{};
    for (final id in ['underhand', 'standing_block']) {
      final strokes = await analyzeContinuousTrack(
        definition.event(id)!.analysis,
        clip,
        track,
      );
      final reasons = <String, int>{};
      for (final s in strokes) {
        for (final reason in s.issues) {
          reasons.update(reason.name, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      final eligible =
          !deferred &&
          !athlete.ambiguous &&
          athlete.orientationSure &&
          athlete.target != null &&
          row['supported_event_hint'] == id;
      events[id] = {
        'candidate_strokes': strokes.length,
        'gate_passing_candidates': strokes.where((s) => s.usable).length,
        'gate_passing_seconds': strokes
            .where((s) => s.usable)
            .fold(0.0, (n, s) => n + s.seconds),
        'production_eligible_strokes': eligible
            ? strokes.where((s) => s.usable).length
            : 0,
        'issues': reasons,
        'event_assignment_reviewed': false,
      };
      measurements[id] = [
        for (final s in strokes)
          {
            'start_frame': s.startFrame,
            'end_frame': s.endFrame,
            'usable': s.usable,
            'phase_pose_confidence': s.detail.phasePoseConfidence,
            'implement_dropout_s': s.dropoutSeconds,
            'measurement': s.detail.outcome.toJson(),
            'issues': [for (final issue in s.issues) issue.name],
          },
      ];
    }
    await atomicJson(File('${directory.path}/private-track.json'), {
      'format': 'gurr-private-pose/1',
      'runtime_key': key,
      'clip_sha256': row['sha256'],
      'fps': clip.fps,
      'track': [
        for (final f in track.frames)
          {
            'f': f.frame,
            'j': {
              for (final e in f.joints.entries)
                e.key.wire: [e.value.x, e.value.y, e.value.z],
            },
            'c': {for (final e in f.confidence.entries) e.key.wire: e.value},
          },
      ],
      'sparse_landmarks': sparseXY,
    });
    await atomicJson(
      File('${directory.path}/private-measurements.json'),
      measurements,
    );
    await atomicJson(resultFile, {
      ...base,
      'status': 'complete',
      'duration_s': clip.durationMs / 1000,
      'fps': clip.fps,
      'expected_sample_count': expected,
      'pose_samples': track.frames.length,
      'mean_joint_confidence': track.meanConfidence,
      'pose_presence_fraction': expected == 0
          ? 0
          : track.frames.length / expected,
      'last_progress_fraction': lastProgress,
      'full_span_reached': lastProgress >= 1 - step / clip.frameCount,
      'last_pose_time_s': track.frames.isEmpty
          ? null
          : track.frames.last.frame / clip.fps,
      'longest_missing_pose_s': longestGapFrames / clip.fps,
      'production_deferred': deferred,
      'preflight': preflight,
      'production_selection': state.found[clip.clipId] == null
          ? null
          : selection(state.found[clip.clipId]!),
      'diagnostic_selection': selection(athlete),
      'events': events,
      'elapsed_s': clock.elapsedMilliseconds / 1000,
      'genuine_judgments': 0,
      'accepted_edits': 0,
      'learning_execution': 'not_run_no_reviewed_coach_profile_or_feedback',
      'claimed_technique_improvement': false,
    });
    // ignore: avoid_print
    print(
      'POPULATION complete ${row['relative_path']} poses=${track.frames.length}/$expected deferred=$deferred elapsed=${clock.elapsedMilliseconds / 1000}',
    );
    exit(0);
  } catch (error, stack) {
    await atomicJson(resultFile, {
      ...base,
      'status': 'failed',
      'error': error.toString(),
      'elapsed_s': clock.elapsedMilliseconds / 1000,
    });
    // ignore: avoid_print
    print('$error\n$stack');
    exit(1);
  }
}
