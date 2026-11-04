import 'dart:math' as math;

import 'features.dart';
import 'pack.dart';
import 'stages.dart';

/// A specialist residual head on the feature vector (ARCHITECTURE.md).
/// Patches from the workbench harness load onto heads.
abstract class SpecialistHead {
  /// Key in `specialist_residuals`.
  String get name;

  /// Id of the base weights; patches must name it.
  String get baseId;
  int get parameterCount;

  /// [base] is the measured error of the head's target metric versus the
  /// coach reference (0 without a reference). The head adds its learned
  /// correction to it.
  double evaluate(List<double> features, {double base = 0});
}

/// Residual head: base + MLP(features), MLP = [featureWidth] → 32 (ReLU) → 1
/// (DECISIONS.md: 2-layer MLP, 64→32, under 10k parameters).
class MlpHead implements SpecialistHead {
  MlpHead({
    required this.name,
    required this.baseId,
    required this.w1,
    required this.b1,
    required this.w2,
    required this.b2,
  })  : assert(w1.length == 32 && w1.every((r) => r.length == featureWidth)),
        assert(b1.length == 32 && w2.length == 32);

  @override
  final String name;
  @override
  final String baseId;
  final List<List<double>> w1; // [32][64]
  final List<double> b1; // [32]
  final List<double> w2; // [32]
  final double b2;

  /// Base weights for [baseId]: a deterministic random hidden layer and a
  /// zero output layer, so an unpatched head returns exactly the measured
  /// error. Accepted patches (sparse edits) teach the correction.
  factory MlpHead.base(String name, String baseId, {double scale = 0.1}) {
    final r = SeededRandom(fnv1a(baseId));
    double w() => (r.next() * 2 - 1) * scale;
    return MlpHead(
      name: name,
      baseId: baseId,
      w1: [for (var i = 0; i < 32; i++) [for (var j = 0; j < featureWidth; j++) w()]],
      b1: [for (var i = 0; i < 32; i++) w()],
      w2: List.filled(32, 0.0),
      b2: 0,
    );
  }

  @override
  int get parameterCount => 32 * featureWidth + 32 + 32 + 1;

  @override
  double evaluate(List<double> features, {double base = 0}) {
    if (features.length != featureWidth) {
      throw ArgumentError('expected $featureWidth features, got ${features.length}');
    }
    var out = base + b2;
    for (var i = 0; i < 32; i++) {
      var h = b1[i];
      final row = w1[i];
      for (var j = 0; j < featureWidth; j++) {
        h += row[j] * features[j];
      }
      out += w2[i] * math.max(0, h);
    }
    return out;
  }
}

/// The heads a pack declares, at their base weights.
List<MlpHead> headsFor(AnalysisPack pack) =>
    [for (final h in pack.heads) MlpHead.base(h.name, h.base)];

/// A copy of [h] with [edits] added (tensor, index, delta).
MlpHead patchedMlpHead(
    MlpHead h, Iterable<(String, List<int>, double)> edits) {
  final w1 = [for (final r in h.w1) [...r]];
  final b1 = [...h.b1];
  final w2 = [...h.w2];
  var b2 = h.b2;
  for (final (tensor, idx, delta) in edits) {
    switch (tensor) {
      case 'w1':
        w1[idx[0]][idx[1]] += delta;
      case 'b1':
        b1[idx[0]] += delta;
      case 'w2':
        w2[idx[0]] += delta;
      case 'b2':
        b2 += delta;
    }
  }
  return MlpHead(name: h.name, baseId: h.baseId, w1: w1, b1: b1, w2: w2, b2: b2);
}
