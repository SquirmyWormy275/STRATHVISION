import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/person_detector.dart';

/// Pose landmarks (39 × 5) with shoulders, hips and wrists placed; the
/// body's up direction at [angle] degrees from vertical.
List<double> body({double angle = 0, double wristX = 0, double wristY = -0.5}) {
  final lm = List<double>.filled(39 * 5, 0);
  final a = angle * math.pi / 180;
  // Body coordinates: hips at (0, 0), shoulders 1 torso up, image y down.
  (double, double) at(double bx, double by) =>
      (128 + 50 * (bx * math.cos(a) - by * math.sin(a)), 128 + 50 * (bx * math.sin(a) + by * math.cos(a)));
  void put(int i, double bx, double by) {
    final (x, y) = at(bx, by);
    lm[i * 5] = x;
    lm[i * 5 + 1] = y;
  }

  put(23, -0.2, 0);
  put(24, 0.2, 0);
  put(11, -0.25, -1);
  put(12, 0.25, -1);
  put(15, wristX - 0.05, wristY);
  put(16, wristX + 0.05, wristY);
  return lm;
}

const box = PersonBox(0.4, 0.2, 0.6, 0.9, 0.8);

void main() {
  test('upright people score high; sideways or upside-down score zero', () {
    expect(uprightScore(box, 1, body()), closeTo(0.8, 1e-9));
    expect(uprightScore(box, 1, body(angle: 20)), greaterThan(0.5));
    expect(uprightScore(box, 1, body(angle: 90)), closeTo(0, 1e-9));
    expect(uprightScore(box, 1, body(angle: 180)), 0);
    expect(uprightScore(box, 0.1, body()), closeTo(0.08, 1e-9));
  });

  test('orientation: unturned unless a turn is clearly better', () {
    expect(chooseOrientation({0: 4.0, 1: 0.1, 3: 0.2}), (quarterTurns: 0, sure: true));
    expect(chooseOrientation({0: 0.1, 1: 0.2, 3: 3.7}), (quarterTurns: 3, sure: true));
    expect(chooseOrientation({0: 0.6, 1: 0.0, 3: 0.9}), (quarterTurns: 0, sure: false));
    // Both turns plausible: pick the better, but not sure.
    expect(chooseOrientation({0: 0.0, 1: 0.83, 3: 0.73}), (quarterTurns: 1, sure: false));
    expect(chooseOrientation({0: 0.0, 1: 0.0, 3: 0.0}), (quarterTurns: 0, sure: false));
  });

  List<Candidate> scene({required bool twoChoppers}) {
    final cs = <Candidate>[];
    for (var f = 0; f < 20; f++) {
      final swing = math.sin(f * 0.9) * 1.2; // hands travel ~2 torso lengths
      final boxes = [
        // The chopper, framed by the camera (or two, framed alike).
        twoChoppers ? const PersonBox(0.20, 0.20, 0.40, 0.90, 0.8) : const PersonBox(0.40, 0.20, 0.60, 0.90, 0.8),
        const PersonBox(0.02, 0.30, 0.12, 0.80, 0.7), // spectator at the edge, still
        const PersonBox(0.70, 0.60, 0.95, 0.99, 0.5), // camp chair: no pose
        if (twoChoppers) const PersonBox(0.60, 0.20, 0.80, 0.90, 0.8),
        // A half-seen passer-by with jittery pose (only some samples).
        if (f % 4 == 0) const PersonBox(0.45, 0.05, 0.50, 0.20, 0.3),
      ];
      final pres = [0.95, 0.9, 0.02, if (twoChoppers) 0.9, if (f % 4 == 0) 0.6];
      final wrists = <(double, double)?>[
        (swing, -0.5 + swing.abs()),
        (0.01 * (f % 2), -0.4),
        null,
        if (twoChoppers) (-swing, -0.5 + swing.abs()),
        if (f % 4 == 0) (f.isEven ? 2.0 : -2.0, f % 8 == 0 ? 2.0 : -2.0),
      ];
      linkDetections(cs, f * 3, boxes, pres, wrists);
    }
    return cs;
  }

  test('the framed chopper is picked over a spectator, an object and a passer-by', () {
    final cs = scene(twoChoppers: false);
    final r = pickAthlete(cs, 20);
    expect(r.pick!.boxAt(0)!.cx, closeTo(0.5, 1e-9));
    expect(r.ambiguous, isFalse);
  });

  test('two choppers framed alike is ambiguous; a tap selects one', () {
    final cs = scene(twoChoppers: true);
    expect(pickAthlete(cs, 20).ambiguous, isTrue);
    final tapped = selectByPoint(cs, 30, 0.72, 0.5)!;
    expect(tapped.boxAt(30)!.x1, 0.60);
    // A tap outside every box takes the nearest person.
    expect(selectByPoint(cs, 30, 0.0, 0.1)!.boxAt(30)!.x1, 0.02);
  });

  test('a swinging chopper stays one person even as their box changes shape', () {
    final cs = <Candidate>[];
    for (var f = 0; f < 12; f++) {
      // Box widens and narrows with the axe: low overlap between samples.
      final wide = f.isEven;
      final chopper = wide ? const PersonBox(0.20, 0.10, 0.60, 0.95, 0.8) : const PersonBox(0.30, 0.15, 0.45, 0.95, 0.8);
      linkDetections(cs, f, [chopper, const PersonBox(0.85, 0.1, 1.0, 0.95, 0.7)], const [0.9, 0.9],
          [((wide ? 1.0 : -1.0), -0.5), (0.0, -0.4)]);
    }
    expect(cs.length, 2);
    expect(pickAthlete(cs, 12).pick!.boxAt(0)!.x1, 0.20);
  });

  test('an onlooker cut off by the edge loses to the chopper even with jumpy hands', () {
    final cs = <Candidate>[];
    for (var f = 0; f < 20; f++) {
      linkDetections(cs, f, const [
        PersonBox(0.21, 0.11, 0.53, 0.98, 0.8), // chopper, barely swinging yet
        PersonBox(0.82, 0.10, 1.00, 0.97, 0.8), // onlooker at the right edge
      ], const [0.95, 0.9], [
        (0.2 * math.sin(f.toDouble()), -0.5),
        (1.5 * math.sin(f * 2.0), 0.7 * math.cos(f * 3.0)), // unreliable hands
      ]);
    }
    expect(pickAthlete(cs, 20).pick!.boxAt(0)!.x1, 0.21);
  });

  test('nobody seen enough is ambiguous with no pick', () {
    final cs = <Candidate>[];
    linkDetections(cs, 0, const [PersonBox(0.4, 0.2, 0.6, 0.9, 0.8)], const [0.9], const [(0.0, 0.0)]);
    expect(pickAthlete(cs, 20), (pick: null, ambiguous: true));
  });

  test('wrists relative to hips are in torso lengths', () {
    final (x, y) = wristsFromHips(body(wristX: 0.5, wristY: -1.5))!;
    expect(x, closeTo(0.5 * 50 / math.sqrt(50 * 50 + 0), 0.05));
    expect(y, closeTo(-1.5, 0.05));
  });

  test('targets round-trip through JSON', () {
    const t = AthleteTarget(quarterTurns: 3, frame: 42, x: 0.25, y: 0.75);
    expect(AthleteTarget.fromJson(t.toJson()), t);
  });
}
