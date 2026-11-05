import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

/// A flat swing (the tip never rises): rest at contact, slow move out to
/// the reach, fast swing back, stop. Sampled every 2 frames at 30 fps.
ImplementTrack flatSwings(int strokes, {bool glitch = false}) {
  final tips = <Vec3>[];
  for (var k = 0; k < strokes; k++) {
    for (var i = 0; i < 8; i++) {
      tips.add(const Vec3(1, 0, 0)); // in the material
    }
    for (var i = 1; i <= 10; i++) {
      // Out to the reach at x = -1, slowing into the turnaround.
      tips.add(Vec3(1 - 2 * math.sin(math.pi / 2 * i / 10), 0, 0));
    }
    for (var i = 1; i <= 3; i++) {
      tips.add(Vec3(-1 + 2 * i / 3, 0, 0)); // fast swing back
    }
  }
  for (var i = 0; i < 8; i++) {
    tips.add(const Vec3(1, 0, 0));
  }
  if (glitch) tips[4] = const Vec3(1, 2, 0); // one flipped forearm
  return ImplementTrack(frames: [
    for (var i = 0; i < tips.length; i++)
      ImplementFrame(frame: i * 2, grip: const Vec3(0, 0, 0), tip: tips[i], confidence: 1),
  ]);
}

void main() {
  test('contacts are found in flat swings that never rise', () {
    final imp = flatSwings(3);
    final stops = findStops(imp, 30);
    expect(stops.length, 3);
    // Each stop is just after a fast swing ends at x = 1.
    for (final s in stops) {
      expect(imp.frames[s].tip.x, closeTo(1, 1e-9));
    }
    final spans = segmentStrokesByStops(imp, 30);
    expect(spans.length, 3);
    for (var k = 1; k < spans.length; k++) {
      expect(spans[k].$1, greaterThan(spans[k - 1].$2));
    }
  });

  test('a single-sample glitch is removed and is not a contact', () {
    final imp = flatSwings(2, glitch: true);
    expect(despikedTips(imp)[4].y, closeTo(0, 1e-9));
    expect(findStops(imp, 30).length, 2);
  });

  test('reach and stop phases on a flat swing', () async {
    final imp = flatSwings(1);
    final n = imp.frames.length;
    final pack = AnalysisPack(
      packId: 't',
      eventId: 'e',
      metricSchemaVersion: '1',
      phases: const ['setup', 'backswing', 'downswing', 'entry', 'recovery'],
      criticalPhases: const ['downswing'],
      metrics: const [],
      phaseEvents: const ['rise', 'reach', 'stop', 'release'],
      minPhaseFrames: 2,
    );
    final clip = ClipSource(clipId: 'c', path: '/x', durationMs: (n * 2 / 30 * 1000).round(), fps: 30);
    final phases = const EventPhaseDetector()
        .detect(clip, const PoseTrack(fps: 30, frames: []), imp, pack);
    // Reach: the turnaround at x = -1 (sample 17, frame 34); contact at
    // the end of the swing back.
    expect(phases['downswing']!.startFrame, inInclusiveRange(32, 36));
    // The swing arrives at frame 40 and the tip is still by 42: contact
    // is placed between them.
    expect(phases['entry']!.startFrame, inInclusiveRange(40, 42));
    expect(phases['backswing']!.startFrame, lessThanOrEqualTo(18));
  });
}
