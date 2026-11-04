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
}
