import 'engine.dart';
import 'errors.dart';
import 'heads.dart';
import 'pack.dart';
import 'patch.dart';
import 'probes.dart';

/// One probe clip as the harness holds it: what the head sees, plus the
/// probe inputs. Precomputed once, so trying a patch costs one MLP pass per
/// clip and no re-analysis.
class HarnessClip {
  const HarnessClip({
    required this.features,
    required this.base,
    required this.trackConfidence,
    this.mark,
  });

  /// Builds a clip from an analysis made with the coach reference.
  factory HarnessClip.fromDetail(AnalysisDetail d, String head, {String? mark}) =>
      HarnessClip(
        features: d.features,
        base: d.headBases[head] ?? 0,
        trackConfidence: d.implementConfidence,
        mark: mark,
      );

  final List<double> features;
  final double base;
  final double trackConfidence;
  final String? mark;
}

/// The verdict on a patch under the pack's acceptance rules.
class PatchDecision {
  const PatchDecision({required this.accepted, required this.reasons});
  final bool accepted;

  /// One plain sentence per rule, failing rules first.
  final List<String> reasons;
}

class HarnessRun {
  const HarnessRun({
    required this.before,
    required this.after,
    required this.decision,
    this.patch,
    this.newEdits = 0,
  });

  final Map<String, double?> before;
  final Map<String, double?> after;
  final PatchDecision decision;

  /// The cumulative patch (null when nothing was found to try).
  final SpecialistPatch? patch;

  /// Edits this run added on top of the current patch.
  final int newEdits;
}

/// Local weight-space harness for one registered specialist head. The five
/// probes are the only feedback it reads (DECISIONS.md).
class SpecialistHarness {
  SpecialistHarness({
    required this.pack,
    required this.headName,
    required this.clips,
    this.current,
  }) : def = pack.heads.firstWhere((h) => h.name == headName,
            orElse: () => throw AnalysisError(ErrorCode.patchRejected,
                'The pack has no head called $headName.')) {
    if (def.acceptance == null) {
      throw AnalysisError(ErrorCode.patchRejected,
          'The pack gives no acceptance rules for $headName.');
    }
    final base = MlpHead.base(def.name, def.base);
    _head = current == null
        ? base
        : patchedMlpHead(
            base, [for (final e in current!.edits) (e.tensor, e.index, e.delta)]);
  }

  final AnalysisPack pack;
  final String headName;
  final List<HarnessClip> clips;

  /// The patch already in the package, if any. New patches build on it.
  final SpecialistPatch? current;
  final HeadDef def;
  late final MlpHead _head;

  AcceptanceRules get rules => def.acceptance!;
  int get _budget =>
      (rules.maxWeightFraction * _head.parameterCount).ceil() - 1;

  Map<String, double?> probe(MlpHead h) => runProbes(pack, headName, [
        for (final c in clips)
          ProbeSample(
              residual: h.evaluate(c.features, base: c.base),
              trackConfidence: c.trackConfidence,
              mark: c.mark),
      ]);

  /// Probe readings for the current head.
  Map<String, double?> baseline() => probe(_head);

  /// Applies the pack's acceptance rules to before/after readings.
  PatchDecision judge(
      Map<String, double?> before, Map<String, double?> after, int totalEdits) {
    final checks = _checks(before, after, totalEdits);
    return PatchDecision(
      accepted: checks.every((c) => c.passed),
      reasons: [
        for (final c in checks.where((c) => !c.passed)) c.sentence,
        for (final c in checks.where((c) => c.passed)) c.sentence,
      ],
    );
  }

  List<_Check> _checks(
      Map<String, double?> before, Map<String, double?> after, int totalEdits) {
    final out = <_Check>[];
    String f(double? v) => v == null ? 'n/a' : v.toStringAsFixed(3);

    final p0 = before[rules.primaryProbe], p1 = after[rules.primaryProbe];
    if (p0 == null || p1 == null) {
      out.add(_Check(true, false, '${rules.primaryProbe} could not be measured.'));
    } else if (p0.abs() - p1.abs() >= rules.minImprovement - 1e-9) {
      out.add(_Check(true, true, '${rules.primaryProbe} improved from ${f(p0)} to ${f(p1)}.'));
    } else {
      out.add(_Check(true, false, '${rules.primaryProbe} must improve by at least '
          '${rules.minImprovement} (from ${f(p0)} to ${f(p1)}).'));
    }
    for (final n in rules.noRegress) {
      final a = before[n], b = after[n];
      if (a != null && b != null && b.abs() > a.abs() + 1e-9) {
        out.add(_Check(false, false, '$n got worse (${f(a)} → ${f(b)}).'));
      } else if ((a == null) != (b == null)) {
        out.add(_Check(false, false, '$n changed from ${f(a)} to ${f(b)}.'));
      } else {
        out.add(_Check(false, true, '$n did not regress (${f(a)} → ${f(b)}).'));
      }
    }
    for (final e in rules.withinFraction.entries) {
      final a = before[e.key], b = after[e.key];
      final pct = (e.value * 100).round();
      if (a == null && b == null) {
        out.add(_Check(false, true, '${e.key} stayed unmeasurable.'));
      } else if (a == null || b == null) {
        out.add(_Check(false, false, '${e.key} changed from ${f(a)} to ${f(b)}.'));
      } else if ((b - a).abs() <= e.value * a.abs() + 1e-9) {
        out.add(_Check(false, true, '${e.key} stayed within $pct% (${f(a)} → ${f(b)}).'));
      } else {
        out.add(_Check(false, false, '${e.key} moved more than $pct% (${f(a)} → ${f(b)}).'));
      }
    }
    final limit = rules.maxWeightFraction * _head.parameterCount;
    out.add(totalEdits < limit
        ? _Check(false, true, 'Touches $totalEdits of ${_head.parameterCount} weights.')
        : _Check(false, false,
            'Touches $totalEdits weights; must be under '
            '${(rules.maxWeightFraction * 100).toStringAsFixed(0)}% '
            '(${limit.toStringAsFixed(1)} of ${_head.parameterCount}).'));
    return out;
  }

