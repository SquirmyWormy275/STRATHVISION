import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'blazepose.dart';
import 'frame_grabber.dart';
import 'pose_math.dart';

/// Turns a clip into a real 3D pose track on this device: decode frames,
/// track the body region, run BlazePose, map to the engine's joints.
class PoseService {
  PoseService({this.maxSampleRate = 15, this.maxSamples = maxPoseSamples});

  /// Frames per second analysed (clips are sampled down to this).
  final double maxSampleRate;
  final int maxSamples;

  static final PoseService instance = PoseService();
  static const modelAsset = 'assets/models/pose_landmark_full.onnx';

  /// Progress of the running track (0..1), null when idle.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  BlazePose? _model;
  final Map<String, PoseTrack> _cache = {};

  Future<BlazePose> _load() async =>
      _model ??= BlazePose.load((await rootBundle.load(modelAsset)).buffer.asUint8List());

  /// The pose track for [clip] (cached per path and duration).
  Future<PoseTrack> track(ClipSource clip, {void Function(double progress)? onProgress, String? sourceKey}) async {
    final key = '${sourceKey ?? clip.path}|${clip.durationMs}|${clip.fps}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final model = await _load();
    final grabber = await FrameGrabber.open(clip.path);
    if (grabber == null) return PoseTrack(fps: clip.fps, frames: const []);
    try {
      final n = clip.frameCount;
      var step = math.max(1, (clip.fps / maxSampleRate).round());
      step = math.max(step, (n / maxSamples).ceil());
      final frames = <PoseFrame>[];
      Roi? roi;
      for (var f = 0; f < n; f += step) {
        final img = await grabber.frameIndex(f, fps: clip.fps);
        if (img == null) continue;
        roi ??= Roi.full(img.width, img.height);
        var out = await model.infer(cropToInput(img.bgra, img.width, img.height, roi));
        if (out.presence < 0.5) {
          // Lost the body: search the whole frame again.
          roi = Roi.full(img.width, img.height);
          out = await model.infer(cropToInput(img.bgra, img.width, img.height, roi));
        }
        if (out.presence >= 0.5) {
          frames.add(poseFrameFromBlazePose(f, out.world, out.visibility, out.landmarkPresence));
          roi = roiFromLandmarks(out.landmarks, roi);
        } else {
          roi = null;
        }
        onProgress?.call((f + 1) / n);
        progress.value = (f + 1) / n;
      }
      final t = PoseTrack(fps: clip.fps, frames: frames);
      if (_cache.length > 32) _cache.remove(_cache.keys.first);
      _cache[key] = t;
      return t;
    } finally {
      progress.value = null;
      await grabber.close();
    }
  }
}
