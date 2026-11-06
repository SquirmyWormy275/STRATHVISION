import 'package:analysis_engine/analysis_engine.dart';
import 'package:test/test.dart';

void main() {
  final pack = AnalysisPack.fromJson({
    'pack_id': 'test',
    'event_id': 'event',
    'metric_schema_version': '1',
    'phases': ['action'],
    'critical_phases': ['action'],
    'metrics': [
      {
        'key': 'x',
        'kind': 'implement_inclination',
        'phase': 'action',
        'unit': 'deg',
      },
    ],
    'attribute_metrics': {
      'Slope': ['x'],
    },
    'heads': [],
    'probes': [],
  });
  final now = DateTime.utc(2026, 11, 4);
  Profile profile(List<ReferenceClip> refs) => Profile(
    profileId: 'p',
    version: 1,
    coachName: 'Anonymous test',
    packId: 'test',
    eventId: 'event',
    metricSchemaVersion: '1',
    createdAt: now,
    sourceClipCount: 15,
    minClipsMet: true,
    selfConsistencyPassed: true,
    notes: '',
    metrics: const {
      'x': ProfileMetric(
        center: 0,
        spread: 1,
        weight: 1,
        unit: 'deg',
        phase: 'action',
      ),
    },
    referenceClips: refs,
  );
  MetricVector vector() => const MetricVector(
    clipId: 'c',
    packId: 'test',
    eventId: 'event',
    metricSchemaVersion: '1',
    phases: {'action': PhaseSpan(startFrame: 0, endFrame: 3599, confidence: 1)},
    metrics: {'x': MetricValue(value: 5, confidence: 1, phase: 'action')},
    poseConfidenceSummary: 1,
    specialistResiduals: {},
  );

  test('accepted exemplar removal preserves every metric and exact undo', () {
    final coach = profile(const [
      ReferenceClip(clipId: 'a', metrics: {'x': -10}),
      ReferenceClip(clipId: 'b', metrics: {'x': 10}),
      ReferenceClip(
        clipId: 'bad',
        metrics: {'x': 5},
        exemplar: true,
        confidence: .3,
      ),
    ]);
    final session = CarneSession(pack: pack, profile: coach, priority: 'Slope');
    session.addClip(
      'c',
      [
        StrokeDetail(
          clipId: 'c',
          index: 0,
          startFrame: 0,
          endFrame: 3599,
          fps: 30,
          dropoutSeconds: 0,
          pack: pack,
          detail: AnalysisDetail(AnalysisSuccess(vector()), const {
            'action': 1,
          }),
        ),
      ],
      marksFor: (_) => [
        StrokeMark(
          attribute: 'Slope',
          label: 'red',
          author: 'coach',
          createdAt: now,
        ),
      ],
    );
    expect((session.step() as StepAccepted).edit.type, 'drop_exemplar');
    expect(session.mixture.keys, ['x']);
    expect(session.editedProfile.metrics['x']!.center, 0);
    session.undo();
    expect(session.editedProfile.toJson(), coach.toJson());
  });
  test('production inference uses the same exemplar match as research', () {
    final plain = profile([]);
    final improved = profile(const [
      ReferenceClip(clipId: 'ex', metrics: {'x': 5}, exemplar: true),
    ]);
    double score(Profile p) =>
        (compare(vector: vector(), profile: p, resultId: 'r')
                as ComparisonSuccess)
            .result
            .overallScore;
    expect(score(improved), 1);
    expect(score(improved), greaterThan(score(plain)));
    final result =
        (compare(vector: vector(), profile: improved, resultId: 'r')
                as ComparisonSuccess)
            .result;
    expect(result.rankedDeltas.single.contribution, 0);
  });
  test('merged coach evidence persists across serialization', () {
    final session = CarneSession(
      pack: pack,
      profile: profile(const [
        ReferenceClip(clipId: 'a', metrics: {'x': 0}),
      ]),
      priority: 'Slope',
    );
    session.mergeCoachStrokes(
      profile(const [
        ReferenceClip(clipId: 'b', metrics: {'x': 10}),
      ]),
    );
    final restored = Profile.fromJson(session.editedProfile.toJson());
    expect(restored.referenceClips.map((r) => r.clipId), ['a', 'b']);
    expect(
      CarneSession(pack: pack, profile: restored, priority: 'Slope').hull['x'],
      (0, 10),
    );
  });
}
