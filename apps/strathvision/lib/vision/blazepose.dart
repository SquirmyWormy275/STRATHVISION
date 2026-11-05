import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'pose_math.dart';

/// One model pass: landmarks in input pixels (39 × x, y, z, visibility,
/// presence), pose presence, and metric world landmarks (39 × x, y, z).
class BlazePoseOutput {
  const BlazePoseOutput(this.landmarks, this.presence, this.world);
  final List<double> landmarks;
  final double presence;
  final List<double> world;

  List<double> get visibility => [for (var i = 0; i < 39; i++) landmarks[i * 5 + 3]];
  List<double> get landmarkPresence => [for (var i = 0; i < 39; i++) landmarks[i * 5 + 4]];
}

List<double> flattenOrt(Object? v) {
  final out = <double>[];
  void walk(Object? x) {
    if (x is num) {
      out.add(x.toDouble());
    } else if (x is List) {
      for (final e in x) {
        walk(e);
      }
    }
  }

  walk(v);
  return out;
}

/// Initializes ONNX Runtime once for every model in the app.
void ensureOrtEnv() {
  if (_envReady) return;
  OrtEnv.instance.init();
  _envReady = true;
}

bool _envReady = false;

/// BlazePose GHUM 3D landmark model on ONNX Runtime. Inference runs on
/// ONNX Runtime's worker isolate, so the UI keeps rendering.
class BlazePose {
  BlazePose._(this._session);
  final OrtSession _session;

  static BlazePose load(Uint8List modelBytes) {
    ensureOrtEnv();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    return BlazePose._(OrtSession.fromBuffer(modelBytes, options));
  }

  Future<BlazePoseOutput> infer(Float32List input) async {
    final tensor = OrtValueTensor.createTensorWithDataList(
        input, [1, poseInputSize, poseInputSize, 3]);
    final run = OrtRunOptions();
    try {
      final outs = await _session.runAsync(
              run, {'input_1': tensor}, ['Identity', 'Identity_1', 'Identity_4']) ??
          const [];
      final values = [for (final o in outs) flattenOrt(o?.value)];
      for (final o in outs) {
        o?.release();
      }
      return BlazePoseOutput(values[0], values[1].first, values[2]);
    } finally {
      tensor.release();
      run.release();
    }
  }

  void release() => _session.release();
}
