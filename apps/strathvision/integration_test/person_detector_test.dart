// Person detector (YOLOX-Nano, ONNX Runtime) on decoded frames of a real
// clip, checked against an independent Python run of the same model
// (tools/carne_asada/footage.py Detector on the same frame: one person,
// box [0.025, 0.421, 0.671, 0.800], score 0.803).
//   flutter test integration_test/person_detector_test.dart -d linux \
//     --dart-define=CLIP_DIR=$PWD/integration_test/assets
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/blazepose.dart';
import 'package:strathvision/vision/frame_grabber.dart';
import 'package:strathvision/vision/person_detector.dart';
import 'package:strathvision/vision/pose_math.dart';

const clipDir = String.fromEnvironment('CLIP_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('YOLOX on device matches the reference and handles sideways clips', (tester) async {
    await tester.runAsync(() async {
      final detector = PersonDetector.load(
          (await rootBundle.load('assets/models/yolox_nano.onnx')).buffer.asUint8List());

      final g = (await FrameGrabber.open('$clipDir/cleave.webm'))!;
      final frame = (await g.frameIndex(60, fps: 29.97))!;
      await g.close();
      const dump = String.fromEnvironment('DUMP');
      if (dump.isNotEmpty) {
        File(dump).writeAsBytesSync(frame.bgra);
        // ignore: avoid_print
        print('dumped ${frame.width}x${frame.height} stride ${frame.stride}');
      }
      final boxes = await detector.detect(frame);
      // ignore: avoid_print
      print('upright: $boxes');
      const ref = PersonBox(0.025, 0.421, 0.671, 0.800, 0.803);
      expect(boxes, isNotEmpty);
      expect(boxes.first.iou(ref), greaterThan(0.9));
      expect(boxes.first.score, closeTo(ref.score, 0.06));

      // Sideways copy: turned upright, the same person is found with
      // similar confidence. The detector alone also finds the lying person
      // fairly confidently, so orientation is decided by the pose model's
      // upright check on each detected person.
      final s = (await FrameGrabber.open('$clipDir/cleave_sideways.webm'))!;
      final side = (await s.frameIndex(60, fps: 29.97))!;
      await s.close();
      final turned = await detector.detect(side, quarterTurns: 3);
      final lying = await detector.detect(side, threshold: 0.05);
      // ignore: avoid_print
      print('sideways turned: $turned\nsideways unturned: $lying');
      expect(turned, isNotEmpty);
      expect(turned.first.iou(boxes.first), greaterThan(0.8));
      final pose = BlazePose.load(
          (await rootBundle.load('assets/models/pose_landmark_full.onnx')).buffer.asUint8List());
      Future<double> upright(PersonBox b, int q) async {
        final v = FrameView(side.width, side.height, q);
        final roi = Roi(b.cx * v.viewWidth, b.cy * v.viewHeight,
            math.max(b.width * v.viewWidth, b.height * v.viewHeight) * 1.2);
        final o = await pose.infer(
            cropToInput(side.bgra, side.width, side.height, roi, stride: side.stride, quarterTurns: q));
        return uprightScore(b, o.presence, o.landmarks);
      }

      final up = await upright(turned.first, 3);
      final down = lying.isEmpty ? 0.0 : await upright(lying.first, 0);
      // ignore: avoid_print
      print('upright check: turned $up, unturned $down');
      expect(up, greaterThan(0.5));
      expect(down, lessThan(up / 2));
      detector.release();
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
