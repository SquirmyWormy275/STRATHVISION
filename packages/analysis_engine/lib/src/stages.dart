import 'dart:math' as math;

import 'body.dart';
import 'contracts.dart';
import 'errors.dart';
import 'pack.dart';

/// A clip to analyze. Video stays on the device; only its path is passed.
class ClipSource {
  const ClipSource({
    required this.clipId,
    required this.path,
    required this.durationMs,
    required this.fps,
  });

  final String clipId;
  final String path;
  final int durationMs;
  final double fps;

  int get frameCount => (durationMs * fps / 1000).floor();
}

// ------------------------------------------------------------ stage interfaces

/// Video → root-relative 3D full-body pose.
abstract class PoseEstimator {
  Future<PoseTrack> estimate(ClipSource clip);
}

/// Video (+ pose) → implement segment in the pose frame.
abstract class ImplementTracker {
  Future<ImplementTrack> track(ClipSource clip, PoseTrack pose);
}

/// Pose + implement → phase spans for the pack's phases.
/// Throws [AnalysisError] (PHASE_DETECTION_FAILED) when it cannot.
abstract class PhaseDetector {
  Map<String, PhaseSpan> detect(
      ClipSource clip, PoseTrack pose, ImplementTrack implement, AnalysisPack pack);
}

// ------------------------------------------------------- deterministic helpers

/// 32-bit FNV-1a. Same result on every platform.
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// mulberry32: small seeded PRNG with identical output on VM and web.
class SeededRandom {
  SeededRandom(int seed) : _s = seed & 0xffffffff;
  int _s;

  double next() {
    _s = (_s + 0x6D2B79F5) & 0xffffffff;
    var t = _s;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff;
    return ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296.0;
  }

  static int _imul(int a, int b) => (a * b) & 0xffffffff;
}

// --------------------------------------------------------------------- stubs

/// Rest positions for the stub skeleton (metres, y up, pelvis at origin).
const _rest = {
  Joint.pelvis: Vec3(0, 0, 0),
  Joint.spine: Vec3(0, 0.25, 0),
  Joint.neck: Vec3(0, 0.5, 0),
  Joint.head: Vec3(0, 0.65, 0),
  Joint.leftShoulder: Vec3(-0.18, 0.47, 0),
  Joint.leftElbow: Vec3(-0.22, 0.2, 0.05),
  Joint.leftWrist: Vec3(-0.2, -0.02, 0.15),
  Joint.rightShoulder: Vec3(0.18, 0.47, 0),
  Joint.rightElbow: Vec3(0.22, 0.2, 0.05),
  Joint.rightWrist: Vec3(0.2, -0.02, 0.15),
  Joint.leftHip: Vec3(-0.1, -0.02, 0),
  Joint.leftKnee: Vec3(-0.11, -0.45, 0.04),
  Joint.leftAnkle: Vec3(-0.11, -0.88, 0),
  Joint.rightHip: Vec3(0.1, -0.02, 0),
  Joint.rightKnee: Vec3(0.11, -0.45, 0.04),
  Joint.rightAnkle: Vec3(0.11, -0.88, 0),
};

/// Max pose samples per clip; long clips are sampled at a stride.
const maxPoseSamples = 1800;

/// Stub pose model (Phase 3). Produces a plausible, deterministic moving
/// skeleton seeded by the clip id. Does not read video. Replaced by a real
/// 3D pose model in Phase 4.
///
/// With [styleSeed], every clip shares one movement style (a synthetic
/// "coach") and varies from it by up to ±[jitter] (fraction) per clip.
/// Synthetic clips are allowed by the Phase 4 acceptance.
class StubPoseEstimator implements PoseEstimator {
  const StubPoseEstimator({
    this.confidence = 0.85,
    this.styleSeed,
    this.jitter = 0.03,
  });

  /// Mean joint confidence the stub reports.
  final double confidence;
  final int? styleSeed;
  final double jitter;

