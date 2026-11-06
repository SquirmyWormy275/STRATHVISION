import 'dart:math' as math;

import 'pack.dart';

/// One clip's view through a head, as the probes see it.
class ProbeSample {
  const ProbeSample({
    required this.residual,
    required this.trackConfidence,
    this.mark,
  });

  /// Head output for the clip.
  final double residual;

  /// Mean implement-track confidence for the clip.
  final double trackConfidence;

  /// Winning red/green mark on the probe's attribute, if any:
  /// `red` or `green`.
  final String? mark;
}

double? _mean(Iterable<double> xs) {
  final l = xs.toList();
  return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
}

/// Evaluates one probe over [samples]. Null when it is undefined for them
/// (no samples, no marks, or no variation to correlate).
double? evaluateProbe(ProbeDef probe, List<ProbeSample> samples) {
  final r = [for (final s in samples) s.residual];
  switch (probe.kind) {
    case ProbeKind.meanAbsResidual:
      return _mean(r.map((x) => x.abs()));
    case ProbeKind.signedMeanResidual:
      return _mean(r);
    case ProbeKind.markAgreement:
      final marked = samples.where((s) => s.mark == 'red' || s.mark == 'green');
      if (marked.isEmpty) return null;
      final agree = marked.where((s) => s.mark == 'green'
          ? s.residual.abs() < probe.tolerance
          : s.residual.abs() >= probe.tolerance);
      return agree.length / marked.length;
    case ProbeKind.residualVariance:
      final m = _mean(r);
      if (m == null) return null;
      return _mean(r.map((x) => (x - m) * (x - m)));
    case ProbeKind.confidenceCorrelation:
      if (samples.length < 2) return null;
      final xs = r.map((x) => x.abs()).toList();
      final ys = [for (final s in samples) s.trackConfidence];
      final mx = _mean(xs)!, my = _mean(ys)!;
      var sxy = 0.0, sxx = 0.0, syy = 0.0;
      for (var i = 0; i < xs.length; i++) {
        sxy += (xs[i] - mx) * (ys[i] - my);
        sxx += (xs[i] - mx) * (xs[i] - mx);
        syy += (ys[i] - my) * (ys[i] - my);
      }
      if (sxx < 1e-12 || syy < 1e-12) return null; // no variation
      return sxy / math.sqrt(sxx * syy);
  }
}

/// Every probe the pack registers on [head], by name.
Map<String, double?> runProbes(
        AnalysisPack pack, String head, List<ProbeSample> samples) =>
    {
      for (final p in pack.probes.where((p) => p.head == head))
        p.name: evaluateProbe(p, samples),
    };
