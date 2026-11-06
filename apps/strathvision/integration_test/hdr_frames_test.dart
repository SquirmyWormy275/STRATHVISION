// HDR clips (phones record HLG / Dolby Vision) are tone-mapped to standard
// video before pose tracking; standard clips are left alone. Without this
// the headless decoder's frames are washed out and bright scenes lose the
// person entirely (found on the Gurr Academy footage).
//   flutter test integration_test/hdr_frames_test.dart -d linux \
//     --dart-define=CLIP_DIR=$PWD/integration_test/assets
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/vision/frame_grabber.dart';

const clipDir = String.fromEnvironment('CLIP_DIR');

double meanLuma(VideoFrame f) {
  var sum = 0.0, n = 0;
  for (var y = 0; y < f.height; y += 4) {
    for (var x = 0; x < f.width; x += 4) {
      final i = y * f.stride + x * 4;
      sum += 0.114 * f.bgra[i] + 0.587 * f.bgra[i + 1] + 0.299 * f.bgra[i + 2];
      n++;
    }
  }
  return sum / n;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('HDR is tone-mapped, SDR is not', (tester) async {
    await tester.runAsync(() async {
      final hdr = (await FrameGrabber.open('$clipDir/hdr_hlg.mov'))!;
      final frame = (await hdr.frameIndex(10, fps: 30))!;
      // ignore: avoid_print
      print('hdr: tone-mapped ${hdr.toneMapped}, ${frame.width}x${frame.height}, luma ${meanLuma(frame).toStringAsFixed(1)}');
      expect(hdr.toneMapped, isTrue);
      expect(frame.width, 320);
      await hdr.close();

      final sdr = (await FrameGrabber.open('$clipDir/cleave.webm'))!;
      expect(sdr.toneMapped, isFalse);
      expect(await sdr.frameIndex(10, fps: 29.97), isNotNull);
      await sdr.close();
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