  @override
  Future<PoseTrack> estimate(ClipSource clip) async {
    final n = clip.frameCount;
    final stride = math.max(1, (n / maxPoseSamples).ceil());
    final clipRnd = SeededRandom(fnv1a(clip.clipId));
    final style = styleSeed == null ? clipRnd : SeededRandom(styleSeed!);
    double vary() =>
        styleSeed == null ? 1 : 1 + (clipRnd.next() * 2 - 1) * jitter;
    final phase = style.next() * 2 * math.pi * vary();
    final amp = (0.08 + style.next() * 0.08) * vary();
    final period = clip.fps * (1.2 + style.next()) * vary(); // frames per cycle
    final frames = <PoseFrame>[];
    for (var f = 0; f < n; f += stride) {
      final t = 2 * math.pi * f / period + phase;
      final s = math.sin(t), c = math.cos(t);
      final joints = <Joint, Vec3>{};
      _rest.forEach((j, p) {
        var q = p;
        switch (j) {
          case Joint.leftElbow || Joint.rightElbow:
            q = p + Vec3(0, amp * s, amp * c);
          case Joint.leftWrist || Joint.rightWrist:
            q = p + Vec3(0, 2.5 * amp * s, 2.5 * amp * c);
          case Joint.leftKnee || Joint.rightKnee:
            q = p + Vec3(0, 0.3 * amp * (1 + s), 0.6 * amp * (1 + s));
          case Joint.spine || Joint.neck || Joint.head:
            q = p + Vec3(0, 0, 0.5 * amp * (1 + c));
          default:
        }
        joints[j] = q;
      });
      final conf = {
        for (final j in Joint.values)
          j: (confidence + 0.05 * math.sin(t + j.index)).clamp(0.0, 1.0),
      };
      frames.add(PoseFrame(frame: f, joints: joints, confidence: conf));
    }
    return PoseTrack(fps: clip.fps, frames: frames);
  }
}

/// Stub implement tracker (Phase 3): a 0.8 m segment held in both hands,
/// following the wrists. Replaced by a real tracker later.
class StubImplementTracker implements ImplementTracker {
  const StubImplementTracker();

  @override
  Future<ImplementTrack> track(ClipSource clip, PoseTrack pose) async {
    return ImplementTrack(frames: [
      for (final p in pose.frames)
        () {
          final grip = (p.joints[Joint.leftWrist]! + p.joints[Joint.rightWrist]!)
              .scale(0.5);
          final dir = grip - p.joints[Joint.neck]!;
          final len = dir.length == 0 ? 1.0 : dir.length;
          return ImplementFrame(
            frame: p.frame,
            grip: grip,
            tip: grip + dir.scale(0.8 / len),
            confidence: 0.8,
          );
        }(),
    ]);
  }
}

/// Stub phase detector (Phase 3): splits the clip evenly across the pack's
/// phases with a fixed low confidence. Fails when a phase would be shorter
/// than the pack's minimum.
class StubPhaseDetector implements PhaseDetector {
  const StubPhaseDetector({this.confidence = 0.5});
  final double confidence;

  @override
  Map<String, PhaseSpan> detect(ClipSource clip, PoseTrack pose,
      ImplementTrack implement, AnalysisPack pack) {
    final n = clip.frameCount;
    final per = n ~/ pack.phases.length;
    if (n <= 0 || per < pack.minPhaseFrames || pose.frames.isEmpty) {
      throw AnalysisError(
        ErrorCode.phaseDetectionFailed,
        'The clip is too short to find every phase.',
        {
          'frame_count': n,
          'phase_count': pack.phases.length,
          'min_phase_frames': pack.minPhaseFrames,
        },
      );
    }
    return {
      for (var i = 0; i < pack.phases.length; i++)
        pack.phases[i]: PhaseSpan(
          startFrame: i * per,
          endFrame: i == pack.phases.length - 1 ? n - 1 : (i + 1) * per - 1,
          confidence: confidence,
        ),
    };
  }
}
