import 'dart:math' as math;

import 'pack.dart';
import 'profile.dart';
import 'scoring.dart';
import 'strokes.dart';

/// Status copy for the CARNE ASADA playground (DECISIONS.md "CARNE ASADA
/// Ingestion (exact)"). Wording is fixed; attribute, phase, units, and
/// direction words come from the pack.
class CarneCopy {
  static String found(int strokes, int clean, String attr) =>
      'Found $strokes strokes. $clean are clean enough for ${attr.toLowerCase()}. Adding them.';
  static const voice =
      'Coach is talking through the swing. Pulling the spoken labels and binding them to the timeline.';
  static String dropout(double seconds) =>
      'Implement drops out for ${seconds.toStringAsFixed(1)} s. Clip saved, but it won’t move the model.';
  static String gravy(int minutes, String attr) =>
      'You already have $minutes minutes of good ${attr.toLowerCase()} footage. This is pure gravy.';
  static String priority(String attr) =>
      'Priority is ${attr.toLowerCase()}. Only ${attr.toLowerCase()} updates will be considered this session.';
  static const belowThreshold =
      'This clip is below the usable threshold. Click ‘use anyway’ if you want it in the pile.';
  static String accepted(String change) => 'CARNE ASADA accepted an update. $change';
  static const leftHull = 'No update. The proposed change would have left the coach hull.';
  static String tally(int n) =>
      'Session tally: $n accepted ${n == 1 ? 'edit' : 'edits'}. Undo is one click.';

  /// Accepted-update change line for a mean shift.
  static String shifted(String attr, String amount, String dir, String phase) =>
      '$attr mean shifted $amount $dir on the $phase.';

  /// One-sentence explanations (exact style).
  static String shiftWhy(String attr, String amount, String dir, String phase,
          int agree, int greens) =>
      'Shifted ${attr.toLowerCase()} mean $amount $dir on the $phase phase because '
      '$agree of your last $greens green marks agreed.';
  static String tightenWhy(String attr, String phase, int reds) =>
      'Tightened ${attr.toLowerCase()} variance in the $phase phase after '
      '${_word(reds)} consecutive red marks on the same stroke.';
  static String tightened(String attr, String phase) =>
      '$attr variance tightened in the $phase phase.';
}

const _words = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'
];
String _word(int n) => n >= 0 && n < _words.length ? _words[n] : '$n';

/// A red/green mark bound to a stroke, from a project.
class StrokeMark {
  const StrokeMark({
    required this.attribute,
    required this.label,
    required this.author,
    required this.createdAt,
  });
  final String attribute;

  /// `red` or `green`.
  final String label;

  /// `athlete` or `coach`.
  final String author;
  final DateTime createdAt;
}

/// A stroke in the session pile.
class PileStroke {
  PileStroke({required this.stroke, required this.clipName, List<StrokeMark>? marks})
      : marks = marks ?? [];
  final StrokeDetail stroke;
  final String clipName;
  final List<StrokeMark> marks;

  /// "Use anyway": counts as usable even though it misses the threshold.
  bool forced = false;

  /// "Ignore this clip" note.
  bool ignored = false;

  bool get counts => !ignored && (stroke.usable || forced);

  /// The winning label on [attribute]: coach overrides athlete, newest
  /// coach mark wins, else newest athlete mark (DECISIONS.md).
  String? winning(String attribute) {
    final on = marks.where((m) => m.attribute == attribute).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return (on.where((m) => m.author == 'coach').firstOrNull ?? on.firstOrNull)?.label;
  }

  int redCount(String attribute) =>
      marks.where((m) => m.attribute == attribute && m.label == 'red').length;
}

/// One accepted mixture edit.
class MixtureEdit {
  const MixtureEdit({
    required this.type,
    required this.metric,
    required this.phase,
    required this.before,
    required this.after,
    required this.explanation,
    required this.status,
    required this.objectiveBefore,
    required this.objectiveAfter,
    required this.at,
  });

  /// `shift_mean` or `tighten_spread`.
  final String type;
  final String metric;
  final String phase;
  final ProfileMetric before, after;

  /// One sentence, exact style (DECISIONS.md).
  final String explanation;
  final String status;
  final double objectiveBefore, objectiveAfter;
  final DateTime at;

  Map<String, Object?> toJson() => {
        'type': type,
        'metric': metric,
        'phase': phase,
        'before': before.toJson(),
        'after': after.toJson(),
        'explanation': explanation,
        'objective_before': objectiveBefore,
        'objective_after': objectiveAfter,
        'accepted_at': at.toUtc().toIso8601String(),
      };
}

/// Result of one loop step.
sealed class StepResult {
  const StepResult();
}

class StepAccepted extends StepResult {
  const StepAccepted(this.edit);
  final MixtureEdit edit;
}

class StepRejected extends StepResult {
  const StepRejected(this.message);
  final String message;
}

/// Nothing to try (limit reached, below baseline, no marks, no candidate).
class StepIdle extends StepResult {
  const StepIdle(this.reason);
  final String reason;
}

