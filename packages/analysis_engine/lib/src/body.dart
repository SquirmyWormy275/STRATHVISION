import 'dart:math' as math;

/// Generic full-body joint set (root-relative 3D). No sport-specific joints.
enum Joint {
  pelvis('pelvis'),
  spine('spine'),
  neck('neck'),
  head('head'),
  leftShoulder('left_shoulder'),
  leftElbow('left_elbow'),
  leftWrist('left_wrist'),
  rightShoulder('right_shoulder'),
  rightElbow('right_elbow'),
  rightWrist('right_wrist'),
  leftHip('left_hip'),
  leftKnee('left_knee'),
  leftAnkle('left_ankle'),
  rightHip('right_hip'),
  rightKnee('right_knee'),
  rightAnkle('right_ankle');

  const Joint(this.wire);
  final String wire;

  static Joint? fromWire(Object? s) {
    for (final j in values) {
      if (j.wire == s) return j;
    }
    return null;
  }
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 scale(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(dot(this));
}

/// Angle at [b] formed by a–b–c, degrees.
double angleDeg(Vec3 a, Vec3 b, Vec3 c) {
  final u = a - b, v = c - b;
  final n = u.length * v.length;
  if (n == 0) return 0;
  final cos = (u.dot(v) / n).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// One frame of root-relative 3D pose. y is up, metres, pelvis at origin.
class PoseFrame {
  const PoseFrame({
    required this.frame,
    required this.joints,
    required this.confidence,
  });

  /// Index into the clip's frames.
  final int frame;
  final Map<Joint, Vec3> joints;

  /// Per-joint confidence, 0..1.
  final Map<Joint, double> confidence;
}

class PoseTrack {
  const PoseTrack({required this.fps, required this.frames});
  final double fps;
  final List<PoseFrame> frames;

  /// Mean joint confidence over all frames.
  double get meanConfidence {
    if (frames.isEmpty) return 0;
    var sum = 0.0, n = 0;
    for (final f in frames) {
      for (final c in f.confidence.values) {
        sum += c;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }
}

/// Implement as a short rigid segment (grip → tip) in the same
/// root-relative frame as the pose.
class ImplementFrame {
  const ImplementFrame({
    required this.frame,
    required this.grip,
    required this.tip,
    required this.confidence,
  });

  final int frame;
  final Vec3 grip, tip;
  final double confidence;

  /// Inclination of grip→tip above horizontal, degrees (−90..90).
  double get inclinationDeg {
    final d = tip - grip;
    final horiz = math.sqrt(d.x * d.x + d.z * d.z);
    return math.atan2(d.y, horiz) * 180 / math.pi;
  }
}

class ImplementTrack {
  const ImplementTrack({required this.frames});
  final List<ImplementFrame> frames;
}
