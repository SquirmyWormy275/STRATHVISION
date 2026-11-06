import 'dart:math' as math;

import 'contracts.dart';
import 'engine.dart';
import 'errors.dart';
import 'pack.dart';
import 'profile.dart';
import 'scoring.dart';
import 'stages.dart';

// ------------------------------------------------------- clip quality (task 1)

/// Quality verdict for one reference clip.
class ClipQuality {
  const ClipQuality({
    required this.clipId,
    required this.displayName,
    required this.usable,
    required this.reasons,
    this.vector,
    this.error,
    this.criticalPoseConfidence,
  });

  final String clipId;
  final String displayName;
  final bool usable;

  /// Why the clip is not usable (empty when usable). Plain language.
  final List<String> reasons;
  final MetricVector? vector;
  final AnalysisError? error;

  /// Mean pose confidence over the pack's critical phases.
  final double? criticalPoseConfidence;
}

/// Judges one analyzed clip against the pack's builder thresholds.
ClipQuality evaluateClip({
  required String displayName,
  required String clipId,
  required AnalysisDetail detail,
  required AnalysisPack pack,
}) {
  switch (detail.outcome) {
    case AnalysisFailure(:final error):
      return ClipQuality(
        clipId: clipId,
        displayName: displayName,
        usable: false,
        reasons: [error.message],
        error: error,
      );
    case AnalysisSuccess(:final vector):
      final reasons = <String>[];
      final crit = [
        for (final p in pack.criticalPhases) detail.phasePoseConfidence[p] ?? 0,
      ];
      final critConf = crit.isEmpty
          ? 0.0
          : crit.reduce((a, b) => a + b) / crit.length;
      if (critConf < pack.minCriticalPoseConfidence) {
        reasons.add('The body is hard to see in the key part of the movement.');
      }
      final missing = pack.metrics
          .where((m) => !vector.metrics.containsKey(m.key))
          .toList();
      if (missing.isNotEmpty) {
        reasons.add('Some measurements could not be taken.');
      }
      return ClipQuality(
        clipId: clipId,
        displayName: displayName,
        usable: reasons.isEmpty,
        reasons: reasons,
        vector: vector,
        criticalPoseConfidence: critConf,
      );
  }
}

// ------------------------------------------------------------ fitting (task 2)

/// Fits center (mean), spread (sample standard deviation, floored at the
/// pack's `min_spread`), and weight per pack metric from Metric Vectors.
///
/// Weight = pack default weight × mean metric confidence, rescaled so the
/// weights of present metrics average 1. Metrics measured less reliably
/// count less.
Map<String, ProfileMetric> fitMetrics(
  List<MetricVector> vectors,
  AnalysisPack pack,
) {
  final raw = <String, ProfileMetric>{};
  for (final def in pack.metrics) {
    final vals = <double>[], confs = <double>[];
    for (final v in vectors) {
      final m = v.metrics[def.key];
      if (m == null) continue;
      vals.add(m.value);
      confs.add(m.confidence);
    }
    if (vals.isEmpty) continue;
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    var sd = 0.0;
    if (vals.length > 1) {
      final ss = vals
          .map((x) => (x - mean) * (x - mean))
          .reduce((a, b) => a + b);
      sd = math.sqrt(ss / (vals.length - 1));
    }
    final spread = math.max(sd, math.max(def.minSpread, 1e-6));
    final conf = confs.reduce((a, b) => a + b) / confs.length;
    raw[def.key] = ProfileMetric(
      center: mean,
      spread: spread,
      weight: def.weight * conf,
      unit: def.unit,
      phase: def.phase,
    );
  }
  final weights = raw.values.map((m) => m.weight).toList();
  final meanW = weights.isEmpty
      ? 0.0
      : weights.reduce((a, b) => a + b) / weights.length;
  double r(double v) => (v * 1e4).roundToDouble() / 1e4;
  return {
    for (final e in raw.entries)
      e.key: ProfileMetric(
        center: r(e.value.center),
        spread: r(math.max(e.value.spread, 1e-4)),
        weight: meanW == 0 ? 0 : r(e.value.weight / meanW),
        unit: e.value.unit,
        phase: e.value.phase,
      ),
  };
}

Map<String, double> metricValues(MetricVector v) => {
  for (final e in v.metrics.entries) e.key: e.value.value,
};

// ----------------------------------------------------- self-consistency (task 3)

class SelfConsistency {
  const SelfConsistency({
    required this.heldOutScores,
    required this.meanScore,
    required this.threshold,
  });

  /// clip_id → score of that clip against the profile fitted without it.
  final Map<String, double> heldOutScores;
  final double meanScore;
  final double threshold;

  bool get passed => meanScore >= threshold;
}

/// Leave-one-out: each clip is scored against the profile fitted from the
/// others. Passes when the mean held-out score meets the pack threshold.
SelfConsistency selfConsistency(List<MetricVector> vectors, AnalysisPack pack) {
  final scores = <String, double>{};
  for (var i = 0; i < vectors.length; i++) {
    final rest = [...vectors.take(i), ...vectors.skip(i + 1)];
    final fit = fitMetrics(rest, pack);
    scores[vectors[i].clipId] =
        styleMatchScore(metricValues(vectors[i]), fit) ?? 0;
  }
  final mean = scores.isEmpty
      ? 0.0
      : scores.values.reduce((a, b) => a + b) / scores.length;
  return SelfConsistency(
    heldOutScores: scores,
    meanScore: mean,
    threshold: pack.selfConsistencyThreshold,
  );
}

