import 'dart:io';
import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

import 'real_pose_test.dart' show loadTrack;

void main() {
  test('missing-pose gaps cannot become long usable strokes', () async {
    final pack = PackDefinition.parse(
      File(
        '../../apps/strathvision/assets/packs/timber.json',
      ).readAsStringSync(),
    ).event('underhand')!.analysis;
    final original = loadTrack('cleave_pose.json');
    final separated = PoseTrack(
      fps: original.fps,
      frames: [
        ...original.frames,
        for (final frame in original.frames)
          PoseFrame(
            frame: frame.frame + 1200,
            joints: frame.joints,
            confidence: frame.confidence,
          ),
      ],
    );
    const clip = ClipSource(
      clipId: 'gap',
      path: '',
      durationMs: 50000,
      fps: 29.97,
    );
    final base = await analyzeContinuousTrack(pack, clip, original);
    final result = await analyzeContinuousTrack(pack, clip, separated);
    expect(base, isNotEmpty);
    expect(result, hasLength(base.length * 2));
    expect(
      result.every(
        (stroke) => stroke.endFrame < 1200 || stroke.startFrame >= 1200,
      ),
      isTrue,
    );
    expect(
      result.map((stroke) => stroke.index).toSet(),
      hasLength(result.length),
    );
    expect(
      result.fold<double>(0, (n, stroke) => n + stroke.seconds),
      lessThan(20),
    );
  });
}
