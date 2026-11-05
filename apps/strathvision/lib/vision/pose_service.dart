import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'athlete.dart';
import 'blazepose.dart';
import 'frame_grabber.dart';
import 'person_detector.dart';
import 'pose_math.dart';

/// A pose track and how it was obtained: who was followed, and what to
/// offer the user if that was the wrong person.
class AthleteTrack {
  const AthleteTrack({
    required this.track,
    required this.target,
    required this.ambiguous,
    required this.orientationSure,
    required this.candidatesFrame,
    required this.candidates,
  });

  final PoseTrack track;

  /// The person followed (pass it back to re-track the same way), or null
  /// when nobody was found.
  final AthleteTarget? target;

  /// The automatic pick could not tell people apart (two choppers in a
  /// heat, or nobody clearly chopping): ask the user to tap the athlete.
  final bool ambiguous;

  /// The picture's orientation was clear (false: offer to rotate).
  final bool orientationSure;

  /// Clip frame whose people are offered for correction, and those people
  /// (0..1 of the view turned by [target]'s quarter-turns).
  final int candidatesFrame;
  final List<PersonBox> candidates;
}

/// Loads the frame offered for choosing the athlete (injectable for tests).
typedef PeopleLoader = Future<PeopleFrame?> Function(ClipSource clip, int frame, int quarterTurns);

/// One frame offered for choosing the athlete: a display image (RGBA,
/// turned upright) and the people found in it (0..1 of that image).
class PeopleFrame {
  const PeopleFrame({required this.rgba, required this.width, required this.height, required this.people});
  final Uint8List rgba;
  final int width, height;
  final List<PersonBox> people;
}

class _Seen {
  const _Seen(this.pose, this.xy);
  final PoseFrame pose;
  final List<double> xy;
}

/// Turns a clip into a real 3D pose track on this device: find the
/// athlete (person detector + who is chopping), track them, run BlazePose
/// on them, map to the engine's joints.
class PoseService {
  PoseService({this.maxSampleRate = 15, this.maxSamples = maxPoseSamples, this.quarterTurns});

  /// Frames per second analysed (clips are sampled down to this).
  final double maxSampleRate;
  final int maxSamples;

  /// Clockwise quarter-turns to apply before tracking, overriding the
  /// automatic orientation (null: automatic). The file's own rotation
  /// metadata is always applied first.
  final int? quarterTurns;

  static final PoseService instance = PoseService();
  static const modelAsset = 'assets/models/pose_landmark_full.onnx';
  static const detectorAsset = 'assets/models/yolox_nano.onnx';

  /// Seconds at the start in which everyone is followed to find who is
  /// chopping.
  static const pickWindowSeconds = 4.0;

  /// People followed during the pick, by detector score.
  static const maxCandidates = 5;

  /// While following, the detector re-checks every this many samples.
  static const recheckEvery = 15;

  /// Progress of the running track (0..1), null when idle.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  BlazePose? _model;
  PersonDetector? _detector;
  final Map<String, AthleteTrack> _cache = {};

  Future<BlazePose> _load() async =>
      _model ??= BlazePose.load((await rootBundle.load(modelAsset)).buffer.asUint8List());
  Future<PersonDetector> _loadDetector() async => _detector ??=
      PersonDetector.load((await rootBundle.load(detectorAsset)).buffer.asUint8List());

  /// The pose track for [clip]; see [trackAthlete].
  Future<PoseTrack> track(ClipSource clip,
          {void Function(double progress)? onProgress,
          String? sourceKey,
          AthleteTarget? target,
          void Function(int frame, List<double> xy, int width, int height)? onLandmarks}) async =>
      (await trackAthlete(clip,
              onProgress: onProgress, sourceKey: sourceKey, target: target, onLandmarks: onLandmarks))
          .track;

