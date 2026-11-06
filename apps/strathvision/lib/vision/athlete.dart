import 'dart:math' as math;

import 'person_detector.dart';

/// Which person to follow in a clip, and how to turn the picture upright.
///
/// The person is the detection containing ([x], [y]) (0..1 of the turned
/// view) at sampled frame [frame]: a tap, or the automatic pick. Tracking
/// is deterministic, so the same target always selects the same person.
class AthleteTarget {
  const AthleteTarget({required this.quarterTurns, required this.frame, required this.x, required this.y});
  final int quarterTurns;
  final int frame;
  final double x, y;

  Map<String, Object?> toJson() => {'quarter_turns': quarterTurns, 'frame': frame, 'x': x, 'y': y};
  factory AthleteTarget.fromJson(Map<String, Object?> j) => AthleteTarget(
        quarterTurns: (j['quarter_turns'] as num).toInt(),
        frame: (j['frame'] as num).toInt(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is AthleteTarget &&
      other.quarterTurns == quarterTurns &&
      other.frame == frame &&
      other.x == x &&
      other.y == y;
  @override
  int get hashCode => Object.hash(quarterTurns, frame, x, y);
}

/// How upright a person looks to the pose model, 0..1: detector score ×
/// pose presence × how vertical the hips→shoulders line is (cos⁴ of its
/// angle from straight up, 0 when it points sideways or down).
/// [landmarks] are the pose model's 39 × (x, y, z, vis, presence) in input
/// pixels of a crop around the person (uniform scale, so angles hold).
double uprightScore(PersonBox box, double presence, List<double> landmarks) {
  double c(int i, int k) => landmarks[i * 5 + k];
  final vx = (c(11, 0) + c(12, 0) - c(23, 0) - c(24, 0)) / 2;
  final vy = (c(11, 1) + c(12, 1) - c(23, 1) - c(24, 1)) / 2;
  final len = math.sqrt(vx * vx + vy * vy);
  if (len == 0) return 0;
  final cos = math.max(0.0, -vy / len);
  return box.score * presence * cos * cos * cos * cos;
}

/// Orientation from per-turn upright scores summed over sampled frames:
/// unturned unless a turn is clearly better (its score more than twice the
/// unturned one); `sure` is false when the top two are close.
({int quarterTurns, bool sure}) chooseOrientation(Map<int, double> scores) {
  final up = scores[0] ?? 0;
  final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
  final pick = best.key != 0 && best.value > 2 * up ? best.key : 0;
  final top = scores[pick] ?? 0;
  final runnerUp = scores.entries.where((e) => e.key != pick).map((e) => e.value).fold(0.0, math.max);
  return (quarterTurns: pick, sure: top > 0 && runnerUp < 0.75 * top);
}

/// One sampled observation of a candidate: its box and, when the pose
/// model was confident, the wrists' centre relative to the hips in units
/// of torso length (null otherwise).
class CandidateSample {
  const CandidateSample(this.frame, this.box, this.presence, this.wrist, [this.data]);
  final int frame;
  final PersonBox box;
  final double presence;
  final (double, double)? wrist;

  /// Whatever the caller attached (the pose measured on this sample).
  final Object? data;
}

/// A person followed through the pick window by box overlap.
class Candidate {
  Candidate(this.id);
  final int id;
  final List<CandidateSample> samples = [];

  /// The caller's tracking state for this person (e.g. the pose region).
  Object? state;
  PersonBox get last => samples.last.box;

  /// Share of the window in which this person's pose was seen (0..1).
  double seen(int windowSamples) =>
      math.min(1.0, samples.where((s) => s.wrist != null).length / math.max(1, windowSamples));

  /// Hand movement: the range (10th–90th percentile, both axes) of the
  /// wrists' path relative to the hips, smoothed over three samples, in
  /// torso lengths. A range, not frame-to-frame travel: pose jitter on
  /// small or half-seen people looks like travel but not like a swing.
  double motion() {
    final w = [for (final s in samples) if (s.wrist != null) s.wrist!];
    if (w.length < 3) return 0;
    final sm = [
      for (var i = 0; i < w.length; i++)
        () {
          final a = math.max(0, i - 1), b = math.min(w.length - 1, i + 1);
          var x = 0.0, y = 0.0;
          for (var j = a; j <= b; j++) {
            x += w[j].$1;
            y += w[j].$2;
          }
          return (x / (b - a + 1), y / (b - a + 1));
        }(),
    ];
    double spread(List<double> v) {
      v.sort();
      return v[(v.length * 0.9).floor().clamp(0, v.length - 1)] - v[(v.length * 0.1).floor()];
    }

    return spread([for (final p in sm) p.$1]) + spread([for (final p in sm) p.$2]);
  }

  /// Median box height (0..1 of the view).
  double get height {
    final h = [for (final s in samples) s.box.height]..sort();
    return h[h.length ~/ 2];
  }

  /// Median box centre across (0..1 of the view).
  double get centreX {
    final x = [for (final s in samples) s.box.cx]..sort();
    return x[x.length ~/ 2];
  }

  /// Cut off by the left or right edge of the picture in most samples.
  bool get atSideEdge =>
      samples.where((s) => s.box.x1 <= 0.005 || s.box.x2 >= 0.995).length * 2 > samples.length;

  /// How likely this is the athlete: the person the camera is filming is
  /// seen throughout, large, near the centre and not cut off by the edge,
  /// and moves their hands over a wide range. Seen in under 30% of the
  /// window scores zero. [tallest] is the largest candidate height in the
  /// window. (A body cut off by the edge also gives unreliable hands, which
  /// look like movement.)
  double score(int windowSamples, double tallest) {
    final seenShare = seen(windowSamples);
    if (seenShare < 0.3 || tallest <= 0) return 0;
    return seenShare *
        math.sqrt(height / tallest) *
        (1 - (centreX - 0.5).abs()) *
        (atSideEdge ? 0.5 : 1) *
        (0.5 + motion());
  }

  /// This candidate's box at [frame], or the nearest earlier one.
  PersonBox? boxAt(int frame) {
    PersonBox? b;
    for (final s in samples) {
      if (s.frame > frame) break;
      b = s.box;
    }
    return b ?? (samples.isEmpty ? null : samples.first.box);
  }
}

/// How well detection [d] continues a person last seen at [last]: similar
/// height (0.5–2×) and overlapping or close (centre within 0.65 box
/// sizes); higher is better, null when it cannot be the same person. A
/// swing changes a chopper's box shape a lot between samples, so overlap
/// alone would split them into fragments.
double? continuity(PersonBox last, PersonBox d) {
  final ratio = d.height / math.max(last.height, 1e-3);
  if (ratio < 0.5 || ratio > 2) return null;
  final dist = math.sqrt(math.pow((d.cx - last.cx) / math.max(last.width, 0.05), 2) +
      math.pow((d.cy - last.cy) / math.max(last.height, 0.05), 2));
  final overlap = last.iou(d);
  if (overlap < 0.15 && dist > 0.65) return null;
  return overlap + 0.35 * math.max(0, 1 - dist);
}

/// Which candidate each detection continues ([continuity], greedy, best
/// first); unmatched detections start new candidates (appended). Returns
/// one candidate index per detection.
List<int> assignDetections(List<Candidate> candidates, List<PersonBox> boxes) {
  final pairs = <(double, int, int)>[];
  for (var c = 0; c < candidates.length; c++) {
    if (candidates[c].samples.isEmpty) continue;
    for (var d = 0; d < boxes.length; d++) {
      final k = continuity(candidates[c].last, boxes[d]);
      if (k != null) pairs.add((k, c, d));
    }
  }
  pairs.sort((a, b) => b.$1.compareTo(a.$1));
  final out = List<int>.filled(boxes.length, -1);
  final usedC = <int>{};
  for (final (_, c, d) in pairs) {
    if (usedC.contains(c) || out[d] >= 0) continue;
    usedC.add(c);
    out[d] = c;
  }
  for (var d = 0; d < boxes.length; d++) {
    if (out[d] >= 0) continue;
    candidates.add(Candidate(candidates.length));
    out[d] = candidates.length - 1;
  }
  return out;
}

/// [assignDetections], then records each detection as a sample.
void linkDetections(List<Candidate> candidates, int frame, List<PersonBox> boxes,
    List<double> presence, List<(double, double)?> wrists, [List<Object?>? data]) {
  final who = assignDetections(candidates, boxes);
  for (var d = 0; d < boxes.length; d++) {
    candidates[who[d]].samples.add(CandidateSample(frame, boxes[d], presence[d], wrists[d], data?[d]));
  }
}

/// The automatic pick: the candidate most likely to be the athlete
/// ([Candidate.score]). `ambiguous` when the runner-up scores at least
/// 75% as high (two people framed alike), or when nobody was seen enough.
({Candidate? pick, bool ambiguous}) pickAthlete(List<Candidate> candidates, int windowSamples) {
  final seen = [for (final c in candidates) if (c.samples.isNotEmpty) c];
  if (seen.isEmpty) return (pick: null, ambiguous: true);
  final tallest = seen.map((c) => c.height).reduce(math.max);
  final scored = [for (final c in seen) (c.score(windowSamples, tallest), c)]
    ..sort((a, b) => b.$1.compareTo(a.$1));
  if (scored.first.$1 <= 0) return (pick: null, ambiguous: true);
  final second = scored.length > 1 ? scored[1].$1 : 0.0;
  return (pick: scored.first.$2, ambiguous: second >= 0.75 * scored.first.$1);
}

/// The candidate a target selects: the one whose box at the target frame
/// contains the point (the smallest such box), else the nearest box centre.
Candidate? selectByPoint(List<Candidate> candidates, int frame, double x, double y) {
  Candidate? best;
  var bestKey = double.infinity;
  for (final c in candidates) {
    final b = c.boxAt(frame);
    if (b == null) continue;
    final key = b.contains(x, y)
        ? b.width * b.height
        : 10 + math.sqrt(math.pow(b.cx - x, 2) + math.pow(b.cy - y, 2));
    if (key < bestKey) {
      bestKey = key;
      best = c;
    }
  }
  return best;
}

/// Wrists' centre relative to the hips' centre, in torso lengths, from the
/// pose model's landmarks (input pixels of a uniform-scale crop).
(double, double)? wristsFromHips(List<double> landmarks) {
  double c(int i, int k) => landmarks[i * 5 + k];
  final hx = (c(23, 0) + c(24, 0)) / 2, hy = (c(23, 1) + c(24, 1)) / 2;
  final sx = (c(11, 0) + c(12, 0)) / 2, sy = (c(11, 1) + c(12, 1)) / 2;
  final torso = math.sqrt(math.pow(sx - hx, 2) + math.pow(sy - hy, 2));
  if (torso < 1e-6) return null;
  return (((c(15, 0) + c(16, 0)) / 2 - hx) / torso, ((c(15, 1) + c(16, 1)) / 2 - hy) / torso);
}

/// The detection that continues following [last] (0..1 view boxes): it
/// must be of similar height (0.5–2×) and overlap or sit close; the best
/// by overlap and closeness. With [typicalHeight] (the athlete's usual
/// detected height), detections under 0.6× or over 1.8× of it are not
/// the athlete: a judge or onlooker nearby is smaller in the picture.
/// Null when nothing qualifies, or when two detections are nearly as good
/// (never guess between people).
PersonBox? continueTrack(PersonBox last, List<PersonBox> detections, {double? typicalHeight}) {
  final ranked = <(double, PersonBox)>[
    for (final d in detections)
      if (typicalHeight == null || _usualSize(d, typicalHeight))
        if (continuity(last, d) case final k?) (k + 0.1 * d.score, d),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  if (ranked.isEmpty) return null;
  if (ranked.length > 1 && ranked[0].$1 - ranked[1].$1 < 0.12) return null;
  return ranked.first.$2;
}

bool _usualSize(PersonBox d, double typicalHeight) =>
    d.height >= 0.6 * typicalHeight && d.height <= 1.8 * typicalHeight;

/// The athlete again after they have been lost for a while (climbing past
/// a pole, hidden behind it): someone of their usual size roughly above
/// or below where they were last seen (centre within 1.5 box widths
/// sideways; any height in the picture, as a springboard chopper climbs).
/// The nearest sideways wins; null when nobody fits or two fit about
/// equally well.
PersonBox? findAgain(PersonBox last, double typicalHeight, List<PersonBox> detections) {
  final w = math.max(last.width, 0.02);
  final ranked = <(double, PersonBox)>[
    for (final d in detections)
      if (_usualSize(d, typicalHeight) && (d.cx - last.cx).abs() <= 1.5 * w)
        ((d.cx - last.cx).abs() / w + 0.5 * (d.height / typicalHeight - 1).abs(), d),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (ranked.isEmpty) return null;
  if (ranked.length > 1 && ranked[1].$1 - ranked[0].$1 < 0.25) return null;
  return ranked.first.$2;
}

/// [b] moved so its centre is at ([cx], [cy]), same size.
PersonBox movedTo(PersonBox b, double cx, double cy) =>
    PersonBox(cx - b.width / 2, cy - b.height / 2, cx + b.width / 2, cy + b.height / 2, b.score);

/// The median of [xs] (not empty).
double median(List<double> xs) {
  final s = [...xs]..sort();
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}
