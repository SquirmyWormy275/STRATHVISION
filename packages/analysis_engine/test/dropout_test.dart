import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

ImplementFrame observation(int frame, [double confidence = 1]) => ImplementFrame(
  frame: frame, grip: const Vec3(0, 0, 0), tip: const Vec3(1, 0, 0),
  confidence: confidence,
);

void main() {
  test('confident endpoints do not hide a missing middle interval', () {
    final track = ImplementTrack(frames: [observation(0), observation(15)]);
    expect(longestDropout(track, 30, 0, 15), closeTo(14 / 30, 1e-9));
  });
  test('missing edges and entirely absent spans count as dropout', () {
    final track = ImplementTrack(frames: [observation(10), observation(15)]);
    expect(longestDropout(track, 30, 0, 29), closeTo(14 / 30, 1e-9));
    expect(longestDropout(const ImplementTrack(frames: []), 30, 0, 29), 1);
  });
  test('missing and low-confidence observations form one continuous gap', () {
    final track = ImplementTrack(frames: [
      observation(0), observation(5, .2), observation(10, .2), observation(15),
    ]);
    expect(longestDropout(track, 30, 0, 15), closeTo(14 / 30, 1e-9));
  });
  test('normal downsampling gaps do not accumulate across confident samples', () {
    final track = ImplementTrack(frames: [
      for (var i = 0; i < 30; i += 2) observation(i),
    ]);
    expect(longestDropout(track, 30, 0, 29), closeTo(1 / 30, 1e-9));
  });
}
