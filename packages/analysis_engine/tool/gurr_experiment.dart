import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

/// Whole-corpus ingestion/coverage and no-feedback control. No identities,
/// events or coach marks are invented from detections.
Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'dart run tool/gurr_experiment.dart MANIFEST TRACKS_DIR OUTPUT',
    );
    exitCode = 2;
    return;
  }
  final manifest = jsonDecode(await File(args[0]).readAsString()) as Map;
  final pack = PackDefinition.parse(
    await File(
      '../../apps/strathvision/assets/packs/timber.json',
    ).readAsString(),
  );
  final clips = <Map<String, Object?>>[];
  final details = <Map<String, Object?>>[];
  final aggregate = <String, Map<String, Object?>>{};
  final corpusSpans = <String, List<StrokeDetail>>{};
  final corpusVectors = <String, List<MetricVector>>{};
  var frames = 0, withPeople = 0, multiple = 0, detections = 0, poses = 0;
  double runtime = 0;
  for (final c in manifest['clips'] as List) {
    final file = File('${args[1]}/${c['sha256']}.json');
    if (!await file.exists()) {
      throw StateError('Missing analysis for ${c['relative_path']}');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    frames += data['sampled_frames'] as int;
    withPeople += data['frames_with_people'] as int;
    multiple += data['frames_with_multiple_people'] as int;
    detections += (data['observations'] as List).length;
    runtime += (data['elapsed_s'] as num).toDouble();
    final fps = (c['fps'] as num).toDouble();
    final samples = data['pose_samples'] as Map;
    poses += samples.values.fold<int>(0, (n, v) => n + (v as List).length);
    final clipCounts = <String, Object?>{};
    for (final event in pack.events) {
      var strokes = 0, usable = 0;
      double usableSeconds = 0;
      final errors = <String, int>{};
      final qualities = <ClipQuality>[];
      final allSpans = <StrokeDetail>[];
      for (final entry in samples.entries) {
        final list = entry.value as List;
        if (list.length < 10) continue;
        List<double> doubles(Object? value) => [
          for (final n in value as List) (n as num).toDouble(),
        ];
        final track = PoseTrack(
          fps: fps,
          frames: [
            for (final sample in list)
              poseFrameFromBlazePose(
                sample['f'] as int,
                doubles(sample['w']),
                doubles(sample['v']),
                doubles(sample['p']),
              ),
          ],
        );
        final id = '${c['sha256']}:${entry.key}';
        final source = ClipSource(
          clipId: id,
          path: '',
          durationMs: ((c['duration_s'] as num) * 1000).round(),
          fps: fps,
        );
        final engine = AnalysisEngine(
          pack: event.analysis,
          pose: PrecomputedPoseEstimator(track),
          implement: const GripImplementTracker(),
          phases: const EventPhaseDetector(),
          perStroke: true,
        );
        final spans = await analyzeContinuousTrack(
          event.analysis,
          source,
          track,
        );
        strokes += spans.length;
        allSpans.addAll(spans);
        corpusSpans.putIfAbsent(event.eventId, () => []).addAll(spans);
        for (final span in spans) {
          if (span.usable) {
            usable++;
            usableSeconds += span.seconds;
          } else {
            for (final issue in span.issues) {
              errors.update(issue.name, (n) => n + 1, ifAbsent: () => 1);
            }
          }
        }
        final quality = await ProfileBuilder(
          engine: engine,
        ).evaluate(source, displayName: id);
        qualities.add(quality);
        corpusVectors.putIfAbsent(event.eventId, () => []).addAll([
          for (final span in spans)
            if (span.usable && span.detail.outcome is AnalysisSuccess)
              (span.detail.outcome as AnalysisSuccess).vector,
        ]);
        details.add({
          'clip_sha256': c['sha256'],
          'track_id': entry.key,
          'candidate_event': event.eventId,
          'pose_frames': list.length,
          'candidate_strokes': spans.length,
          'usable_strokes': spans.where((s) => s.usable).length,
          'mean_pose_confidence': track.meanConfidence,
          'identity_confirmed': false,
          'event_confirmed': c['event_id'] == event.eventId,
        });
      }
      clipCounts[event.eventId] = {
        'candidate_strokes': strokes,
        'usable_strokes': usable,
        'usable_track_seconds': usableSeconds,
        'rejections': errors,
      };
      final total = aggregate.putIfAbsent(
        event.eventId,
        () => {
          'candidate_strokes': 0,
          'usable_strokes': 0,
          'usable_track_seconds': 0.0,
          'no_feedback_accepted_edits': 0,
          'source_clips': 0,
        },
      );
      total['candidate_strokes'] =
          (total['candidate_strokes'] as int) + strokes;
      total['usable_strokes'] = (total['usable_strokes'] as int) + usable;
      total['usable_track_seconds'] =
          (total['usable_track_seconds'] as double) + usableSeconds;
      total['source_clips'] =
          (total['source_clips'] as int) + (usable > 0 ? 1 : 0);
      // An anonymous control fitted from measured, usable stroke vectors.
      // It is not a ready coach package and never contains fabricated marks.
      final vectors = [
        for (final span in allSpans)
          if (span.usable && span.detail.outcome is AnalysisSuccess)
            (span.detail.outcome as AnalysisSuccess).vector,
      ];
      if (vectors.isNotEmpty) {
        final control = Profile(
          profileId: 'anonymous-control-${event.eventId}',
          version: 1,
          coachName: 'Anonymous ingestion control',
          packId: event.analysis.packId,
          eventId: event.eventId,
          metricSchemaVersion: event.analysis.metricSchemaVersion,
          createdAt: DateTime.utc(2026, 11, 4),
          sourceClipCount: 1,
          minClipsMet: false,
          selfConsistencyPassed: false,
          notes: 'Not a coaching profile.',
          metrics: fitMetrics(vectors, event.analysis),
          referenceClips: [
            for (final v in vectors)
              ReferenceClip(clipId: v.clipId, metrics: metricValues(v)),
          ],
        );
        final session = CarneSession(
          pack: event.analysis,
          profile: control,
          priority: event.analysis.attributeMetrics.keys.first,
        );
        session.addClip('${c['sha256']}', allSpans);
        final firstStep = session.step();
        if (firstStep is StepIdle) {
          final reasons =
              total.putIfAbsent('control_idle_reasons', () => <String, int>{})
                  as Map<String, int>;
          reasons.update(firstStep.reason, (n) => n + 1, ifAbsent: () => 1);
        }
        // No marks supplied: run the actual loop as a negative control.
        for (var attempt = 0; attempt < 10; attempt++) {
          session.step();
        }
        total['no_feedback_accepted_edits'] =
            (total['no_feedback_accepted_edits'] as int) + session.edits.length;
      }
    }
    clips.add({
      'source_name': c['relative_path'],
      'sha256': c['sha256'],
      'duration_s': c['duration_s'],
      'sampled_frames': data['sampled_frames'],
      'frames_with_multiple_people': data['frames_with_multiple_people'],
      'max_detected_people': data['max_people'],
      'posed_tracks': samples.length,
      'candidate_events': clipCounts,
    });
  }
  for (final event in pack.events) {
    final vectors = corpusVectors[event.eventId] ?? [];
    if (vectors.isEmpty) continue;
    final control = Profile(
      profileId: 'whole-corpus-control',
      version: 1,
      coachName: 'Anonymous control',
      packId: event.analysis.packId,
      eventId: event.eventId,
      metricSchemaVersion: event.analysis.metricSchemaVersion,
      createdAt: DateTime.utc(2026, 11, 4),
      sourceClipCount: clips.length,
      minClipsMet: false,
      selfConsistencyPassed: false,
      notes: 'Diagnostic control only.',
      metrics: fitMetrics(vectors, event.analysis),
      referenceClips: [
        for (final v in vectors)
          ReferenceClip(clipId: v.clipId, metrics: metricValues(v)),
      ],
    );
    final session = CarneSession(
      pack: event.analysis,
      profile: control,
      priority: event.analysis.attributeMetrics.keys.first,
    );
    session.addClip('whole corpus', corpusSpans[event.eventId] ?? []);
    final step = session.step();
    for (var i = 0; i < 10; i++) {
      session.step();
    }
    aggregate[event.eventId]!['whole_corpus_control'] = {
      'baseline_met': session.baselineMet,
      'reason': step is StepIdle ? step.reason : 'unexpected edit',
      'accepted_edits': session.edits.length,
      'usable_track_seconds': session.usableSeconds,
    };
  }
  final result = {
    'format': 'gurr-experiment/1',
    'date': '2026-11-04',
    'experiment': 'anonymous multi-person ingestion and no-feedback control',
    'clip_count': clips.length,
    'duration_s': (manifest['clips'] as List).fold<double>(
      0,
      (n, c) => n + (c['duration_s'] as num).toDouble(),
    ),
    'sample_rate': 5,
    'sampled_frames': frames,
    'frames_with_people': withPeople,
    'frames_with_multiple_people': multiple,
    'person_detections': detections,
    'pose_samples': poses,
    'pipeline_elapsed_s': runtime,
    'named_athlete_profiles_built': 0,
    'confirmed_coach_marks': 0,
    'claimed_technique_improvement': false,
    'events_are_candidate_passes': true,
    'caveats': [
      'Athlete identities and events await user confirmation.',
      'Both event packs were stress-tested on every clip; counts are not ground-truth event counts.',
      'Detector finds spectators as well as athletes. Tracks can fragment during occlusion or rotation.',
      'Implement direction is a forearm/grip proxy, not a measured axe track.',
      'No coach labels were generated. No technique-improvement claim is made.',
      'Track-seconds may overlap across people and are not unique recording time.',
    ],
    'aggregate': aggregate,
    'clips': clips,
    'track_quality': details,
  };
  final output = File(args[2]);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln(
    'Processed ${clips.length} clips, $frames frames, $poses pose samples.',
  );
}
