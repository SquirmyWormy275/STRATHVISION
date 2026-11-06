import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../packages/analysis_engine/tool/feedback_evaluation.dart';
import 'support/carne_fixture.dart';

/// Synthetic measurements/judgments exercise the replay; no coach data is made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarneFixture fixture;
  setUpAll(() async => fixture = await CarneFixture.load());

  test('empty real feedback stays pending without a manufactured profile', () {
    final result = evaluateFeedback(
      feedback: {'format': 'coach-feedback/1', 'entries': []},
      pack: fixture.info.analysisPack,
      runs: [],
    );
    expect(result['status'], 'pending');
    expect(result['accepted_edits'], 0);
    expect(result['claimed_technique_improvement'], false);
  });

  test(
    'measured export round-trips through source-disjoint learning replay',
    () async {
      final dir = await Directory.systemTemp.createTemp('feedback_replay_');
      addTearDown(() => dir.delete(recursive: true));
      final c = fixture.controller();
      addTearDown(c.dispose);
      final paths = [
        for (var i = 0; i < 4; i++)
          (File('${dir.path}/$i.mov')..writeAsStringSync('fixture-$i')).path,
      ];
      await c.drop(paths);
      final run = c.runReport();
      final before = jsonEncode(fixture.profile.toJson());
      final sources = run['sources'] as List;
      final entries = <Map<String, Object?>>[];
      for (var i = 0; i < sources.length; i++) {
        final sha = sources[i]['sha256'];
        for (final raw in (run['strokes'] as List).where(
          (s) => s['clip_id'] == 'sha256:$sha',
        )) {
          final measurement = Map<String, Object?>.from(
            raw['measurement'] as Map,
          );
          expect(validateMetricVector(measurement), isEmpty);
          entries.add({
            'feedback_id': '$i-${raw['index']}',
            'clip_sha256': sha,
            'partition': i < 3 ? 'fit' : 'evaluation',
            'event_id': fixture.profile.eventId,
            'stroke_span_s': [
              (raw['start_frame'] as num) / (raw['fps'] as num),
              ((raw['end_frame'] as num) + 1) / (raw['fps'] as num),
            ],
            'attribute': 'Slope',
            'label': 'green',
            'author_id': 'Synthetic fixture',
            'author_role': 'coach',
            'reviewer_id': 'Synthetic fixture',
            'single_stroke_confirmed': true,
            'reviewed': true,
            'created_at': DateTime.utc(2026, 11, 5).toIso8601String(),
          });
        }
      }
      final feedback = <String, Object?>{
        'format': 'coach-feedback/1',
        'priority': 'Slope',
        'entries': entries,
        'reference_sources': {
          for (var i = 0; i < fixture.profile.referenceClips.length; i++)
            fixture.profile.referenceClips[i].clipId: (1000 + i)
                .toRadixString(16)
                .padLeft(64, '0'),
        },
      };
      Map<String, Object?> replay(List<Map<String, Object?>> runs) =>
          evaluateFeedback(
            feedback: feedback,
            pack: fixture.info.analysisPack,
            runs: runs,
          );
      final result = replay([run]);
      expect(result['status'], isNot('pending'));
      expect(result['accepted_edits'] as int, inInclusiveRange(1, 5));
      expect(result['fit_source_count'], 3);
      expect(result['evaluation_source_count'], 1);
      expect(result['claimed_technique_improvement'], false);
      expect(jsonEncode(fixture.profile.toJson()), before);
      final duplicate = replay([run, run]);
      expect(duplicate['usable_fit_minutes'], result['usable_fit_minutes']);
      expect(duplicate['accepted_edits'], result['accepted_edits']);

      final e = Map<String, Object?>.from(entries.first)
        ..['feedback_id'] = 'leak'
        ..['partition'] = 'evaluation';
      entries.add(e);
      expect(() => replay([run]), throwsFormatException);
      entries.removeLast();
      final references = feedback['reference_sources'] as Map;
      references[fixture.profile.referenceClips.first.clipId] =
          sources.last['sha256'];
      expect(() => replay([run]), throwsFormatException);
    },
  );
}
