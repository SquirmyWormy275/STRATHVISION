import 'dart:math' as math;
import 'dart:typed_data';

/// Model input size (BlazePose landmark model).
const poseInputSize = 256;

/// A square region of the frame, in frame pixels.
class Roi {
  const Roi(this.cx, this.cy, this.size);
  final double cx, cy, size;

  /// The whole frame, centred (the start, and the fallback when lost).
  factory Roi.full(int width, int height) =>
      Roi(width / 2, height / 2, math.max(width, height).toDouble());

  double get left => cx - size / 2;
  double get top => cy - size / 2;

  /// Model-input pixel → frame pixel.
  (double, double) toFrame(double x, double y) =>
      (left + x * size / poseInputSize, top + y * size / poseInputSize);
}

/// An upright view of a frame: the frame turned clockwise by [quarterTurns]
/// × 90° (phones filmed sideways without rotation metadata show the person
/// lying down; the pose model needs them upright). Regions and landmarks
/// live in view pixels.
class FrameView {
  const FrameView(this.width, this.height, this.quarterTurns);
  final int width, height, quarterTurns;

  int get viewWidth => quarterTurns.isOdd ? height : width;
  int get viewHeight => quarterTurns.isOdd ? width : height;

  /// View point → frame point (continuous pixel coordinates).
  (double, double) toFrame(double vx, double vy) => switch (quarterTurns % 4) {
        1 => (vy, height - vx),
        2 => (width - vx, height - vy),
        3 => (width - vy, vx),
        _ => (vx, vy),
      };
}

/// Crops [roi] from a BGRA frame and resizes it (bilinear) to the model
/// input: 256×256 RGB floats in 0..1, row-major, HWC. Outside the frame is
/// black.
///
/// [stride] is bytes per row (defaults to width × 4; decoders may pad rows).
/// [quarterTurns] turns the frame clockwise first; [roi] is then in the
/// turned view's pixels (see [FrameView]).
Float32List cropToInput(Uint8List bgra, int width, int height, Roi roi,
    {int? stride, int quarterTurns = 0}) {
  final view = FrameView(width, height, quarterTurns);
  const n = poseInputSize;
  final out = Float32List(n * n * 3);
  final scale = roi.size / n;
  final rowBytes = stride ?? width * 4;
  var o = 0;
  for (var y = 0; y < n; y++) {
    final vy = roi.top + (y + 0.5) * scale;
    for (var x = 0; x < n; x++) {
      final (sx, sy) = view.toFrame(roi.left + (x + 0.5) * scale, vy);
      final fx = sx - 0.5, fy = sy - 0.5;
      final x0 = fx.floor(), y0 = fy.floor();
      final wy = fy - y0;
      final wx = fx - x0;
      for (var c = 0; c < 3; c++) {
        // BGRA → RGB channel offset.
        final ch = 2 - c;
        double px(int xx, int yy) => (xx < 0 || yy < 0 || xx >= width || yy >= height)
            ? 0.0
            : bgra[yy * rowBytes + xx * 4 + ch].toDouble();
        final v = px(x0, y0) * (1 - wx) * (1 - wy) +
            px(x0 + 1, y0) * wx * (1 - wy) +
            px(x0, y0 + 1) * (1 - wx) * wy +
            px(x0 + 1, y0 + 1) * wx * wy;
        out[o++] = v / 255.0;
      }
    }
  }
  return out;
}

/// The next frame's region from this frame's landmarks (MediaPipe's rule):
/// centred on the hip centre (landmark 33), side = 2.5 × the distance from
/// the hip centre to the body-scale point (landmark 34). [landmarks] are 39
/// × (x, y, ...) in model-input pixels of [roi]; [stride] values per point.
Roi roiFromLandmarks(List<double> landmarks, Roi roi, {int stride = 5}) {
  final (hx, hy) = roi.toFrame(landmarks[33 * stride], landmarks[33 * stride + 1]);
  final (sx, sy) = roi.toFrame(landmarks[34 * stride], landmarks[34 * stride + 1]);
  final size = 2 * math.sqrt((sx - hx) * (sx - hx) + (sy - hy) * (sy - hy)) * 1.25;
  return Roi(hx, hy, math.max(size, 32));
}

