import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'blazepose.dart';
import 'frame_grabber.dart';
import 'pose_math.dart';

/// Detector input size (YOLOX-Nano).
const detectorInputSize = 416;

/// A person found in a frame: corners in 0..1 of the (turned) view, and the
/// detector's confidence.
class PersonBox {
  const PersonBox(this.x1, this.y1, this.x2, this.y2, this.score);
  final double x1, y1, x2, y2, score;

  double get width => x2 - x1;
  double get height => y2 - y1;
  double get cx => (x1 + x2) / 2;
  double get cy => (y1 + y2) / 2;
  bool contains(double x, double y) => x >= x1 && x <= x2 && y >= y1 && y <= y2;

  double iou(PersonBox o) {
    final iw = math.max(0.0, math.min(x2, o.x2) - math.max(x1, o.x1));
    final ih = math.max(0.0, math.min(y2, o.y2) - math.max(y1, o.y1));
    final inter = iw * ih;
    final union = width * height + o.width * o.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  Map<String, Object?> toJson() => {'box': [x1, y1, x2, y2], 'score': score};
  factory PersonBox.fromJson(Map<String, Object?> j) {
    final b = [for (final v in j['box']! as List) (v as num).toDouble()];
    return PersonBox(b[0], b[1], b[2], b[3], (j['score'] as num?)?.toDouble() ?? 1);
  }

  @override
  String toString() =>
      'PersonBox(${x1.toStringAsFixed(3)}, ${y1.toStringAsFixed(3)}, ${x2.toStringAsFixed(3)}, ${y2.toStringAsFixed(3)}, ${score.toStringAsFixed(2)})';
}

/// The model input for a frame: the (turned) view scaled to fit 416×416,
/// top-left aligned, padded with grey 114; BGR, CHW, 0..255 (YOLOX's own
/// preprocessing). Returns the input and the scale from view pixels to
/// input pixels.
(Float32List, double) detectorInput(Uint8List bgra, int width, int height,
    {int? stride, int quarterTurns = 0}) {
  const n = detectorInputSize;
  final view = FrameView(width, height, quarterTurns);
  final ratio = math.min(n / view.viewWidth, n / view.viewHeight);
  final rowBytes = stride ?? width * 4;
  final out = Float32List(3 * n * n)..fillRange(0, 3 * n * n, 114);
  final w = (view.viewWidth * ratio).floor(), h = (view.viewHeight * ratio).floor();
  // Per-axis scale from the integer target size, as OpenCV's resize does.
  final scaleX = view.viewWidth / w, scaleY = view.viewHeight / h;
  for (var y = 0; y < h; y++) {
    final vy = (y + 0.5) * scaleY;
    for (var x = 0; x < w; x++) {
      final (sx, sy) = view.toFrame((x + 0.5) * scaleX, vy);
      final fx = sx - 0.5, fy = sy - 0.5;
      final x0 = fx.floor(), y0 = fy.floor();
      final wx = fx - x0, wy = fy - y0;
      for (var c = 0; c < 3; c++) {
        double px(int xx, int yy) {
          xx = xx.clamp(0, width - 1);
          yy = yy.clamp(0, height - 1);
          return bgra[yy * rowBytes + xx * 4 + c].toDouble(); // B, G, R
        }

        out[c * n * n + y * n + x] = px(x0, y0) * (1 - wx) * (1 - wy) +
            px(x0 + 1, y0) * wx * (1 - wy) +
            px(x0, y0 + 1) * (1 - wx) * wy +
            px(x0 + 1, y0 + 1) * wx * wy;
      }
    }
  }
  return (out, ratio);
}

/// Decodes YOLOX output (3549 × 85, strides 8/16/32 on 416) into person
/// boxes above [threshold], in 0..1 of a view [viewWidth] × [viewHeight]
/// that was scaled by [ratio], then removes overlaps (IoU ≥ 0.45).
List<PersonBox> decodePersons(List<double> raw, double ratio, int viewWidth, int viewHeight,
    {double threshold = 0.4}) {
  const n = detectorInputSize;
  final boxes = <PersonBox>[];
  var row = 0;
  for (final s in const [8, 16, 32]) {
    final g = n ~/ s;
    for (var gy = 0; gy < g; gy++) {
      for (var gx = 0; gx < g; gx++, row++) {
        final o = row * 85;
        final score = raw[o + 4] * raw[o + 5];
        if (score < threshold) continue;
        final cx = (raw[o] + gx) * s / ratio, cy = (raw[o + 1] + gy) * s / ratio;
        final bw = math.exp(raw[o + 2]) * s / ratio, bh = math.exp(raw[o + 3]) * s / ratio;
        boxes.add(PersonBox(
          math.max(0, cx - bw / 2) / viewWidth,
          math.max(0, cy - bh / 2) / viewHeight,
          math.min(viewWidth.toDouble(), cx + bw / 2) / viewWidth,
          math.min(viewHeight.toDouble(), cy + bh / 2) / viewHeight,
          score,
        ));
      }
    }
  }
  boxes.sort((a, b) => b.score.compareTo(a.score));
  final keep = <PersonBox>[];
  for (final b in boxes) {
    if (keep.every((k) => b.iou(k) < 0.45)) keep.add(b);
  }
  return keep;
}

/// YOLOX-Nano person detector on ONNX Runtime (Apache-2.0, see
/// assets/models/NOTICE.md). Finds people so the pose model can be pointed
/// at the athlete instead of the whole frame.
class PersonDetector {
  PersonDetector._(this._session);
  final OrtSession _session;

  static PersonDetector load(Uint8List modelBytes) {
    ensureOrtEnv();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    return PersonDetector._(OrtSession.fromBuffer(modelBytes, options));
  }

  /// People in [frame], turned clockwise by [quarterTurns] first; boxes are
  /// in 0..1 of the turned view.
  Future<List<PersonBox>> detect(VideoFrame frame, {int quarterTurns = 0, double threshold = 0.4}) async {
    final (input, ratio) = detectorInput(frame.bgra, frame.width, frame.height,
        stride: frame.stride, quarterTurns: quarterTurns);
    final tensor = OrtValueTensor.createTensorWithDataList(
        input, [1, 3, detectorInputSize, detectorInputSize]);
    final run = OrtRunOptions();
    try {
      final outs = await _session.runAsync(run, {'images': tensor}, ['output']) ?? const [];
      final raw = flattenOrt(outs.first?.value);
      for (final o in outs) {
        o?.release();
      }
      final view = FrameView(frame.width, frame.height, quarterTurns);
      return decodePersons(raw, ratio, view.viewWidth, view.viewHeight, threshold: threshold);
    } finally {
      tensor.release();
      run.release();
    }
  }

  void release() => _session.release();
}
