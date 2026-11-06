import 'body.dart';
import 'engine.dart';
import 'pack.dart';
import 'stages.dart';
import 'strokes.dart';
import 'vision_stages.dart';

/// Missing pose is missing evidence. Never segment a stroke across an
/// occlusion, lost track, or camera cut represented by a sampling gap.
Future<List<StrokeDetail>> analyzeContinuousTrack(
  AnalysisPack pack,
  ClipSource clip,
  PoseTrack track, {
  double maxGapSeconds = .6,
}) async {
  final groups = <List<PoseFrame>>[];
  for (final frame in track.frames) {
    if (groups.isEmpty ||
        (frame.frame - groups.last.last.frame) / track.fps > maxGapSeconds) {
      groups.add([]);
    }
    if (groups.last.isNotEmpty && frame.frame <= groups.last.last.frame) {
      throw ArgumentError('Pose frames must be strictly increasing');
    }
    groups.last.add(frame);
  }
  final out = <StrokeDetail>[];
  for (final group in groups.where((g) => g.length >= 10)) {
    final strokes = await AnalysisEngine(
      pack: pack,
      pose: PrecomputedPoseEstimator(PoseTrack(fps: track.fps, frames: group)),
      implement: const GripImplementTracker(),
      phases: const EventPhaseDetector(),
    ).analyzeStrokes(clip);
    for (final stroke in strokes) {
      out.add(
        StrokeDetail(
          clipId: clip.clipId,
          index: out.length,
          startFrame: stroke.startFrame,
          endFrame: stroke.endFrame,
          fps: stroke.fps,
          detail: stroke.detail,
          dropoutSeconds: stroke.dropoutSeconds,
          clipDropoutSeconds: stroke.clipDropoutSeconds,
          pack: pack,
        ),
      );
    }
  }
  return out;
}
