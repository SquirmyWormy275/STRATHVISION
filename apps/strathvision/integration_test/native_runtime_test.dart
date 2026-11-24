// Run on an actual native target, including the iOS Simulator in CI.
// Synthetic input verifies linking/model compatibility, not coaching accuracy.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:strathvision/vision/blazepose.dart';
import 'package:strathvision/vision/frame_grabber.dart';
import 'package:strathvision/vision/person_detector.dart';
import 'package:strathvision/vision/pose_math.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native runtime loads and executes both shipped models', (
    tester,
  ) async {
    await tester.runAsync(() async {
      ensureOrtEnv();
      expect(OrtEnv.version, '1.15.1');
      final pose = BlazePose.load(
        (await rootBundle.load('assets/models/pose_landmark_full.onnx')).buffer
            .asUint8List(),
      );
      try {
        final result = await pose.infer(
          Float32List(poseInputSize * poseInputSize * 3),
        );
        expect(result.landmarks, hasLength(39 * 5));
        expect(result.world, hasLength(39 * 3));
        expect(result.presence, inInclusiveRange(0.0, 1.0));
        expect(
          [
            ...result.landmarks,
            ...result.world,
          ].every((value) => value.isFinite),
          isTrue,
        );
      } finally {
        pose.release();
      }
      final detector = PersonDetector.load(
        (await rootBundle.load('assets/models/yolox_nano.onnx')).buffer
            .asUint8List(),
      );
      try {
        final frame = VideoFrame(Uint8List(64 * 64 * 4), 64, 64, 64 * 4);
        expect(await detector.detect(frame), isEmpty);
      } finally {
        detector.release();
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
