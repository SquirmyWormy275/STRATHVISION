import 'dart:math' as math;

import 'engine.dart';
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

  static String raiseExemplarWhy(String where) =>
      'Raised the weight of the residual exemplar from $where; it matched the '
      'current priority better than the existing mean.';
  static String addExemplarWhy(String where) =>
      'Added a residual exemplar from $where; it matched the current priority '
      'better than the existing mean.';
  static String dropExemplarWhy(String plainDir) =>
      'Dropped one low-confidence exemplar that was pulling the mean $plainDir.';
  static String raiseWeightWhy(String attr, String metric, int close, int greens) =>
      'Raised the weight of ${metric.toLowerCase()} within ${attr.toLowerCase()} because '
      '$close of your last $greens green marks were closest on it.';
  static String exemplarChange(String attr, String verb) =>
      '${attr[0].toUpperCase()}${attr.substring(1)} exemplar $verb.';
  static String weightChange(String attr, String metric) =>
      '$attr now leans more on ${metric.toLowerCase()}.';
  static String mergedCoach(int n, String who) =>
      'Added $n coach strokes from $who to the coach hull.';

  /// "the 14-second mark of the Gurr clip".
  static String where(double seconds, String clip) =>
      'the ${seconds.round()}-second mark of the $clip clip';
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
    this.exemplar,
    this.mixtureBefore = const {},
    this.exemplarsBefore = const [],
  });

  /// `shift_mean`, `tighten_spread`, `raise_weight`, `add_exemplar`,
  /// `raise_exemplar`, or `drop_exemplar`.
  final String type;
  final String metric;
  final String phase;
  final ProfileMetric before, after;

  /// One sentence, exact style (DECISIONS.md).
  final String explanation;
  final String status;
  final double objectiveBefore, objectiveAfter;
  final DateTime at;

  /// The exemplar added, raised, or dropped (exemplar edits).
  final ReferenceClip? exemplar;

  /// State before the edit, for one-click undo.
  final Map<String, ProfileMetric> mixtureBefore;
  final List<ReferenceClip> exemplarsBefore;

  Map<String, Object?> toJson() => {
        'type': type,
        'metric': metric,
        'phase': phase,
        'before': before.toJson(),
        'after': after.toJson(),
        if (exemplar != null) 'exemplar': exemplar!.toJson(),
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
/// phase-conditioned mixture (per-metric center/spread/weight) and its
/// residual exemplars under hard bounds; the phone never runs this.
class CarneSession {
  CarneSession({
    required this.pack,
    required Profile profile,
    required String priority,
    this.limit = 5,
    this.chaos = false,
    this.meters = const Meters(),
    DateTime Function()? clock,
    this.phaseLabel,
    this.metricLabel,
  })  : assert(limit >= 5 && limit <= 10),
        _clock = clock ?? DateTime.now,
        _profile = profile,
        _priority = priority,
        mixture = Map.of(profile.metrics),
        exemplars = [for (final r in profile.referenceClips) if (r.exemplar) r],
        coachStrokes = [for (final r in profile.referenceClips) if (!r.exemplar) r] {
    _rebuildHull();
  }

  final AnalysisPack pack;
  final Profile _profile;

  /// The priority attribute (one per session). Can change only before the
  /// first accepted edit.
  String _priority;
  String get priority => _priority;
  set priority(String v) {
    if (edits.isNotEmpty) throw StateError('Priority is fixed once an edit is accepted.');
    _priority = v;
  }

  /// Max accepted edits this session (5–10).
  final int limit;

  /// Loosens the hull by one spread for this session only. Off by default.
  bool chaos;
  final Meters meters;
  final DateTime Function() _clock;
  final String Function(String phase)? phaseLabel;
  final String Function(String metric)? metricLabel;

  /// The mixture being edited.
  final Map<String, ProfileMetric> mixture;

  /// Residual exemplars: extra mixture components from marked strokes.
  final List<ReferenceClip> exemplars;

  /// The coach's own strokes: define the hull and the held-out set.
  final List<ReferenceClip> coachStrokes;

  /// Coach hull: per metric, the range of the coach's own strokes.
  final Map<String, (double, double)> hull = {};
  List<Map<String, double>> heldOut = const [];
  double _initialHeldOutScore = 0;
  final List<PileStroke> pile = [];
  final List<MixtureEdit> edits = [];

  void _rebuildHull() {
    hull.clear();
    for (final m in pack.metrics) {
      final vals = [
        for (final r in coachStrokes)
          if (r.metrics[m.key] != null) r.metrics[m.key]!,
      ];
      if (vals.isNotEmpty) hull[m.key] = (vals.reduce(math.min), vals.reduce(math.max));
    }
    heldOut = [for (var i = 0; i < coachStrokes.length; i += 4) coachStrokes[i].metrics];
    _initialHeldOutScore = _heldOutScore(mixture);
  }

  /// Adds another package's coach strokes (same event) to the hull and the
  /// held-out set. Returns how many were added.
  int mergeCoachStrokes(Profile other) {
    if (other.packId != pack.packId || other.eventId != pack.eventId) return 0;
    final have = {for (final r in coachStrokes) r.clipId};
    final add = [
      for (final r in other.referenceClips)
        if (!r.exemplar && !have.contains(r.clipId)) r,
    ];
    coachStrokes.addAll(add);
    _rebuildHull();
    return add.length;
  }

  Profile get profile => _profile;

  /// The profile as edited: mixture + coach strokes + exemplars.
  Profile get editedProfile => Profile(
        profileId: _profile.profileId,
        version: _profile.version,
        coachName: _profile.coachName,
        packId: _profile.packId,
        eventId: _profile.eventId,
        metricSchemaVersion: _profile.metricSchemaVersion,
        createdAt: _profile.createdAt,
        sourceClipCount: _profile.sourceClipCount,
        minClipsMet: _profile.minClipsMet,
        selfConsistencyPassed: _profile.selfConsistencyPassed,
        notes: _profile.notes,
        metrics: Map.of(mixture),
        referenceClips: [
          ...coachStrokes,
          ...exemplars,
        ],
      );

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

  /// Match of [values] on the priority attribute: per metric, the better of
  /// the mixture component and the best weighted exemplar; weight-averaged.
  double _match(Map<String, double> values, Map<String, ProfileMetric> mix,
      List<ReferenceClip> ex) {
    return styleMatchScore(values, {for (final k in priorityMetrics) k: mix[k]!},
        exemplars: ex) ?? 0;
  }

  /// Agreement of the mixture with the winning marks on the priority
  /// attribute: green strokes should match, red ones should not.
  double objective(Map<String, ProfileMetric> mix, [List<ReferenceClip>? ex]) {
    final e = ex ?? exemplars;
    var sum = 0.0, n = 0;
    for (final s in pile.where((s) => s.counts)) {
      final label = s.winning(priority);
      if (label == null) continue;
      final m = _match(s.stroke.metrics, mix, e);
      sum += label == 'green' ? m : 1 - m;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  double _heldOutScore(Map<String, ProfileMetric> mix, [List<ReferenceClip>? ex]) {
    if (heldOut.isEmpty) return 1;
    final scores = [for (final h in heldOut) styleMatchScore(h, mix, exemplars: ex ?? exemplars) ?? 0];
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  bool _insideHull(String metric, double value, double spread) {
    final h = hull[metric];
    if (h == null) return true;
    final margin = chaos ? spread : 0.0;
    return value >= h.$1 - margin - 1e-9 && value <= h.$2 + margin + 1e-9;
  }

  bool _exemplarInsideHull(ReferenceClip e) => priorityMetrics.every((k) =>
      e.metrics[k] == null || _insideHull(k, e.metrics[k]!, mixture[k]!.spread));

  String _phase(String p) => (phaseLabel?.call(p) ?? p).toLowerCase();
  String _label(String k) => metricLabel?.call(k) ?? k.replaceAll('_', ' ');
  String _amount(double v, String unit) {
    final n = v.abs() < 10 ? v.abs().toStringAsFixed(1) : v.abs().toStringAsFixed(0);
    return unit == '°' ? '$n°' : '$n $unit';
  }

  double _strokeConfidence(PileStroke s) {
    final d = s.stroke.detail.outcome;
    if (d is! AnalysisSuccess) return 0;
    final cs = [
      for (final k in priorityMetrics)
        if (d.vector.metrics[k] != null) d.vector.metrics[k]!.confidence,
    ];
    return cs.isEmpty ? 0 : cs.reduce((a, b) => a + b) / cs.length;
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
    final held0 = _initialHeldOutScore;
    final cands = <_Candidate>[];

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

    final reds = pile.where((s) => s.counts).map((s) => s.redCount(priority)).fold(0, math.max);
    for (final (k, mean, dist, g) in ranked) {
      final m = mixture[k]!;
      final def = pack.metrics.firstWhere((d) => d.key == k);
      // 1. Shift μ.
      if (mean != null && dist > 0.1) {
        final delta = (0.5 * (mean - m.center)).clamp(-m.spread, m.spread);
        final next = ProfileMetric(
            center: m.center + delta, spread: m.spread, weight: m.weight, unit: m.unit, phase: m.phase);
        final up = delta > 0;
        final dir = pack.wordsFor(k, up: up)[0];
        final agree = g.where((v) => up ? v > m.center : v < m.center).length;
        cands.add(_Candidate(
          type: 'shift_mean',
          metric: k,
          mix: {...mixture, k: next},
          why: CarneCopy.shiftWhy(priority, _amount(delta, def.unit), dir, _phase(m.phase), agree, g.length),
          change: CarneCopy.shifted(priority, _amount(delta, def.unit), dir, _phase(m.phase)),
          hullOk: _insideHull(k, next.center, next.spread),
        ));
      }
      // 2. Scale one covariance direction.
      if (reds >= 3) {
        final next = ProfileMetric(
            center: m.center, spread: m.spread * 0.85, weight: m.weight, unit: m.unit, phase: m.phase);
        cands.add(_Candidate(
          type: 'tighten_spread',
          metric: k,
          mix: {...mixture, k: next},
          why: CarneCopy.tightenWhy(priority, _phase(m.phase), reds),
          change: CarneCopy.tightened(priority, _phase(m.phase)),
        ));
      }
      // 3. Adjust w (only meaningful with more than one metric).
      if (keys.length > 1 && g.isNotEmpty && m.weight < 3) {
        final close = g.where((v) => (v - m.center).abs() <= m.spread).length;
        final next = ProfileMetric(
            center: m.center, spread: m.spread, weight: math.min(3.0, m.weight * 1.25),
            unit: m.unit, phase: m.phase);
        cands.add(_Candidate(
          type: 'raise_weight',
          metric: k,
          mix: {...mixture, k: next},
          why: CarneCopy.raiseWeightWhy(priority, _label(k), close, g.length),
          change: CarneCopy.weightChange(priority, _label(k)),
        ));
      }
    }

    // 4. Add or raise one residual exemplar: the green stroke the mixture
    //    explains worst.
    final top = ranked.first.$1;
    if (greens.isNotEmpty) {
      final worst = (greens.toList()
            ..sort((a, b) => _match(a.stroke.metrics, mixture, exemplars)
                .compareTo(_match(b.stroke.metrics, mixture, exemplars))))
          .first;
      final id = '${worst.stroke.clipId}@${worst.stroke.index}';
      final where = CarneCopy.where(worst.stroke.midSeconds, worst.clipName);
      final existing = exemplars.indexWhere((e) => e.clipId == id);
      if (existing < 0) {
        final e = ReferenceClip(
          clipId: id,
          metrics: {for (final k in keys) if (worst.stroke.metrics[k] != null) k: worst.stroke.metrics[k]!},
          exemplar: true,
          weight: 0.5,
          confidence: _strokeConfidence(worst),
          source: where,
        );
        cands.add(_Candidate(
          type: 'add_exemplar',
          metric: top,
          mix: mixture,
          ex: [...exemplars, e],
          exemplar: e,
          why: CarneCopy.addExemplarWhy(where),
          change: CarneCopy.exemplarChange(priority.toLowerCase(), 'added from $where'),
          hullOk: _exemplarInsideHull(e),
        ));
      }
    }
    for (var i = 0; i < exemplars.length; i++) {
      final e = exemplars[i];
      if (e.weight < 1 && e.confidence >= lowExemplarConfidence) {
        final raised = e.withWeight(math.min(1.0, e.weight + 0.25));
        final where = e.source ?? 'a marked stroke';
        cands.add(_Candidate(
          type: 'raise_exemplar',
          metric: top,
          mix: mixture,
          ex: [...exemplars]..[i] = raised,
          exemplar: raised,
          why: CarneCopy.raiseExemplarWhy(where),
          change: CarneCopy.exemplarChange(priority.toLowerCase(), 'from $where weighted up'),
        ));
      }
      // 5. Remove one low-confidence exemplar.
      if (e.confidence < lowExemplarConfidence) {
        final x = e.metrics[top];
        final up = x != null && x > mixture[top]!.center;
        cands.add(_Candidate(
          type: 'drop_exemplar',
          metric: top,
          mix: mixture,
          ex: [...exemplars]..removeAt(i),
          exemplar: e,
          why: CarneCopy.dropExemplarWhy(pack.wordsFor(top, up: up)[1]),
          change: CarneCopy.exemplarChange(priority.toLowerCase(), 'dropped'),
        ));
      }
    }
    if (cands.isEmpty) return const StepIdle('nothing to change');

    // Evaluate on the priority attribute + held-out coach strokes.
    _Candidate? best;
    double bestObj = obj0;
    var hullBlocked = false;
    for (final c in cands) {
      final obj1 = objective(c.mix, c.ex ?? exemplars);
      if (obj1 < obj0 + 0.005) continue;
      if (_heldOutScore(c.mix, c.ex) < held0 * 0.95) continue;
      if (!c.hullOk) {
        hullBlocked = true;
        continue;
      }
      if (best == null || obj1 > bestObj) {
        best = c;
        bestObj = obj1;
      }
    }
    if (best == null) {
      return hullBlocked ? const StepRejected(CarneCopy.leftHull) : const StepIdle('no improvement');
    }
    final m0 = mixture[best.metric]!;
    final edit = MixtureEdit(
      type: best.type,
      metric: best.metric,
      phase: m0.phase,
      before: m0,
      after: best.mix[best.metric]!,
      explanation: best.why,
      status: CarneCopy.accepted(best.change),
      objectiveBefore: obj0,
      objectiveAfter: bestObj,
      at: _clock(),
      exemplar: best.exemplar,
      mixtureBefore: Map.of(mixture),
      exemplarsBefore: List.of(exemplars),
    );
    final acceptedMix = Map<String, ProfileMetric>.of(best.mix);
    mixture
      ..clear()
      ..addAll(acceptedMix);
    if (best.ex != null) {
      exemplars
        ..clear()
        ..addAll(best.ex!);
    }
    edits.add(edit);
    return StepAccepted(edit);
  }

  /// One-click undo of the last accepted edit.
  MixtureEdit? undo() {
    if (edits.isEmpty) return null;
    final e = edits.removeLast();
    mixture
      ..clear()
      ..addAll(e.mixtureBefore);
    exemplars
      ..clear()
      ..addAll(e.exemplarsBefore);
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
        'coach_strokes': coachStrokes.length,
        'hull': {for (final e in hull.entries) e.key: [e.value.$1, e.value.$2]},
        'exemplars': [for (final e in exemplars) e.toJson()],
        'edits': [for (final e in edits) e.toJson()],
      };
}

/// Exemplars below this measurement confidence may be dropped, never raised.
const lowExemplarConfidence = 0.6;

class _Candidate {
  _Candidate({
    required this.type,
    required this.metric,
    required this.mix,
    required this.why,
    required this.change,
    this.ex,
    this.exemplar,
    this.hullOk = true,
  });
  final String type;
  final String metric;
  final Map<String, ProfileMetric> mix;
  final List<ReferenceClip>? ex;
  final ReferenceClip? exemplar;
  final String why;
  final String change;
  final bool hullOk;
}
