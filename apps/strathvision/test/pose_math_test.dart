import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/vision/pose_math.dart';

void main() {
  /// A BGRA frame: left half pure red, right half pure blue.
  Uint8List frame(int w, int h) {
    final b = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        if (x < w / 2) {
          b[i + 2] = 255; // R
        } else {
          b[i] = 255; // B
        }
        b[i + 3] = 255;
      }
    }
    return b;
  }

  test('full-frame region is centred and covers the long side', () {
    final r = Roi.full(400, 720);
    expect((r.cx, r.cy, r.size), (200, 360, 720));
    expect(r.toFrame(0, 0), (-160, 0));
    expect(r.toFrame(256, 256), (560, 720));
  });

  test('crop converts BGRA to RGB floats with black padding outside', () {
    final input = cropToInput(frame(400, 720), 400, 720, Roi.full(400, 720));
    expect(input.length, 256 * 256 * 3);
    double at(int x, int y, int c) => input[(y * 256 + x) * 3 + c];
    // Padding left of the frame.
    expect(at(5, 128, 0), 0);
    // Inside the red half: R≈1, B≈0.
    expect(at(90, 128, 0), closeTo(1, 1e-6));
    expect(at(90, 128, 2), closeTo(0, 1e-6));
    // Inside the blue half.
    expect(at(170, 128, 2), closeTo(1, 1e-6));
    expect(at(170, 128, 0), closeTo(0, 1e-6));
  });

  test('padded rows (stride > width × 4) are read correctly', () {
    // 8×8, rows padded to 48 bytes; left half red, right half blue.
    const w = 8, h = 8, stride = 48;
    final b = Uint8List(stride * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        b[y * stride + x * 4 + (x < 4 ? 2 : 0)] = 255;
      }
    }
    final input = cropToInput(b, w, h, Roi.full(w, h), stride: stride);
    double at(int x, int y, int c) => input[(y * 256 + x) * 3 + c];
    for (final y in [20, 128, 236]) {
      expect(at(48, y, 0), closeTo(1, 1e-6), reason: 'row $y left is red');
      expect(at(208, y, 2), closeTo(1, 1e-6), reason: 'row $y right is blue');
      expect(at(208, y, 0), closeTo(0, 1e-6));
    }
    // Reading without the stride would skew rows: this is what broke.
    final skewed = cropToInput(b, w, h, Roi.full(w, h));
    expect(skewed[(236 * 256 + 48) * 3], isNot(closeTo(1, 1e-6)));
  });

  test('next region follows the hips and body scale', () {
    final lm = List<double>.filled(39 * 5, 0);
    lm[33 * 5] = 128; lm[33 * 5 + 1] = 128; // hip centre at input centre
    lm[34 * 5] = 128; lm[34 * 5 + 1] = 64; // scale point 64 px above
    const roi = Roi(500, 400, 512); // 2 frame px per input px
    final next = roiFromLandmarks(lm, roi);
    expect(next.cx, 500);
    expect(next.cy, 400);
    expect(next.size, closeTo(2 * 128 * 1.25, 1e-9));
  });

  test('a sideways frame is turned upright before the model sees it', () {
    // 8 wide × 4 tall frame filmed sideways: the "top" of the scene is the
    // left edge (red), the bottom the right edge (blue).
    const w = 8, h = 4;
    final b = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        b[(y * w + x) * 4 + (x < 4 ? 2 : 0)] = 255;
      }
    }
    // One clockwise turn puts the left edge on top.
    const view = FrameView(w, h, 1);
    expect(view.viewWidth, 4);
    expect(view.viewHeight, 8);
    final input = cropToInput(b, w, h, Roi.full(4, 8), quarterTurns: 1);
    double at(int x, int y, int c) => input[(y * 256 + x) * 3 + c];
    expect(at(128, 64, 0), closeTo(1, 1e-6), reason: 'top is red');
    expect(at(128, 192, 2), closeTo(1, 1e-6), reason: 'bottom is blue');
    // View → frame points round-trip each turn.
    for (final q in [0, 1, 2, 3]) {
      final v = FrameView(w, h, q);
      final (x, y) = v.toFrame(0, 0);
      expect(x >= 0 && x <= w && y >= 0 && y <= h, isTrue, reason: 'turn $q corner');
    }
    expect(const FrameView(w, h, 1).toFrame(0, 0), (0.0, 4.0));
    expect(const FrameView(w, h, 3).toFrame(0, 0), (8.0, 0.0));
  });

}
