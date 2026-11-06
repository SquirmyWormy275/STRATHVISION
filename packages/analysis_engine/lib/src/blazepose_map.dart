import 'dart:math' as math;

import 'body.dart';

/// BlazePose GHUM 3D landmark indices used by the body model.
const _bp = {
  Joint.leftShoulder: 11,
  Joint.rightShoulder: 12,
  Joint.leftElbow: 13,
  Joint.rightElbow: 14,
  Joint.leftWrist: 15,
  Joint.rightWrist: 16,
  Joint.leftHip: 23,
  Joint.rightHip: 24,
  Joint.leftKnee: 25,
  Joint.rightKnee: 26,
  Joint.leftAnkle: 27,
  Joint.rightAnkle: 28,
};

double _sigmoid(double x) => 1 / (1 + math.exp(-x));

/// One pose frame from BlazePose outputs: [world] is 39×3 metric
/// hip-centred landmarks (x right, y down, z toward the camera);
/// [visibility] and [presence] the 39 raw logits each. Converted to the
/// engine's root-relative frame (y up), with derived pelvis / spine / neck /
/// head.
///
/// Joint confidence = presence × (0.4 + 0.6 × visibility): a joint that is
/// in frame but hidden (behind the body, the implement) still has a usable
/// 3D estimate, so it scores 0.4 rather than near zero; a clearly visible
/// joint scores up to 1.
PoseFrame poseFrameFromBlazePose(int frame, List<double> world, List<double> visibility,
    [List<double>? presence]) {
  Vec3 at(int i) => Vec3(world[i * 3], -world[i * 3 + 1], world[i * 3 + 2]);
  double vis(int i) =>
      (presence == null ? 1.0 : _sigmoid(presence[i])) * (0.4 + 0.6 * _sigmoid(visibility[i]));
  final joints = <Joint, Vec3>{};
  final conf = <Joint, double>{};
  _bp.forEach((j, i) {
    joints[j] = at(i);
    conf[j] = vis(i);
  });
  Vec3 mid(Vec3 a, Vec3 b) => (a + b).scale(0.5);
  final hips = mid(at(23), at(24));
  final shoulders = mid(at(11), at(12));
  joints[Joint.pelvis] = hips;
  joints[Joint.spine] = mid(hips, shoulders);
  joints[Joint.neck] = shoulders;
  joints[Joint.head] = mid(at(7), at(8)); // ears
  conf[Joint.pelvis] = math.min(vis(23), vis(24));
  conf[Joint.spine] = math.min(conf[Joint.pelvis]!, math.min(vis(11), vis(12)));
  conf[Joint.neck] = math.min(vis(11), vis(12));
  conf[Joint.head] = math.max(vis(7), vis(8));
  return PoseFrame(frame: frame, joints: joints, confidence: conf);
}
