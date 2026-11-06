import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart';

import '../data/database.dart';
import '../workspace/project.dart';
import 'athlete.dart';
import 'pose_service.dart';

typedef TrainingTrackLoader = Future<AthleteTrack> Function(ClipSource clip);

/// Reuse explicit choices made in a review; never silently choose between
/// conflicting reviews of the same file.
TrainingTrackLoader reviewedTrainingTrack(AppDatabase db) => (clip) async {
  final choices = <String, AthleteTarget>{};
  for (final row in await db.select(db.projectRows).get()) {
    final project = Project.fromJson(
      jsonDecode(row.json) as Map<String, Object?>,
    );
    for (final c in project.clips) {
      if (c.path == clip.path && c.athlete != null) {
        final target = AthleteTarget.fromJson(c.athlete!);
        choices[jsonEncode(target.toJson())] = target;
      }
    }
  }
  if (choices.length > 1) {
    throw AnalysisError(
      ErrorCode.lowPoseConfidence,
      'Reviews disagree about the athlete. Keep one selection, then retry.',
    );
  }
  return PoseService.instance.trackAthlete(
    clip,
    sourceKey: clip.clipId,
    target: choices.values.firstOrNull,
  );
};

Future<PoseTrack> trainingTrack(
  ClipSource clip, {
  TrainingTrackLoader? load,
}) async {
  final found =
      await (load ??
          (c) =>
              PoseService.instance.trackAthlete(c, sourceKey: c.clipId))(clip);
  if (found.ambiguous || !found.orientationSure || found.target == null) {
    throw AnalysisError(
      ErrorCode.lowPoseConfidence,
      'Choose the athlete in a review of this clip, then retry.',
    );
  }
  if (found.track.frames.isEmpty) {
    throw AnalysisError(
      ErrorCode.lowPoseConfidence,
      'No person could be found in this clip.',
    );
  }
  return found.track;
}