/// Usable-footage meters (DECISIONS.md: Good 2 min, Great 6, Excellent 15).
class Meters {
  const Meters({this.good = 2, this.great = 6, this.excellent = 15});
  final double good, great, excellent;
}

/// A CARNE ASADA session on one profile (desktop only). Edits the
/// phase-conditioned mixture (per-metric center/spread/weight) under hard
/// bounds; the phone never runs this.
class CarneSession {
  CarneSession({
    required this.pack,
    required Profile profile,
    required this.priority,
    this.limit = 5,
    this.chaos = false,
    this.meters = const Meters(),
    DateTime Function()? clock,
    this.phaseLabel,
  })  : assert(limit >= 5 && limit <= 10),
        _clock = clock ?? DateTime.now,
        _profile = profile,
        mixture = Map.of(profile.metrics) {
    for (final m in pack.metrics) {
      final vals = [
        for (final r in profile.referenceClips)
          if (r.metrics[m.key] != null) r.metrics[m.key]!,
      ];
      if (vals.isNotEmpty) hull[m.key] = (vals.reduce(math.min), vals.reduce(math.max));
    }
    final refs = profile.referenceClips;
    heldOut = [for (var i = 0; i < refs.length; i += 4) refs[i].metrics];
  }

  final AnalysisPack pack;
  final Profile _profile;

  /// The priority attribute (one per session).
  final String priority;

  /// Max accepted edits this session (5–10).
  final int limit;

  /// Loosens the hull by one spread for this session only.
  final bool chaos;
  final Meters meters;
  final DateTime Function() _clock;
  final String Function(String phase)? phaseLabel;

  /// The mixture being edited.
  final Map<String, ProfileMetric> mixture;

  /// Coach hull: per metric, the range of the coach's own strokes.
  final Map<String, (double, double)> hull = {};
  late final List<Map<String, double>> heldOut;
  final List<PileStroke> pile = [];
  final List<MixtureEdit> edits = [];

  Profile get profile => _profile;
  List<String> get priorityMetrics => [
        for (final k in pack.attributeMetrics[priority] ?? const <String>[])
          if (mixture.containsKey(k)) k,
      ];

  double get usableSeconds =>
      pile.where((s) => s.counts).fold(0.0, (a, s) => a + s.stroke.seconds);
  double get usableMinutes => usableSeconds / 60;
  bool get baselineMet => usableMinutes >= meters.good;
  bool get limitReached => edits.length >= limit;

  /// Status lines for adding one clip's strokes.
  List<String> addClip(String clipName, List<StrokeDetail> strokes,
      {List<StrokeMark> Function(StrokeDetail s)? marksFor}) {
    final before = usableMinutes;
    final added = [
      for (final s in strokes)
        PileStroke(stroke: s, clipName: clipName, marks: marksFor?.call(s)),
    ];
    pile.addAll(added);
    final clean = added.where((s) => s.stroke.usable).length;
    final dropout = strokes.map((s) => s.clipDropoutSeconds).fold(0.0, math.max);
    final out = <String>[];
    if (before >= meters.great && clean > 0) {
      out.add(CarneCopy.gravy(before.floor(), priority));
    }
    if (dropout > pack.maxImplementDropoutS) {
      out.add(CarneCopy.dropout(dropout));
    } else if (clean == 0) {
      out.add(CarneCopy.belowThreshold);
    } else {
      out.add(CarneCopy.found(strokes.length, clean, priority));
    }
    return out;
  }

  /// "Use anyway" for every stroke of [clipName].
  void useAnyway(String clipName) {
    for (final s in pile.where((s) => s.clipName == clipName)) {
      s.forced = true;
    }
  }

  /// "Ignore this clip".
  void ignore(String clipName) {
    for (final s in pile.where((s) => s.clipName == clipName)) {
      s.ignored = true;
    }
  }

  double _match(Map<String, double> values, Map<String, ProfileMetric> mix) {
    final keys = priorityMetrics;
    return styleMatchScore(
            {for (final k in keys) if (values[k] != null) k: values[k]!},
            {for (final k in keys) k: mix[k]!}) ??
        0;
  }