  /// Every rule except the primary improvement and the weight budget holds:
  /// keeps the search inside the allowed region.
  bool _sideRulesHold(Map<String, double?> before, Map<String, double?> after) =>
      _checks(before, after, 0).where((c) => !c.primary).every((c) => c.passed);

  /// Proposes a sparse patch by black-box coordinate search over the output
  /// layer, reading only the probes, then judges it.
  HarnessRun search({int rounds = 3}) {
    final before = baseline();
    final p0 = before[rules.primaryProbe];
    if (p0 == null) {
      return HarnessRun(
          before: before,
          after: before,
          decision: judge(before, before, current?.edits.length ?? 0));
    }
    final candidates = <(String, List<int>)>[
      ('b2', const []),
      for (var i = 0; i < 32; i++) ('w2', [i]),
    ];
    final existing = {
      for (final e in current?.edits ?? const <PatchEdit>[]) '${e.tensor}${e.index}',
    };
    final deltas = <String, (String, List<int>, double)>{};
    var head = _head;
    var reading = before;
    double objective(Map<String, double?> r) =>
        (r[rules.primaryProbe] ?? double.infinity).abs();

    for (var round = 0; round < rounds; round++) {
      var improved = false;
      for (final (tensor, idx) in candidates) {
        final key = '$tensor$idx';
        final isNew = !deltas.containsKey(key) && !existing.contains(key);
        final used = existing.length + deltas.keys.where((k) => !existing.contains(k)).length;
        if (isNew && used >= _budget) continue;
        final scale = objective(reading);
        if (scale < 1e-6) break;
        (MlpHead, Map<String, double?>, double)? best;
        for (final step in [1.0, -1.0, 0.5, -0.5, 0.25, -0.25, 2.0, -2.0]) {
          final d = step * scale;
          final trial = patchedMlpHead(head, [(tensor, idx, d)]);
          final r = probe(trial);
          if (objective(r) < objective(best?.$2 ?? reading) - 1e-9 &&
              _sideRulesHold(before, r)) {
            best = (trial, r, d);
          }
        }
        if (best != null) {
          head = best.$1;
          reading = best.$2;
          final prev = deltas[key]?.$3 ?? 0;
          deltas[key] = (tensor, idx, prev + best.$3);
          improved = true;
        }
      }
      if (!improved) break;
    }
    if (deltas.isEmpty) {
      return HarnessRun(
          before: before,
          after: before,
          decision: judge(before, before, current?.edits.length ?? 0));
    }
    // Cumulative patch: earlier edits plus this run's.
    final merged = <String, PatchEdit>{
      for (final e in current?.edits ?? const <PatchEdit>[])
        '${e.tensor}${e.index}': e,
    };
    for (final e in deltas.entries) {
      final prev = merged[e.key]?.delta ?? 0;
      merged[e.key] = PatchEdit(e.value.$1, e.value.$2, prev + e.value.$3);
    }
    final patch = SpecialistPatch(
      head: headName,
      version: (current?.version ?? 0) + 1,
      base: def.base,
      edits: merged.values.toList(),
      notes: 'Harness: ${rules.primaryProbe} '
          '${p0.toStringAsFixed(3)} → ${reading[rules.primaryProbe]!.toStringAsFixed(3)}.',
    );
    return HarnessRun(
      before: before,
      after: reading,
      decision: judge(before, reading, patch.edits.length),
      patch: patch,
      newEdits: deltas.length,
    );
  }
}

class _Check {
  const _Check(this.primary, this.passed, this.sentence);
  final bool primary;
  final bool passed;
  final String sentence;
}
