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
  PoseService({this.maxSampleRate = 15, this.maxSamples = maxPoseSamples, this.quarterTurns = 0});

  /// Frames per second analysed (clips are sampled down to this).
  final double maxSampleRate;
  final int maxSamples;

  /// Clockwise quarter-turns applied before tracking, for clips filmed
  /// sideways without rotation metadata (the person lies down in the
  /// picture). The file's own rotation metadata is always applied first.
  /// Not detected automatically: scoring each turn with the pose model
  /// alone picked wrong turns on upright clips with small or several
  /// people (Gurr evaluation); doing it reliably needs a person detector.
  final int quarterTurns;

  static final PoseService instance = PoseService();
  static const modelAsset = 'assets/models/pose_landmark_full.onnx';

  /// Progress of the running track (0..1), null when idle.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  BlazePose? _model;
  final Map<String, PoseTrack> _cache = {};

  Future<BlazePose> _load() async =>
      _model ??= BlazePose.load((await rootBundle.load(modelAsset)).buffer.asUint8List());

  /// The pose track for [clip] (cached per path and duration).
  /// [onLandmarks] receives each tracked frame's 2D landmarks in frame
  /// pixels (33 × x, y) — for overlays and diagnostics.
  Future<PoseTrack> track(ClipSource clip,
      {void Function(double progress)? onProgress,
      String? sourceKey,
      void Function(int frame, List<double> xy, int width, int height)? onLandmarks}) async {
    final key = '${sourceKey ?? clip.path}|${clip.durationMs}|${clip.fps}|$quarterTurns';
    final cached = _cache[key];
    if (cached != null && onLandmarks == null) return cached;
    final model = await _load();
    final grabber = await FrameGrabber.open(clip.path);
    if (grabber == null) return PoseTrack(fps: clip.fps, frames: const []);
    try {
      final n = clip.frameCount;
      var step = math.max(1, (clip.fps / maxSampleRate).round());
      step = math.max(step, (n / maxSamples).ceil());
      final frames = <PoseFrame>[];
      Roi? roi;
      final turns = quarterTurns % 4;
      for (var f = 0; f < n; f += step) {
        final img = await grabber.frameIndex(f, fps: clip.fps);
        if (img == null) continue;
        Future<BlazePoseOutput> infer(Roi r, int q) => model
            .infer(cropToInput(img.bgra, img.width, img.height, r, stride: img.stride, quarterTurns: q));
        BlazePoseOutput? out;
        final q = turns;
        final view = FrameView(img.width, img.height, q);
        roi ??= Roi.full(view.viewWidth, view.viewHeight);
        out ??= await infer(roi, q);
        if (out.presence < 0.5) {
          // Lost the body: search the whole frame again.
          roi = Roi.full(view.viewWidth, view.viewHeight);
          out = await infer(roi, q);
        }
        if (out.presence >= 0.5) {
          frames.add(poseFrameFromBlazePose(f, out.world, out.visibility, out.landmarkPresence));
          if (onLandmarks != null) {
            final r = roi;
            onLandmarks(
                f,
                [
                  for (var i = 0; i < 33; i++) ...() {
                    final (vx, vy) = r.toFrame(out!.landmarks[i * 5], out.landmarks[i * 5 + 1]);
                    final (x, y) = view.toFrame(vx, vy);
                    return [x, y];
                  }(),
                ],
                img.width,
                img.height);
          }
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
