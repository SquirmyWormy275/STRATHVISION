// Replay native, private pose caches through a pinned engine/pack. No video
// decoding, identity inference, coach labels or profile editing occurs here.
import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln(
      'Usage: population_replay NATIVE_RESULT PRIVATE_TRACK PACK OUTPUT',
    );
    exitCode = 64;
    return;
  }
  final native = jsonDecode(await File(args[0]).readAsString()) as Map;
  final cache = jsonDecode(await File(args[1]).readAsString()) as Map;
  if (native['status'] != 'complete' ||
      cache['runtime_key'] != native['runtime_key'] ||
      cache['clip_sha256'] != native['clip_sha256'] ||
      cache['fps'] != native['fps']) {
    throw StateError('Native pose provenance mismatch');
  }
  final fps = (cache['fps'] as num).toDouble();
  final frames = <PoseFrame>[];
  for (final raw in cache['track'] as List) {
    final joints = <Joint, Vec3>{};
    for (final entry in (raw['j'] as Map).entries) {
      final joint = Joint.fromWire(entry.key);
      if (joint == null)
        throw FormatException('Unknown cached joint ${entry.key}');
      final xyz = entry.value as List;
      joints[joint] = Vec3(
        (xyz[0] as num).toDouble(),
        (xyz[1] as num).toDouble(),
        (xyz[2] as num).toDouble(),
      );
    }
    final confidence = <Joint, double>{};
    for (final entry in (raw['c'] as Map).entries) {
      final joint = Joint.fromWire(entry.key);
      if (joint == null)
        throw FormatException('Unknown cached confidence joint');
      confidence[joint] = (entry.value as num).toDouble();
    }
    frames.add(
      PoseFrame(frame: raw['f'] as int, joints: joints, confidence: confidence),
    );
  }
  final clip = ClipSource(
    clipId: 'sha256:${native['clip_sha256']}',
    path: '<precomputed private poses>',
    durationMs: ((native['duration_s'] as num) * 1000).round(),
    fps: fps,
  );
  final track = PoseTrack(fps: fps, frames: frames);
  final pack = PackDefinition.parse(await File(args[2]).readAsString());
  final counts = <String, Object?>{};
  final measurements = <String, Object?>{};
  for (final event in pack.events) {
    final strokes = await analyzeContinuousTrack(event.analysis, clip, track);
    counts[event.eventId] = {
      'candidate_strokes': strokes.length,
      'gate_passing_candidates': strokes.where((s) => s.usable).length,
      'gate_passing_seconds': strokes
          .where((s) => s.usable)
          .fold(0.0, (n, s) => n + s.seconds),
    };
    measurements[event.eventId] = [
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
  final output = File(args[3]);
  await output.parent.create(recursive: true);
  final temporary = File('${output.path}.pending');
  await temporary.writeAsString(
    jsonEncode({
      'format': 'gurr-pose-engine-replay/1',
      'engine_revision': const String.fromEnvironment('ENGINE_REVISION'),
      'clip_sha256': native['clip_sha256'],
      'native_runtime_key': native['runtime_key'],
      'pose_samples': frames.length,
      'fps': fps,
      'events': counts,
      'measurements': measurements,
      'learning_execution': 'not_run',
      'claimed_technique_improvement': false,
    }),
    flush: true,
  );
  await temporary.rename(output.path);
}