// ------------------------------------------------------------------ builder

sealed class BuildOutcome {
  const BuildOutcome();
}

/// A ready profile.
class BuildReady extends BuildOutcome {
  const BuildReady(this.profile, this.consistency);
  final Profile profile;
  final SelfConsistency consistency;
}

/// Structured rejection (Error Contract). `details.gates` lists each gate.
class BuildRejected extends BuildOutcome {
  const BuildRejected(this.error);
  final AnalysisError error;
}

/// Builds a profile from reference clips, enforcing the INTERFACES.md
/// quality gates. Never returns a weak profile: any failed gate is a
/// rejection.
class ProfileBuilder {
  ProfileBuilder({required this.engine});

  final AnalysisEngine engine;
  AnalysisPack get pack => engine.pack;

  /// Analyzes and judges one reference clip (clip import, task 1).
  Future<ClipQuality> evaluate(
    ClipSource clip, {
    required String displayName,
  }) async {
    final detail = await engine.analyzeDetailed(clip);
    return evaluateClip(
      displayName: displayName,
      clipId: clip.clipId,
      detail: detail,
      pack: pack,
    );
  }

  /// Applies the quality gates to evaluated clips and fits the profile.
  ///
  /// [previous] is the coach's last profile: the new one keeps its id and
  /// takes the next version.
  BuildOutcome build({
    required String coachName,
    required List<ClipQuality> clips,
    required String newProfileId,
    required DateTime now,
    Profile? previous,
  }) {
    final usable = {
      for (final c in clips.where((c) => c.usable)) c.clipId: c,
    }.values.toList();
    final vectors = [for (final c in usable) c.vector!];
    final gates = <String, Object?>{
      'clips_total': clips.length,
      'clips_usable': usable.length,
      'min_clips': pack.minClips,
    };

    if (previous != null &&
        (previous.packId != pack.packId || previous.eventId != pack.eventId)) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.schemaMismatch,
          'The previous profile is for a different event.',
          {
            'previous_pack_id': previous.packId,
            'previous_event_id': previous.eventId,
          },
        ),
      );
    }
    if (previous != null &&
        previous.metricSchemaVersion != pack.metricSchemaVersion) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.schemaMismatch,
          'The previous profile uses an older measurement schema.',
          {
            'previous_schema': previous.metricSchemaVersion,
            'schema': pack.metricSchemaVersion,
          },
        ),
      );
    }

    final minClipsMet = usable.length >= pack.minClips;
    gates['min_clips_met'] = minClipsMet;
    if (!minClipsMet) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.insufficientClips,
          'Add ${pack.minClips - usable.length} more clean clips to build this profile.',
          {'gates': gates, 'unusable': _unusable(clips)},
        ),
      );
    }

    final crit = usable.map((c) => c.criticalPoseConfidence ?? 0).toList();
    final avgCrit = crit.reduce((a, b) => a + b) / crit.length;
    gates['critical_pose_confidence'] = _r(avgCrit);
    gates['min_critical_pose_confidence'] = pack.minCriticalPoseConfidence;
    if (avgCrit < pack.minCriticalPoseConfidence) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.lowPoseConfidence,
          'The body is not tracked clearly enough across these clips.',
          {'gates': gates},
        ),
      );
    }

    final consistency = selfConsistency(vectors, pack);
    gates['self_consistency_score'] = _r(consistency.meanScore);
    gates['self_consistency_threshold'] = consistency.threshold;
    gates['self_consistency_passed'] = consistency.passed;
    if (!consistency.passed) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.profileNotReady,
          'These clips do not agree with each other well enough to form one style.',
          {
            'gates': gates,
            'held_out_scores': {
              for (final e in consistency.heldOutScores.entries)
                e.key: _r(e.value),
            },
          },
        ),
      );
    }

    final profile = Profile(
      profileId: previous?.profileId ?? newProfileId,
      version: (previous?.version ?? 0) + 1,
      coachName: coachName,
      packId: pack.packId,
      eventId: pack.eventId,
      metricSchemaVersion: pack.metricSchemaVersion,
      createdAt: now.toUtc(),
      sourceClipCount: usable.length,
      minClipsMet: true,
      selfConsistencyPassed: true,
      notes:
          '${usable.length} of ${clips.length} clips used. '
          'Held-out match ${(consistency.meanScore * 100).round()}% '
          '(needs ${(consistency.threshold * 100).round()}%). '
          'Critical-phase pose confidence ${(avgCrit * 100).round()}%.',
      metrics: fitMetrics(vectors, pack),
      referenceClips: [
        for (final v in vectors)
          ReferenceClip(clipId: v.clipId, metrics: metricValues(v)),
      ],
    );
    final problems = validateProfile(profile.toJson());
    if (problems.isNotEmpty) {
      return BuildRejected(
        AnalysisError(
          ErrorCode.schemaMismatch,
          'The builder produced an invalid profile.',
          {'problems': problems},
        ),
      );
    }
    return BuildReady(profile, consistency);
  }

  static List<Map<String, Object?>> _unusable(List<ClipQuality> clips) => [
    for (final c in clips.where((c) => !c.usable))
      {'clip_id': c.clipId, 'name': c.displayName, 'reasons': c.reasons},
  ];

  static double _r(double v) => (v * 1e4).roundToDouble() / 1e4;
}