  /// Finds and tracks the athlete in [clip] (cached per source, duration
  /// and target). With [target], follows that person instead of the
  /// automatic pick. [onLandmarks] receives each tracked frame's 2D
  /// landmarks in frame pixels (33 × x, y) — for overlays and diagnostics.
  Future<AthleteTrack> trackAthlete(ClipSource clip,
      {void Function(double progress)? onProgress,
      String? sourceKey,
      AthleteTarget? target,
      void Function(int frame, List<double> xy, int width, int height)? onLandmarks}) async {
    final key = '${sourceKey ?? clip.path}|${clip.durationMs}|${clip.fps}|$quarterTurns|'
        '${target == null ? '' : target.toJson()}';
    final cached = _cache[key];
    if (cached != null && onLandmarks == null) return cached;
    final model = await _load();
    final detector = await _loadDetector();
    final empty = AthleteTrack(
        track: PoseTrack(fps: clip.fps, frames: const []),
        target: null,
        ambiguous: true,
        orientationSure: true,
        candidatesFrame: 0,
        candidates: const []);

    // Orientation: the target's, the override, or detected.
    var orientationSure = true;
    int q;
    if (target != null) {
      q = target.quarterTurns % 4;
    } else if (quarterTurns != null) {
      q = quarterTurns! % 4;
    } else {
      final o = await _orientation(model, detector, clip);
      q = o.quarterTurns;
      orientationSure = o.sure;
    }

    final grabber = await FrameGrabber.open(clip.path);
    if (grabber == null) return empty;
    try {
      final n = clip.frameCount;
      var step = math.max(1, (clip.fps / maxSampleRate).round());
      step = math.max(step, (n / maxSamples).ceil());
      final frames = <PoseFrame>[];
      void emit(int f, _Seen s, int w, int h) {
        frames.add(s.pose);
        onLandmarks?.call(f, s.xy, w, h);
      }

      // 1. Pick window: follow everyone, then choose who is chopping.
      final candidates = <Candidate>[];
      final boxesAt = <int, List<PersonBox>>{};
      var windowEnd = math.min(n, (pickWindowSeconds * clip.fps).round());
      var windowSamples = 0;
      Candidate? chosen;
      var ambiguous = false;
      var f = 0, w0 = 0, h0 = 0;
      for (; f < n; f += step) {
        final img = await grabber.frameIndex(f, fps: clip.fps);
        if (img == null) continue;
        w0 = img.width;
        h0 = img.height;
        final view = FrameView(img.width, img.height, q);
        final people = (await detector.detect(img, quarterTurns: q, threshold: 0.25))
            .take(maxCandidates)
            .toList();
        boxesAt[f] = people;
        windowSamples++;
        // Detections identify people; each person's pose comes from their
        // own landmark region carried between samples (as MediaPipe does),
        // falling back to their box when new or lost.
        final who = assignDetections(candidates, people);
        for (var d = 0; d < people.length; d++) {
          final c = candidates[who[d]];
          final carried = c.state is Roi && c.samples.isNotEmpty && c.samples.last.frame == f - step
              ? c.state! as Roi
              : null;
          final useCarried = carried != null && _inside(people[d], carried, view);
          Future<BlazePoseOutput> poseAt(Roi r) => model.infer(
              cropToInput(img.bgra, img.width, img.height, r, stride: img.stride, quarterTurns: q));
          Roi roi;
          BlazePoseOutput out;
          if (useCarried) {
            roi = carried;
            out = await poseAt(roi);
            if (out.presence < 0.5) (roi, out) = await _fromBox(people[d], view, poseAt);
          } else {
            (roi, out) = await _fromBox(people[d], view, poseAt);
          }
          final ok = out.presence >= 0.5;
          c.state = ok ? roiFromLandmarks(out.landmarks, roi) : null;
          c.samples.add(CandidateSample(
              f,
              people[d],
              out.presence,
              ok ? wristsFromHips(out.landmarks) : null,
              ok
                  ? _Seen(poseFrameFromBlazePose(f, out.world, out.visibility, out.landmarkPresence),
                      _frameXy(out.landmarks, roi, view))
                  : null));
        }
        onProgress?.call((f + 1) / n);
        progress.value = (f + 1) / n;
        if (f + step < windowEnd) continue;
        assert(() {
          final tallest = candidates.isEmpty ? 0.0 : candidates.map((c) => c.height).reduce(math.max);
          debugPrint('PoseService pick ${clip.clipId} at f$f ($windowSamples samples): ${[
            for (final c in candidates)
              if (c.samples.length > 2)
                '#${c.id} n${c.samples.length} seen${c.seen(windowSamples).toStringAsFixed(2)} '
                    'h${c.height.toStringAsFixed(2)} x${c.centreX.toStringAsFixed(2)} '
                    'm${c.motion().toStringAsFixed(2)} s${c.score(windowSamples, tallest).toStringAsFixed(2)}'
          ]}');
          return true;
        }());
        if (target != null) {
          chosen = selectByPoint(candidates, target.frame, target.x, target.y);
        } else {
          final r = pickAthlete(candidates, windowSamples);
          chosen = r.pick;
          ambiguous = r.ambiguous;
        }
        // Nobody yet (e.g. walking in): keep looking, up to three windows.
        if (chosen == null && windowEnd < math.min(n, 3 * pickWindowSeconds * clip.fps)) {
          windowEnd = math.min(n, windowEnd + (pickWindowSeconds * clip.fps).round());
          continue;
        }
        // An empty opening does not make the rest of a recording empty.
        // Search fresh windows so a late entrant is not penalized by all
        // the earlier samples without a person. An explicit target still
        // fails rather than being silently assigned to a later athlete.
        if (target == null && chosen == null && windowEnd < n) {
          candidates.clear();
          boxesAt.clear();
          windowSamples = 0;
          windowEnd = math.min(n, windowEnd + (pickWindowSeconds * clip.fps).round());
          continue;
        }
        f += step;
        break;
      }
      if (chosen == null) return empty;
      for (final s in chosen.samples) {
        if (s.data case final _Seen seen) emit(s.frame, seen, w0, h0);
      }
      // The frame offered for correction: the chosen person's sample in
      // the middle of the window, with everyone detected there.
      final mid = chosen.samples[chosen.samples.length ~/ 2];
      final chosenTarget = target ??
          AthleteTarget(quarterTurns: q, frame: mid.frame, x: mid.box.cx, y: mid.box.cy);
      final offered = target?.frame ?? mid.frame;

      // 2. Follow the chosen person: pose region from their landmarks;
      // the detector re-checks who it is every second, and finds them
      // again (only near where they were) when the pose is lost.
      var last = chosen.last;
      Roi? roi = chosen.samples.last.frame == f - step && chosen.state is Roi ? chosen.state! as Roi : null;
      // The athlete's usual detected height (recent detections), and where
      // their pose region was when [last] was detected: between detector
      // checks [last] moves with the pose, so a lost athlete is looked for
      // where they went, not where the detector last saw them.
      final heights = [for (final s in chosen.samples) s.box.height];
      (double, double)? anchor = roi == null ? null : (roi.cx, roi.cy);
      (double, double)? seenAt = anchor;
      var sinceCheck = 0, lostFor = 0;
      for (; f < n; f += step) {
        final img = await grabber.frameIndex(f, fps: clip.fps);
        if (img == null) continue;
        final view = FrameView(img.width, img.height, q);
        Future<BlazePoseOutput> poseAt(Roi r) => model
            .infer(cropToInput(img.bgra, img.width, img.height, r, stride: img.stride, quarterTurns: q));
        var out = roi == null ? null : await poseAt(roi);
        final lost = out == null || out.presence < 0.5;
        if (lost || ++sinceCheck >= recheckEvery) {
          sinceCheck = 0;
          final typical = median(heights.length > 9 ? heights.sublist(heights.length - 9) : heights);
          final near = anchor != null && seenAt != null
              ? movedTo(last, last.cx + (seenAt.$1 - anchor.$1) / view.viewWidth,
                  last.cy + (seenAt.$2 - anchor.$2) / view.viewHeight)
              : last;
          final people = await detector.detect(img, quarterTurns: q, threshold: 0.25);
          var next = continueTrack(near, people, typicalHeight: typical);
          // Lost for over a second: look above and below (climbing).
          if (next == null && lost && lostFor * step / clip.fps >= 1) next = findAgain(near, typical, people);
          if (next != null) {
            last = next;
            heights.add(next.height);
            if (lost || roi == null || !_inside(next, roi, view)) {
              final (r, o) = await _fromBox(next, view, poseAt);
              roi = r;
              out = o;
            }
            anchor = (roi.cx, roi.cy);
            seenAt = anchor;
          } else if (lost) {
            // Lost and not found near `last`: no pose for this frame.
            roi = null;
            out = null;
          }
        }
        if (out != null && out.presence >= 0.5 && roi != null) {
          emit(f, _Seen(poseFrameFromBlazePose(f, out.world, out.visibility, out.landmarkPresence),
              _frameXy(out.landmarks, roi, view)), img.width, img.height);
          roi = roiFromLandmarks(out.landmarks, roi);
          seenAt = (roi.cx, roi.cy);
          lostFor = 0;
        } else {
          roi = null;
          lostFor++;
        }
        onProgress?.call((f + 1) / n);
        progress.value = (f + 1) / n;
      }
      final result = AthleteTrack(
        track: PoseTrack(fps: clip.fps, frames: frames),
        target: chosenTarget,
        ambiguous: target == null && ambiguous,
        orientationSure: orientationSure,
        candidatesFrame: offered,
        candidates: boxesAt[offered] ?? const [],
      );
      if (_cache.length > 32) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } finally {
      progress.value = null;
      await grabber.close();
    }
  }

  /// The people at clip frame [frame], turned by [quarterTurns], with a
  /// display image: what the athlete picker shows. Null when the frame
  /// cannot be decoded.
  Future<PeopleFrame?> peopleAt(ClipSource clip, int frame, int quarterTurns) async {
    final detector = await _loadDetector();
    final g = await FrameGrabber.open(clip.path);
    if (g == null) return null;
    try {
      final img = await g.frameAt(Duration(microseconds: (frame * 1e6 / clip.fps).round()), fps: clip.fps);
      if (img == null) return null;
      final people = await detector.detect(img, quarterTurns: quarterTurns, threshold: 0.25);
      final shown = viewRgba(img.bgra, img.width, img.height, stride: img.stride, quarterTurns: quarterTurns);
      return PeopleFrame(rgba: shown.rgba, width: shown.width, height: shown.height, people: people);
    } finally {
      await g.close();
    }
  }

  /// The pose model's region for a person box (0..1 of the view): a
  /// square 1.2× the box's longer side, on its centre.
  static Roi _roiFor(PersonBox b, FrameView view) => Roi(b.cx * view.viewWidth, b.cy * view.viewHeight,
      math.max(b.width * view.viewWidth, b.height * view.viewHeight) * 1.2);

  /// A pose for a person found by the detector: one pass on their box,
  /// then a second on the region their own landmarks give (MediaPipe's
  /// rule), which centres the body; a box that includes the implement
  /// leaves the body small and off-centre, and those first poses jump.
  static Future<(Roi, BlazePoseOutput)> _fromBox(
      PersonBox b, FrameView view, Future<BlazePoseOutput> Function(Roi) poseAt) async {
    final box = _roiFor(b, view);
    final first = await poseAt(box);
    if (first.presence < 0.5) return (box, first);
    final refined = roiFromLandmarks(first.landmarks, box);
    final second = await poseAt(refined);
    return second.presence >= 0.5 ? (refined, second) : (box, first);
  }

  /// Whether a person box's centre lies inside a pose region (same
  /// person).
  static bool _inside(PersonBox b, Roi r, FrameView view) {
    final x = b.cx * view.viewWidth, y = b.cy * view.viewHeight;
    return (x - r.cx).abs() <= r.size / 2 && (y - r.cy).abs() <= r.size / 2;
  }

  static List<double> _frameXy(List<double> landmarks, Roi roi, FrameView view) => [
        for (var i = 0; i < 33; i++) ...() {
          final (vx, vy) = roi.toFrame(landmarks[i * 5], landmarks[i * 5 + 1]);
          final (x, y) = view.toFrame(vx, vy);
          return [x, y];
        }(),
      ];

  /// Which clockwise quarter-turn shows people upright: on five frames
  /// spread across the clip, each turn's detected people are checked with
  /// the pose model (confident, and hips below shoulders). The pose model
  /// is reliable on upright people and unsure or wrong on lying ones, so
  /// the turn where it confidently sees upright people wins.
  Future<({int quarterTurns, bool sure})> _orientation(
      BlazePose model, PersonDetector detector, ClipSource clip) async {
    final g = await FrameGrabber.open(clip.path);
    if (g == null) return (quarterTurns: 0, sure: false);
    final scores = <int, double>{0: 0, 1: 0, 3: 0};
    try {
      for (var k = 0; k < 5; k++) {
        final img = await g.frameAt(
            Duration(milliseconds: (clip.durationMs * (k + 0.5) / 5).round()), fps: clip.fps);
        if (img == null) continue;
        for (final q in scores.keys.toList()) {
          final view = FrameView(img.width, img.height, q);
          var best = 0.0;
          for (final b in (await detector.detect(img, quarterTurns: q, threshold: 0.25)).take(5)) {
            final out = await model.infer(cropToInput(img.bgra, img.width, img.height, _roiFor(b, view),
                stride: img.stride, quarterTurns: q));
            best = math.max(best, uprightScore(b, out.presence, out.landmarks));
          }
          scores[q] = scores[q]! + best;
        }
      }
    } finally {
      await g.close();
    }
    assert(() {
      debugPrint('PoseService orientation ${clip.clipId}: $scores');
      return true;
    }());
    return chooseOrientation(scores);
  }
}
