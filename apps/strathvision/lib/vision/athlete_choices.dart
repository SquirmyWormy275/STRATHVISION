import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';

import 'athlete.dart';
import 'pose_service.dart';

/// Who is analysed in each clip: the saved choice (read through
/// [targetFor]) and what the tracker found last time (for the panel's
/// "Wrong person?" and its question when unsure).
class AthleteChoices extends ChangeNotifier {
  AthleteChoices({required this.targetFor, this.loadPeople});

  /// The user's saved choice for a clip, null when automatic.
  final AthleteTarget? Function(String clipId) targetFor;

  /// Frame loader for the picker (null: the pose service's).
  final PeopleLoader? loadPeople;

  final Map<String, AthleteTrack> _found = {};
  final Map<String, ClipSource> _sources = {};

  /// The last tracking result for a clip, and the clip it was run on.
  AthleteTrack? found(String clipId) => _found[clipId];
  ClipSource? source(String clipId) => _sources[clipId];

  void record(ClipSource clip, AthleteTrack track) {
    _found[clip.clipId] = track;
    _sources[clip.clipId] = clip;
    notifyListeners();
  }

  /// The tracker could not tell who the athlete is and the user has not
  /// chosen: the panel asks.
  bool needsChoice(String clipId) =>
      targetFor(clipId) == null && (_found[clipId]?.ambiguous ?? false);
}
