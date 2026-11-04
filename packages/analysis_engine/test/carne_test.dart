import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

class _DropoutTracker implements ImplementTracker {
  @override
  Future<ImplementTrack> track(ClipSource clip, PoseTrack pose) async {
    final base = await const StubImplementTracker().track(clip, pose);
    return ImplementTrack(frames: [
      for (final f in base.frames)
        ImplementFrame(
            frame: f.frame,
            grip: f.grip,
            tip: f.tip,
            // 1.2 s with no confident implement, starting at 2 s.
            confidence: f.frame >= 60 && f.frame < 96 ? 0.1 : f.confidence),
    ]);
  }
}

/// Phase 8 acceptance (engine): exact status language, bounded edits with
/// one-sentence explanations, undo restores the mixture.
void main() {
  final timber = PackDefinition.parse(
      File('../../apps/strathvision/assets/packs/timber.json').readAsStringSync());
  final pack = timber.event('underhand')!.analysis;
  final decisions = File('../../docs/DECISIONS.md').readAsStringSync();
  final now = DateTime.utc(2026, 11, 4);
  String phase(String p) => timber.phaseLabels[p] ?? p;

  late Profile coach;
  setUpAll(() async {
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    coach = (b.build(coachName: 'C', clips: q, newProfileId: 'p', now: now) as BuildReady).profile;
  });

  Future<List<StrokeDetail>> strokes(String id,
          {int seconds = 60, int style = 7, double conf = 0.85, ImplementTracker? tracker}) =>
      AnalysisEngine(
              pack: pack,
              pose: StubPoseEstimator(styleSeed: style, confidence: conf),
              implement: tracker ?? const StubImplementTracker())
          .analyzeStrokes(ClipSource(clipId: id, path: '/$id.mp4', durationMs: seconds * 1000, fps: 30));

  List<StrokeMark> green(StrokeDetail s) => [
        StrokeMark(attribute: 'Slope', label: 'green', author: 'athlete', createdAt: now),
      ];

  test('status copy is exactly DECISIONS.md', () {
    for (final line in [
      CarneCopy.found(8, 5, 'Slope'),
      CarneCopy.voice,
      CarneCopy.dropout(1.2),
      CarneCopy.gravy(7, 'Slope'),
      CarneCopy.priority('Slope'),
      CarneCopy.belowThreshold,
      CarneCopy.accepted(CarneCopy.shifted('Slope', '1.1°', 'steeper', 'downswing')),
      CarneCopy.leftHull,
      CarneCopy.tally(4),
      CarneCopy.shiftWhy('Slope', '1.4°', 'steeper', 'downswing', 7, 9),
      CarneCopy.tightenWhy('Slope', 'entry', 3),
      CarneCopy.raiseExemplarWhy(CarneCopy.where(14.2, 'Gurr')),
      CarneCopy.dropExemplarWhy('flat'),
    ]) {
      expect(decisions, contains('“$line”'), reason: line);
    }
  });

  test('strokes are segmented (underhand: one per backswing top)', () async {
    final s = await strokes('a', seconds: 20);
    expect(s.length, greaterThanOrEqualTo(5));
    for (var i = 1; i < s.length; i++) {
      expect(s[i].startFrame, greaterThan(s[i - 1].endFrame));
    }
    expect(s.every((x) => x.usable), isTrue);
    expect(s.first.metrics.keys, contains('entry_slope'));
  });

  group('ingestion status', () {
    CarneSession session() => CarneSession(
        pack: pack, profile: coach, priority: 'Slope', clock: () => now, phaseLabel: phase);

    test('clean clip: found N strokes, clean enough for slope', () async {
      final s = session();
      final st = await strokes('a', seconds: 20);
      expect(s.addClip('a', st), ['Found ${st.length} strokes. ${st.length} are clean enough for slope. Adding them.']);
    });

    test('implement dropout: saved, but won’t move the model', () async {
      final s = session();
      final st = await strokes('d', seconds: 20, tracker: _DropoutTracker());
      expect(s.addClip('d', st).single,
          'Implement drops out for 1.2 s. Clip saved, but it won’t move the model.');
      expect(s.pile.where((p) => !p.counts), isNotEmpty);
    });

    test('weak pose: below the usable threshold; use anyway counts it', () async {
      final s = session();
      final st = await strokes('w', seconds: 20, conf: 0.55);
      expect(s.addClip('w', st).single, CarneCopy.belowThreshold);
      expect(s.usableSeconds, 0);
      s.useAnyway('w');
      expect(s.usableSeconds, greaterThan(10));
      s.ignore('w');
      expect(s.usableSeconds, 0);
    });

    test('past Great: pure gravy', () async {
      final s = session();
      for (var i = 0; i < 7; i++) {
        s.addClip('c$i', await strokes('c$i', seconds: 60));
      }
      expect(s.usableMinutes, greaterThan(6));
      final msgs = s.addClip('x', await strokes('x', seconds: 20));
      expect(msgs.first, startsWith('You already have '));
      expect(msgs.first, endsWith(' minutes of good slope footage. This is pure gravy.'));
    });
  });

  group('loop', () {
    Future<CarneSession> ready({int limit = 5, bool chaos = false, AnalysisPack? p, Profile? prof}) async {
      final s = CarneSession(
          pack: p ?? pack,
          profile: prof ?? coach,
          priority: 'Slope',
          limit: limit,
          chaos: chaos,
          clock: () => now,
          phaseLabel: phase);
      for (var i = 0; i < 3; i++) {
        s.addClip('ath$i', await strokes('ath$i'), marksFor: green);
      }
      return s;
    }

    test('below Good: no edits until the baseline is met', () async {
      final s = CarneSession(pack: pack, profile: coach, priority: 'Slope', clock: () => now);
      s.addClip('short', await strokes('short', seconds: 30), marksFor: green);
      expect(s.baselineMet, isFalse);
      expect(s.step(), isA<StepIdle>());
      expect(s.edits, isEmpty);
    });

    test('accepted edits stay in bounds, explain themselves, isolate the priority',
        () async {
      final s = await ready();
      expect(s.baselineMet, isTrue);
      final before = Map.of(s.mixture);
      final results = [for (var i = 0; i < 12; i++) s.step()];
      final accepted = results.whereType<StepAccepted>().toList();
      expect(accepted, isNotEmpty);
      expect(accepted.length, lessThanOrEqualTo(5)); // session limit
      expect(s.limitReached || results.last is! StepAccepted, isTrue);
      for (final a in accepted) {
        expect(_oneSentence.any((r) => r.hasMatch(a.edit.explanation)), isTrue,
            reason: a.edit.explanation);
        expect(a.edit.status, startsWith('CARNE ASADA accepted an update. '));
        expect(a.edit.objectiveAfter, greaterThan(a.edit.objectiveBefore));
        final h = s.hull[a.edit.metric]!;
        expect(a.edit.after.center, inInclusiveRange(h.$1, h.$2));
        expect(pack.attributeMetrics['Slope'], contains(a.edit.metric));
        for (final e in s.exemplars) {
          for (final k in pack.attributeMetrics['Slope']!) {
            if (e.metrics[k] != null) {
              expect(e.metrics[k], inInclusiveRange(s.hull[k]!.$1, s.hull[k]!.$2));
            }
          }
        }
      }
      for (final k in s.mixture.keys) {
        if (!pack.attributeMetrics['Slope']!.contains(k)) {
          expect(s.mixture[k]!.toJson(), before[k]!.toJson(), reason: '$k changed');
        }
      }
    });

    test('a change that would leave the coach hull is refused', () async {
      // Only entry slope speaks to Slope, and its mean already sits on the
      // steep edge of the coach hull; the athlete is steeper still.
      final onlyEntry = AnalysisPack.fromJson({
        ...jsonDecode(jsonEncode(_eventJson(timber, 'underhand'))) as Map<String, Object?>,
        'pack_id': 'timber',
        'attribute_metrics': {'Slope': ['entry_slope']},
      });
      final h = coach.referenceClips.map((r) => r.metrics['entry_slope']!).reduce((a, b) => a < b ? a : b);
      final m = coach.metrics['entry_slope']!;
      final edge = Profile.fromJson({
        ...coach.toJson(),
        'metrics': {
          ...coach.toJson()['metrics'] as Map,
          'entry_slope': ProfileMetric(center: h, spread: m.spread, weight: m.weight, unit: m.unit, phase: m.phase).toJson(),
        },
      });
      final s = await ready(p: onlyEntry, prof: edge);
      // Every candidate either fails to improve or would leave the hull.
      final results = [for (var i = 0; i < 6; i++) s.step()];
      expect(results.whereType<StepRejected>().map((r) => r.message), contains(CarneCopy.leftHull));
      for (final e in s.edits) {
        expect(e.type, isNot('shift_mean'));
      }
      final h2 = s.hull['entry_slope']!;
      expect(s.mixture['entry_slope']!.center, inInclusiveRange(h2.$1, h2.$2));

      // The chaos toggle loosens the hull by one spread for the session.
      final loose = await ready(p: onlyEntry, prof: edge, chaos: true);
      final lr = [for (var i = 0; i < 6; i++) loose.step()].whereType<StepAccepted>();
      expect(lr.map((a) => a.edit.type), contains('shift_mean'));
    });

    test('undo restores the previous mixture exactly', () async {
      final s = await ready();
      final before = jsonEncode({for (final e in s.mixture.entries) e.key: e.value.toJson()});
      expect(s.step(), isA<StepAccepted>());
      expect(s.step(), isA<StepAccepted>());
      s.undo();
      s.undo();
      expect(jsonEncode({for (final e in s.mixture.entries) e.key: e.value.toJson()}), before);
      expect(s.edits, isEmpty);
      expect(s.undo(), isNull);
    });

    test('edits record for carne_asada/', () async {
      final s = await ready();
      s.step();
      final log = s.editsLog(version: 2, sessionId: 's1');
      expect(log['format'], 'carne_asada/1');
      expect(log['priority'], 'Slope');
      expect((log['edits'] as List).single['explanation'], startsWith('Shifted slope mean'));
      expect(log['hull'], contains('entry_slope'));
    });
  });

  group('weights, exemplars, packages', () {
    Future<CarneSession> marked() async {
      final s = CarneSession(
          pack: pack, profile: coach, priority: 'Slope', clock: () => now, phaseLabel: phase,
          metricLabel: (k) => timber.metricLabels[k] ?? k);
      for (var i = 0; i < 3; i++) {
        s.addClip('ath$i', await strokes('ath$i'), marksFor: green);
      }
      return s;
    }

    test('loop can add or raise exemplars and weights, each explained and undoable',
        () async {
      final s = await marked();
      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        final r = s.step();
        if (r is StepAccepted) seen.add(r.edit.type);
      }
      expect(seen, isNotEmpty);
      final snapshot = jsonEncode(s.editedProfile.toJson());
      final n = s.edits.length;
      for (var i = 0; i < n; i++) {
        s.undo();
      }
      expect(jsonEncode(s.editedProfile.toJson()), jsonEncode(coach.toJson()));
      expect(snapshot, isNot(jsonEncode(coach.toJson())));
    });

    test('a low-confidence exemplar from an earlier session is dropped', () async {
      // Strokes the coach marked red, and an old low-confidence exemplar
      // sitting right on them: it wrongly says those swings match.
      final reds = [for (var i = 0; i < 3; i++) await strokes('r$i')];
      final all = reds.expand((x) => x).toList();
      double mean(String k) =>
          all.map((x) => x.metrics[k]!).reduce((a, b) => a + b) / all.length;
      final bad = ReferenceClip(
          clipId: 'old@3',
          metrics: {for (final k in pack.attributeMetrics['Slope']!) k: mean(k)},
          exemplar: true,
          weight: 1,
          confidence: 0.3,
          source: 'the 14-second mark of the old clip');
      final withEx = Profile.fromJson({
        ...coach.toJson(),
        'reference_clips': [...coach.toJson()['reference_clips'] as List, bad.toJson()],
      });
      final s = CarneSession(pack: pack, profile: withEx, priority: 'Slope', clock: () => now);
      expect(s.exemplars.single.clipId, 'old@3');
      for (var i = 0; i < 3; i++) {
        s.addClip('r$i', reds[i], marksFor: (st) => [
              StrokeMark(attribute: 'Slope', label: 'red', author: 'coach', createdAt: now),
            ]);
      }
      final r = s.step();
      expect(r, isA<StepAccepted>());
      final e = (r as StepAccepted).edit;
      expect(e.type, 'drop_exemplar');
      expect(e.explanation,
          matches(RegExp(r'^Dropped one low-confidence exemplar that was pulling the mean (flat|steep)\.$')));
      expect(s.exemplars, isEmpty);
      s.undo();
      expect(s.exemplars.single.clipId, 'old@3');
    });

    test('dropped package of the same event widens the coach hull', () async {
      final s = CarneSession(pack: pack, profile: coach, priority: 'Slope', clock: () => now);
      final before = s.hull['entry_slope']!;
      final other = Profile.fromJson({
        ...coach.toJson(),
        'profile_id': 'other',
        'reference_clips': [
          {'clip_id': 'x1', 'metrics': {'entry_slope': before.$1 - 5}},
          {'clip_id': 'x2', 'metrics': {'entry_slope': before.$2 + 5}},
        ],
      });
      expect(s.mergeCoachStrokes(other), 2);
      expect(s.hull['entry_slope'], (before.$1 - 5, before.$2 + 5));
      expect(s.mergeCoachStrokes(other), 0); // already merged
      final foreign = Profile.fromJson({...other.toJson(), 'event_id': 'standing_block'});
      expect(s.mergeCoachStrokes(foreign), 0);
    });

    test('exemplars ride in the edited profile and the record', () async {
      final s = await marked();
      for (var i = 0; i < 5; i++) {
        s.step();
      }
      final log = s.editsLog(version: 2, sessionId: 's');
      expect(log['exemplars'], hasLength(s.exemplars.length));
      expect(s.editedProfile.referenceClips.where((r) => r.exemplar).length, s.exemplars.length);
      expect(validateProfile(s.editedProfile.toJson()), isEmpty);
    });
  });

  test('coach mark overrides athlete; newest coach wins', () {
    final p = PileStroke(
      stroke: StrokeDetail(
          clipId: 'c', index: 0, startFrame: 0, endFrame: 29, fps: 30,
          detail: AnalysisDetail(
              AnalysisFailure(AnalysisError(ErrorCode.phaseDetectionFailed, 'x')), const {}),
          dropoutSeconds: 0, pack: pack),
      clipName: 'c',
      marks: [
        StrokeMark(attribute: 'Slope', label: 'green', author: 'athlete', createdAt: DateTime.utc(2026, 1, 3)),
        StrokeMark(attribute: 'Slope', label: 'red', author: 'coach', createdAt: DateTime.utc(2026, 1, 1)),
        StrokeMark(attribute: 'Slope', label: 'green', author: 'coach', createdAt: DateTime.utc(2026, 1, 2)),
        StrokeMark(attribute: 'Hinge', label: 'red', author: 'athlete', createdAt: DateTime.utc(2026, 1, 4)),
      ],
    );
    expect(p.winning('Slope'), 'green');
    expect(p.winning('Hinge'), 'red');
    expect(p.winning('Path'), isNull);
  });
}

final _oneSentence = [
  RegExp(r'^Shifted slope mean [0-9.]+° (steeper|flatter) on the [a-z]+ phase because \d+ of your last \d+ green marks agreed\.$'),
  RegExp(r'^Tightened slope variance in the [a-z]+ phase after \w+ consecutive red marks on the same stroke\.$'),
  RegExp(r'^Raised the weight of [a-z ]+ within slope because \d+ of your last \d+ green marks were closest on it\.$'),
  RegExp(r'^(Added a|Raised the weight of the) residual exemplar from the \d+-second mark of the \w+ clip; it matched the current priority better than the existing mean\.$'),
  RegExp(r'^Dropped one low-confidence exemplar that was pulling the mean (flat|steep)\.$'),
];

Map<String, Object?> _eventJson(PackDefinition def, String eventId) {
  final raw = jsonDecode(File('../../apps/strathvision/assets/packs/timber.json').readAsStringSync())
      as Map<String, Object?>;
  return (raw['events'] as List).cast<Map<String, Object?>>().firstWhere((e) => e['event_id'] == eventId);
}
