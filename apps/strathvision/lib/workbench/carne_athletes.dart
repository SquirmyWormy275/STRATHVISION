import 'package:analysis_engine/analysis_engine.dart';

import '../vision/athlete.dart';
import '../vision/pose_service.dart';

/// Desktop ingestion must retain swing timing on long recordings. The normal
/// review budget of 1,800 samples would thin a 28-minute source below 2 Hz.
final carnePoseService = PoseService(maxSampleRate: 30, maxSamples: 90000);

class CarneAthleteState {
  final Map<String, AthleteTarget> targets = {};
  final Map<String, AthleteTrack> found = {};
  final Map<String, ClipSource> clips = {};

  void record(ClipSource clip, AthleteTrack result) {
    clips[clip.clipId] = clip;
    found[clip.clipId] = result;
  }

  Map<String, Object?>? metadata(String clipId) {
    final result = found[clipId];
    if (result == null) return null;
    return {
      'selection': targets.containsKey(clipId) ? 'user' : 'automatic',
      'target': result.target?.toJson(),
      'ambiguous': result.ambiguous,
      'orientation_sure': result.orientationSure,
      'candidate_frame': result.candidatesFrame,
      'candidate_count': result.candidates.length,
    };
  }
}

class CarneAthleteChoiceNeeded implements Exception {
  const CarneAthleteChoiceNeeded(this.clip, this.result);
  final ClipSource clip;
  final AthleteTrack result;
}