  /// Agreement of the mixture with the winning marks on the priority
  /// attribute: green strokes should match, red ones should not.
  double objective(Map<String, ProfileMetric> mix) {
    var sum = 0.0, n = 0;
    for (final s in pile.where((s) => s.counts)) {
      final label = s.winning(priority);
      if (label == null) continue;
      final m = _match(s.stroke.metrics, mix);
      sum += label == 'green' ? m : 1 - m;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  double _heldOutScore(Map<String, ProfileMetric> mix) {
    if (heldOut.isEmpty) return 1;
    final scores = [for (final h in heldOut) styleMatchScore(h, mix) ?? 0];
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  bool _insideHull(String metric, ProfileMetric m) {
    final h = hull[metric];
    if (h == null) return true;
    final margin = chaos ? m.spread : 0.0;
    return m.center >= h.$1 - margin - 1e-9 && m.center <= h.$2 + margin + 1e-9;
  }

  String _phase(String p) => (phaseLabel?.call(p) ?? p).toLowerCase();
  String _amount(double v, String unit) {
    final n = v.abs() < 10 ? v.abs().toStringAsFixed(1) : v.abs().toStringAsFixed(0);
    return unit == '°' ? '$n°' : '$n $unit';
  }

  /// Diagnose → propose one sparse update → evaluate → accept or reject.
  StepResult step() {
    if (limitReached) return const StepIdle('limit');
    if (!baselineMet) return const StepIdle('below baseline');
    final keys = priorityMetrics;
    if (keys.isEmpty) return const StepIdle('no metrics for priority');

    final greens = [
      for (final s in pile.where((s) => s.counts && s.winning(priority) == 'green')) s,
    ];
    final marked = pile.where((s) => s.counts && s.winning(priority) != null).toList();
    if (marked.isEmpty) return const StepIdle('no marks');

    final obj0 = objective(mixture);
    final held0 = _heldOutScore(mixture);
    final candidates = <(String type, String metric, ProfileMetric next, String why, String change)>[];

    // Diagnose: largest residual between green strokes and the mixture.
    final ranked = [
      for (final k in keys)
        () {
          final g = [for (final s in greens) if (s.stroke.metrics[k] != null) s.stroke.metrics[k]!];
          final mean = g.isEmpty ? null : g.reduce((a, b) => a + b) / g.length;
          final m = mixture[k]!;
          return (k, mean, mean == null ? 0.0 : (mean - m.center).abs() / m.spread, g);
        }(),
    ]..sort((a, b) => b.$3.compareTo(a.$3));

    for (final (k, mean, dist, g) in ranked) {
      final m = mixture[k]!;
      final def = pack.metrics.firstWhere((d) => d.key == k);
      if (mean != null && dist > 0.1) {
        final delta = (0.5 * (mean - m.center)).clamp(-m.spread, m.spread);
        final next = ProfileMetric(
            center: m.center + delta, spread: m.spread, weight: m.weight, unit: m.unit, phase: m.phase);
        final up = delta > 0;
        final dir = pack.wordsFor(k, up: up)[0];
        final agree = g.where((v) => up ? v > m.center : v < m.center).length;
        candidates.add((
          'shift_mean',
          k,
          next,
          CarneCopy.shiftWhy(priority, _amount(delta, def.unit), dir, _phase(m.phase),
              agree, g.length),
          CarneCopy.shifted(priority, _amount(delta, def.unit), dir, _phase(m.phase)),
        ));
      }
      final reds = pile
          .where((s) => s.counts)
          .map((s) => s.redCount(priority))
          .fold(0, math.max);
      if (reds >= 3) {
        final next = ProfileMetric(
            center: m.center, spread: m.spread * 0.85, weight: m.weight, unit: m.unit, phase: m.phase);
        candidates.add((
          'tighten_spread',
          k,
          next,
          CarneCopy.tightenWhy(priority, _phase(m.phase), reds),
          CarneCopy.tightened(priority, _phase(m.phase)),
        ));
      }
    }
    if (candidates.isEmpty) return const StepIdle('nothing to change');

    // Evaluate on the priority attribute + held-out coach strokes.
    (MixtureEdit, double)? best;
    var hullBlocked = false;
    for (final (type, k, next, why, change) in candidates) {
      final trial = {...mixture, k: next};
      final obj1 = objective(trial);
      if (obj1 < obj0 + 0.005) continue;
      if (_heldOutScore(trial) < held0 * 0.95) continue;
      if (!_insideHull(k, next)) {
        hullBlocked = true;
        continue;
      }
      if (best == null || obj1 > best.$2) {
        best = (
          MixtureEdit(
            type: type,
            metric: k,
            phase: next.phase,
            before: mixture[k]!,
            after: next,
            explanation: why,
            status: CarneCopy.accepted(change),
            objectiveBefore: obj0,
            objectiveAfter: obj1,
            at: _clock(),
          ),
          obj1
        );
      }
    }
    if (best == null) {
      return hullBlocked ? const StepRejected(CarneCopy.leftHull) : const StepIdle('no improvement');
    }
    final edit = best.$1;
    mixture[edit.metric] = edit.after;
    edits.add(edit);
    return StepAccepted(edit);
  }

  /// One-click undo of the last accepted edit.
  MixtureEdit? undo() {
    if (edits.isEmpty) return null;
    final e = edits.removeLast();
    mixture[e.metric] = e.before;
    return e;
  }

  /// `carne_asada/mixture_edits_vN.json` (research record; never needed for
  /// inference).
  Map<String, Object?> editsLog({required int version, required String sessionId}) => {
        'format': 'carne_asada/1',
        'version': version,
        'session_id': sessionId,
        'pack_id': pack.packId,
        'event_id': pack.eventId,
        'priority': priority,
        'limit': limit,
        'chaos': chaos,
        'usable_minutes': double.parse(usableMinutes.toStringAsFixed(2)),
        'hull': {for (final e in hull.entries) e.key: [e.value.$1, e.value.$2]},
        'edits': [for (final e in edits) e.toJson()],
      };
}
