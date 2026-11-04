import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

/// Replay selected anonymous pose segments through a pinned engine snapshot.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('PREDICTION_DIRECTORY OUTPUT');
  final pack = PackDefinition.parse(
    await File(
      '../../apps/strathvision/assets/packs/timber.json',
    ).readAsString(),
  );
  final windows = <Map<String, Object?>>[];
  final files =
      Directory(args[0])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final data = jsonDecode(file.readAsStringSync()) as Map;
    if (data['format'] != 'gurr-accuracy-prediction/1') continue;
    final event = pack.events.singleWhere((e) => e.eventId == data['event_id']);
    final fps = (data['fps'] as num).toDouble();
    final contacts = <double>[];
    var candidates = 0, usable = 0;
    final failures = <String, int>{};
    for (final entry in (data['pose_samples'] as Map).entries) {
      List<double> values(Object? raw) => [
        for (final x in raw as List) (x as num).toDouble(),
      ];
      final track = PoseTrack(
        fps: fps,
        frames: [
          for (final sample in entry.value as List)
            poseFrameFromBlazePose(
              sample['f'] as int,
              values(sample['w']),
              values(sample['v']),
              values(sample['p']),
            ),
        ],
      );
      final source = ClipSource(
        clipId: '${data['window_id']}:${entry.key}',
        path: '',
        durationMs: ((data['duration_s'] as num) * 1000).round(),
        fps: fps,
      );
      final strokes = await analyzeContinuousTrack(
        event.analysis,
        source,
        track,
      );
      candidates += strokes.length;
      for (final stroke in strokes) {
        if (stroke.usable) usable++;
        final outcome = stroke.detail.outcome;
        if (outcome is AnalysisSuccess) {
          final contact = outcome.vector.phases['entry'];
          if (contact != null) contacts.add(contact.startFrame / fps);
        } else if (outcome is AnalysisFailure) {
          failures.update(
            outcome.error.errorCode,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    contacts.sort();
    windows.add({
      'window_id': data['window_id'],
      'variant': data['variant'],
      'prediction_sources_sha256': data['sources_sha256'],
      'contact_times_s': contacts,
      'candidate_strokes': candidates,
      'usable_strokes': usable,
      'failures': failures,
    });
  }
  final out = File(args[1]);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'format': 'gurr-accuracy-contacts/1', 'windows': windows})}\n',
  );
  print('Replayed ${windows.length} windows through the engine.');
}
