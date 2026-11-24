import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/athlete_choices.dart';
import 'package:strathvision/vision/pose_service.dart';

// Models the pose service's documented source cache without native models.
// The UI-visible athlete must follow replacement bytes.
class _CachedPoseService extends PoseService {
  final _cache = <String, AthleteTrack>{};
  int extractions = 0;

  @override
  Future<AthleteTrack> trackAthlete(
    ClipSource clip, {
    void Function(double progress)? onProgress,
    String? sourceKey,
    AthleteTarget? target,
    void Function(int frame, List<double> xy, int width, int height)?
    onLandmarks,
  }) async {
    final key = sourceKey ?? clip.path;
    if (_cache[key] case final previous?) return previous;
    extractions++;
    final marker = await File(clip.path).readAsString();
    return _cache[key] = AthleteTrack(
      track: PoseTrack(fps: clip.fps, frames: const []),
      target: AthleteTarget(
        quarterTurns: 0,
        frame: 0,
        x: marker == 'left' ? 0.2 : 0.8,
        y: 0.5,
      ),
      ambiguous: false,
      orientationSure: true,
      candidatesFrame: 0,
      candidates: const [],
    );
  }
}

void main() {
  test(
    'Analyze re-extracts replaced footage at an unchanged file path',
    () async {
      final dir = await Directory.systemTemp.createTemp('analysis-source-');
      final file = File('${dir.path}/clip.mp4');
      final poses = _CachedPoseService();
      final athletes = AthleteChoices(targetFor: (_) => null);
      try {
        await file.writeAsString('left');
        final source = ClipSource(
          clipId: 'same-clip',
          path: file.path,
          durationMs: 1000,
          fps: 30,
        );
        final run = visionRunner(
          placeholderPack.analysisPack,
          poses: poses,
          athletes: athletes,
        );
        await run(source, const [], const {});
        expect(athletes.found(source.clipId)!.target!.x, 0.2);
        await run(source, const [], const {});
        expect(
          poses.extractions,
          1,
          reason: 'Unchanged footage may reuse its track.',
        );
        await file.writeAsString('rght'); // Same name, size, duration and fps.
        await run(source, const [], const {});
        expect(
          athletes.found(source.clipId)!.target!.x,
          0.8,
          reason: 'Replacement footage must not display the old athlete/track.',
        );
        expect(poses.extractions, 2);
      } finally {
        athletes.dispose();
        poses.progress.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
