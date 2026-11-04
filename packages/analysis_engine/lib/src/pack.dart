import 'body.dart';
import 'errors.dart';

/// How a metric is computed from pose and implement tracks. The engine knows
/// only these generic kinds; packs pick joints, phases, and units.
enum MetricKind {
  /// Mean angle at the middle joint of `joints` (3 names) over the phase, degrees.
  jointAngle('joint_angle', 3),

  /// Max − min of that angle over the phase, degrees.
  jointRange('joint_range', 3),

  /// Mean inclination of the implement segment above horizontal, degrees.
  implementInclination('implement_inclination', 0),

  /// Phase length, seconds.
  phaseDuration('phase_duration', 0);

  const MetricKind(this.wire, this.jointCount);
  final String wire;
  final int jointCount;

  static MetricKind? fromWire(Object? s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

class MetricDef {
  const MetricDef({
    required this.key,
    required this.kind,
    required this.phase,
    required this.unit,
    this.joints = const [],
    this.weight = 1.0,
    this.minSpread = 0.0,
  });

  final String key;
  final MetricKind kind;
  final String phase;
  final String unit;
  final List<Joint> joints;

  /// Pack default weight for style matching (Packs.md).
  final double weight;

  /// Floor for the fitted spread, in [unit]. Keeps a near-constant metric
  /// from dominating the score.
  final double minSpread;
}

/// The part of a pack the analysis runtime reads: phase order, metric
/// catalog, and thresholds. Labels and domain words stay in the pack data.
class AnalysisPack {
  const AnalysisPack({
    required this.packId,
    required this.eventId,
    required this.metricSchemaVersion,
    required this.phases,
    required this.metrics,
    this.minPhaseFrames = 3,
    this.minPoseConfidence = 0.5,
    this.minClips = 15,
    List<String>? criticalPhases,
    this.minCriticalPoseConfidence = 0.6,
    this.selfConsistencyThreshold = 0.5,
  }) : criticalPhases = criticalPhases ?? phases;

  final String packId;
  final String eventId;
  final String metricSchemaVersion;

  /// Phase ids in movement order.
  final List<String> phases;
  final List<MetricDef> metrics;

  /// Fewer frames than this per phase → PHASE_DETECTION_FAILED.
  final int minPhaseFrames;

  /// Clip-level pose confidence below this → LOW_POSE_CONFIDENCE.
  final double minPoseConfidence;

  /// Profile builder: usable clips needed for a ready profile.
  final int minClips;

  /// Phases whose pose confidence gates profile building (default: all).
  final List<String> criticalPhases;

  /// Profile builder: minimum average pose confidence on critical phases,
  /// per clip and across the profile.
  final double minCriticalPoseConfidence;

  /// Profile builder: held-out clips must average at least this style-match
  /// score against the profile fitted from the rest.
  final double selfConsistencyThreshold;

  /// Reads an event's analysis section from pack JSON, or throws
  /// [AnalysisError] with SCHEMA_MISMATCH listing every problem.
  factory AnalysisPack.fromJson(Object? json) {
    final problems = <String>[];
    if (json is! Map) {
      throw AnalysisError(
          ErrorCode.schemaMismatch, 'Pack analysis section must be an object.');
    }
    String str(String k) {
      final v = json[k];
      if (v is String && v.isNotEmpty) return v;
      problems.add('$k must be a non-empty string');
      return '';
    }

    final packId = str('pack_id');
    final eventId = str('event_id');
    final schema = str('metric_schema_version');
    final phases = <String>[];
    final rawPhases = json['phases'];
    if (rawPhases is List && rawPhases.isNotEmpty) {
      for (final p in rawPhases) {
        if (p is String && p.isNotEmpty && !phases.contains(p)) {
          phases.add(p);
        } else {
          problems.add('phases must be unique non-empty strings');
        }
      }
    } else {
      problems.add('phases must be a non-empty list');
    }

    final metrics = <MetricDef>[];
    final keys = <String>{};
    final rawMetrics = json['metrics'];
    if (rawMetrics is! List) {
      problems.add('metrics must be a list');
    } else {
      for (var i = 0; i < rawMetrics.length; i++) {
        final m = rawMetrics[i];
        final path = 'metrics[$i]';
        if (m is! Map) {
          problems.add('$path must be an object');
          continue;
        }
        final key = m['key'];
        final kind = MetricKind.fromWire(m['kind']);
        final phase = m['phase'];
        final unit = m['unit'];
        final ok = <bool>[];
        if (key is! String || key.isEmpty || !keys.add(key)) {
          problems.add('$path.key must be a unique non-empty string');
          ok.add(false);
        }
        if (kind == null) {
          problems.add('$path.kind must be one of '
              '${MetricKind.values.map((k) => k.wire).join(' | ')}');
          ok.add(false);
        }
        if (phase is! String || !phases.contains(phase)) {
          problems.add('$path.phase must be one of the pack phases');
          ok.add(false);
        }
        if (unit is! String) {
          problems.add('$path.unit must be a string');
          ok.add(false);
        }
        final joints = <Joint>[];
        final rawJoints = m['joints'] ?? const [];
        if (rawJoints is List) {
          for (final n in rawJoints) {
            final jn = Joint.fromWire(n);
            if (jn == null) {
              problems.add('$path.joints: unknown joint "$n"');
              ok.add(false);
            } else {
              joints.add(jn);
            }
          }
        }
        if (kind != null && joints.length != kind.jointCount) {
          problems.add('$path.joints must name ${kind.jointCount} joints '
              'for ${kind.wire}');
          ok.add(false);
        }
        final weight = m['weight'] ?? 1.0;
        if (weight is! num || weight < 0) {
          problems.add('$path.weight must be a number >= 0');
          ok.add(false);
        }
        final minSpread = m['min_spread'] ?? 0.0;
        if (minSpread is! num || minSpread < 0) {
          problems.add('$path.min_spread must be a number >= 0');
          ok.add(false);
        }
        if (ok.isEmpty) {
          metrics.add(MetricDef(
            key: key as String,
            kind: kind!,
            phase: phase as String,
            unit: unit as String,
            joints: joints,
            weight: (weight as num).toDouble(),
            minSpread: (minSpread as num).toDouble(),
          ));
        }
      }
    }

    final minFrames = json['min_phase_frames'] ?? 3;
    if (minFrames is! int || minFrames < 1) {
      problems.add('min_phase_frames must be a positive integer');
    }
    final minConf = json['min_pose_confidence'] ?? 0.5;
    if (minConf is! num || minConf < 0 || minConf > 1) {
      problems.add('min_pose_confidence must be a number in 0..1');
    }

    final minClips = json['min_clips'] ?? 15;
    if (minClips is! int || minClips < 2) {
      problems.add('min_clips must be an integer >= 2');
    }
    List<String>? critical;
    final rawCritical = json['critical_phases'];
    if (rawCritical != null) {
      if (rawCritical is List &&
          rawCritical.isNotEmpty &&
          rawCritical.every((p) => p is String && phases.contains(p))) {
        critical = rawCritical.cast<String>();
      } else {
        problems.add('critical_phases must be a non-empty list of pack phases');
      }
    }
    double unit(String key, double dflt) {
      final v = json[key] ?? dflt;
      if (v is num && v >= 0 && v <= 1) return v.toDouble();
      problems.add('$key must be a number in 0..1');
      return dflt;
    }

    final minCritical = unit('min_critical_pose_confidence', 0.6);
    final selfConsistency = unit('self_consistency_threshold', 0.5);

    if (problems.isNotEmpty) {
      throw AnalysisError(ErrorCode.schemaMismatch,
          'Pack analysis section does not match the schema.',
          {'problems': problems});
    }
    return AnalysisPack(
      packId: packId,
      eventId: eventId,
      metricSchemaVersion: schema,
      phases: phases,
      metrics: metrics,
      minPhaseFrames: minFrames as int,
      minPoseConfidence: (minConf as num).toDouble(),
      minClips: minClips as int,
      criticalPhases: critical,
      minCriticalPoseConfidence: minCritical,
      selfConsistencyThreshold: selfConsistency,
    );
  }
}

String _jointLabel(Joint j) => j.wire.replaceAll('_', ' ');

/// Plain definition of a metric from its pack entry, for the expandable
/// delta view. Generic: built only from kind, joints, and phase label.
String describeMetric(MetricDef m, {String Function(String phase)? phaseLabel}) {
  final phase = phaseLabel?.call(m.phase) ?? m.phase;
  final joints = m.joints.map(_jointLabel).join(' · ');
  return switch (m.kind) {
    MetricKind.jointAngle =>
      'Average angle at the ${_jointLabel(m.joints[1])} ($joints) during $phase.',
    MetricKind.jointRange =>
      'How far the angle at the ${_jointLabel(m.joints[1])} ($joints) opens and closes during $phase.',
    MetricKind.implementInclination =>
      'Average angle of the implement above horizontal during $phase.',
    MetricKind.phaseDuration => 'How long $phase lasts.',
  };
}
