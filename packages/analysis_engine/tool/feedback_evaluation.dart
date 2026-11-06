import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value as Map);
List<Object?> _list(Object? value) => List<Object?>.from(value as List? ?? []);

/// Replay measured strokes with reviewed judgments. No inferred technique labels,
/// profile writes, relaxed readiness gates, or source overlap with evaluation.
Map<String, Object?> evaluateFeedback({
  required Map<String, Object?> feedback,
  required AnalysisPack pack,
  required List<Map<String, Object?>> runs,
}) {
  if (feedback['format'] != 'coach-feedback/1') {
    throw const FormatException('Expected coach-feedback/1');
  }
  Map<String, Object?> pending(
    String reason, [
    Map<String, Object?> details = const {},
  ]) => {
    'format': 'coach-learning-evaluation/1',
    'status': 'pending',
    'reason': reason,
    'accepted_edits': 0,
    'claimed_technique_improvement': false,
    ...details,
  };
  final entries = <Map<String, Object?>>[];
  final groups = <String, String>{};
  final ids = <String>{};
  for (final raw in _list(feedback['entries'])) {
    final e = _map(raw);
    if (e['reviewed'] != true || e['single_stroke_confirmed'] != true) continue;
    final sha = e['clip_sha256'] as String;
    final group = e['partition'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        !['fit', 'evaluation'].contains(group) ||
        !['red', 'green'].contains(e['label']) ||
        e['author_role'] != 'coach' ||
        '${e['author_id'] ?? ''}'.trim().isEmpty ||
        '${e['reviewer_id'] ?? ''}'.trim().isEmpty ||
        e['event_id'] != pack.eventId) {
      throw const FormatException('Invalid reviewed technique judgment');
    }
    if (!ids.add(e['feedback_id'] as String)) {
      throw const FormatException('Duplicate feedback ID');
    }
    if (groups.containsKey(sha) && groups[sha] != group) {
      throw const FormatException('Source content leaks into evaluation');
    }
    final span = _list(e['stroke_span_s']);
    if (span.length != 2 ||
        span.any((x) => x is! num || !x.isFinite) ||
        (span[0] as num) < 0 ||
        (span[1] as num) <= (span[0] as num)) {
      throw const FormatException('Invalid reviewed stroke span');
    }
    groups[sha] = group;
    entries.add(e);
  }
  if (entries.isEmpty) return pending('No reviewed technique judgments yet.');
  if (!groups.containsValue('fit') || !groups.containsValue('evaluation')) {
    return pending(
      'Reviewed fitting and separate evaluation recordings are required.',
    );
  }
  if (runs.isEmpty) {
    return pending(
      'Export measured CARNE experiments for the reviewed sources.',
    );
  }
  if (runs.any((r) => r['format'] != 'carne_asada_run/1')) {
    throw const FormatException('Expected standalone CARNE experiment records');
  }
  final base = _map(runs.first['base_profile_snapshot']);
  if (validateProfile(base).isNotEmpty) {
    throw const FormatException('Invalid base profile');
  }
  if (runs.any(
    (r) => jsonEncode(r['base_profile_snapshot']) != jsonEncode(base),
  )) {
    throw const FormatException('Experiments use different base profiles');
  }
  final profile = Profile.fromJson(base);
  if (!profile.minClipsMet ||
      !profile.selfConsistencyPassed ||
      profile.sourceClipCount < pack.minClips ||
      profile.packId != pack.packId ||
      profile.eventId != pack.eventId ||
      profile.metricSchemaVersion != pack.metricSchemaVersion) {
    return pending(
      'A ready coaching profile passing the original pack gates is required.',
    );
  }
  final referenceSources = _map(
    feedback['reference_sources'] ?? <String, Object?>{},
  );
  if (profile.referenceClips.isEmpty ||
      profile.referenceClips.any(
        (r) => !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch('${referenceSources[r.clipId]}'),
      )) {
    return pending(
      'Record source hashes for the base profile references before evaluating learning.',
    );
  }
  if (referenceSources.values.any((sha) => groups[sha] == 'evaluation')) {
    throw const FormatException('Base profile footage leaks into evaluation');
  }
  final priority =
      (feedback['priority'] ?? entries.first['attribute']) as String;
  if (!pack.attributeMetrics.containsKey(priority)) {
    throw const FormatException('Unsupported feedback priority');
  }
  final strokes = <String, StrokeDetail>{};
  final serialized = <String, String>{};
  var excluded = 0;
  for (final run in runs) {
    for (final raw in _list(run['strokes'])) {
      final s = _map(raw);
      final clipId = s['clip_id'] as String;
      if (!clipId.startsWith('sha256:') ||
          !groups.containsKey(clipId.substring(7))) {
        continue;
      }
      if (s['forced'] == true ||
          s['ignored'] == true ||
          s['measurement'] == null) {
        excluded++;
        continue;
      }
      final measurement = _map(s['measurement']);
      if (measurement.containsKey('error_code')) {
        excluded++;
        continue;
      }
      if (validateMetricVector(measurement).isNotEmpty) {
        throw const FormatException('Invalid exported measurement');
      }
      final vector = MetricVector.fromJson(measurement);
      if (vector.clipId != clipId ||
          vector.packId != pack.packId ||
          vector.eventId != pack.eventId ||
          vector.metricSchemaVersion != pack.metricSchemaVersion) {
        throw const FormatException('Measurement source or event mismatch');
      }
      final fps = (s['fps'] as num).toDouble();
      final start = s['start_frame'] as int, end = s['end_frame'] as int;
      if (!fps.isFinite || fps <= 0 || start < 0 || end < start) {
        throw const FormatException('Invalid measurement span');
      }
      final key = '$clipId:$start:$end';
      final contents = jsonEncode([
        measurement,
        s['phase_pose_confidence'],
        s['implement_dropout_s'],
      ]);
      if (serialized.containsKey(key)) {
        if (serialized[key] != contents) {
          throw const FormatException('Conflicting repeated measurements');
        }
        continue;
      }
      for (final old in strokes.values.where((x) => x.clipId == clipId)) {
        if (start <= old.endFrame && end >= old.startFrame) {
          throw const FormatException(
            'Overlapping repeated stroke analyses would inflate footage',
          );
        }
      }
      serialized[key] = contents;
      final confidences = _map(s['phase_pose_confidence']);
      final stroke = StrokeDetail(
        clipId: clipId,
        index: s['index'] as int,
        startFrame: start,
        endFrame: end,
        fps: fps,
        detail: AnalysisDetail(AnalysisSuccess(vector), {
          for (final e in confidences.entries)
            e.key: (e.value as num).toDouble(),
        }),
        dropoutSeconds: (s['implement_dropout_s'] as num).toDouble(),
        pack: pack,
      );
      if (stroke.usable) {
        strokes[key] = stroke;
      } else {
        excluded++;
      }
    }
  }
  final fitting = CarneSession(
    pack: pack,
    profile: profile,
    priority: priority,
  );
  final evaluation = CarneSession(
    pack: pack,
    profile: profile,
    priority: priority,
  );
  for (final id in strokes.values.map((s) => s.clipId).toSet()) {
    final session = groups[id.substring(7)] == 'fit' ? fitting : evaluation;
    session.addClip(id, strokes.values.where((s) => s.clipId == id).toList());
  }
  var unbound = 0;
  for (final e in entries.where((e) => e['attribute'] == priority)) {
    final session = e['partition'] == 'fit' ? fitting : evaluation;
    final span = _list(e['stroke_span_s']);
    final a = (span[0] as num).toDouble(), b = (span[1] as num).toDouble();
    final matches = session.pile.where((p) {
      if (p.stroke.clipId != 'sha256:${e['clip_sha256']}') return false;
      final lo = p.stroke.startFrame / p.stroke.fps,
          hi = (p.stroke.endFrame + 1) / p.stroke.fps;
      final intersection = (b < hi ? b : hi) - (a > lo ? a : lo);
      final union = (b > hi ? b : hi) - (a < lo ? a : lo);
      return intersection > 0 && intersection / union >= .5;
    }).toList();
    if (matches.length != 1) {
      unbound++;
      continue;
    }
    matches.single.marks.add(
      StrokeMark(
        attribute: priority,
        label: e['label'] as String,
        author: 'coach',
        createdAt: DateTime.parse(e['created_at'] as String),
      ),
    );
  }
  if (unbound > 0) {
    return pending(
      'Reviewed strokes must align uniquely with usable measured strokes.',
      {'unbound_judgments': unbound},
    );
  }
  if (!fitting.baselineMet) {
    return pending(
      'Insufficient usable fitting footage under the original Good gate.',
      {'usable_fit_minutes': fitting.usableMinutes},
    );
  }
  if (!evaluation.pile.any((s) => s.winning(priority) != null)) {
    return pending(
      'Reviewed evaluation judgments are required for this priority.',
    );
  }
  final before = evaluation.objective(profile.metrics, profile.referenceClips);
  String? stop;
  for (var i = 0; i < fitting.limit; i++) {
    final step = fitting.step();
    if (step is StepIdle) {
      stop = step.reason;
      break;
    }
    if (step is StepRejected) {
      stop = step.message;
      break;
    }
  }
  final after = evaluation.objective(fitting.mixture, fitting.exemplars);
  return {
    'format': 'coach-learning-evaluation/1',
    'status': fitting.edits.isEmpty
        ? 'no_update'
        : after > before + 1e-8
        ? 'candidate'
        : 'no_evaluation_gain',
    'priority': priority,
    'stop_reason': stop ?? 'limit',
    'accepted_edits': fitting.edits.length,
    'fit_source_count': groups.values.where((g) => g == 'fit').length,
    'evaluation_source_count': groups.values
        .where((g) => g == 'evaluation')
        .length,
    'excluded_measurements': excluded,
    'usable_fit_minutes': fitting.usableMinutes,
    'evaluation_feedback_agreement_before': before,
    'evaluation_feedback_agreement_after': after,
    'research_log': fitting.editsLog(
      version: profile.version,
      sessionId: 'feedback-replay',
    ),
    'candidate_profile': fitting.edits.isEmpty
        ? null
        : fitting.editedProfile.toJson(),
    'claimed_technique_improvement': false,
    'limitations': [
      'Human-entered author/reviewer provenance is an attestation, not credential verification.',
      'Feedback agreement is not physical technique accuracy or a field-validation result.',
      'The input measurement pipeline requires its own independent accuracy validation.',
    ],
  };
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    throw ArgumentError('FEEDBACK_JSON OUTPUT_JSON [CARNE_RUN_JSON ...]');
  }
  final feedback = _map(jsonDecode(await File(args[0]).readAsString()));
  final definition = PackDefinition.parse(
    await File(
      '../../apps/strathvision/assets/packs/timber.json',
    ).readAsString(),
  );
  final entries = _list(feedback['entries']);
  final event = entries.isEmpty
      ? definition.events.first
      : definition.event(_map(entries.first)['event_id'] as String)!;
  final runs = [
    for (final path in args.skip(2))
      _map(jsonDecode(await File(path).readAsString())),
  ];
  final result = evaluateFeedback(
    feedback: feedback,
    pack: event.analysis,
    runs: runs,
  );
  final out = File(args[1]);
  await out.parent.create(recursive: true);
  await out.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln(
    '${result['status']}: ${result['reason'] ?? result['stop_reason']}',
  );
}
