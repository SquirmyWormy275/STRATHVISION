import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../profiles/clip_probe.dart';
import '../profiles/profile_package.dart';
import '../vision/pose_service.dart';
import '../vision/athlete.dart';
import '../workspace/project.dart' show Mark;
import 'carne_run.dart';
import 'carne_athletes.dart';
import 'voice_notes.dart';
import 'local_transcriber.dart';

export 'carne_run.dart' show ExperimentWriter;
export 'voice_notes.dart';

typedef StrokeAnalyzer = Future<List<StrokeDetail>> Function(ClipSource clip);

Map<String, Object?> carneAnalysisMetadata() => {
  'provider': 'local_blazepose_with_gap_safe_stroke_analysis',
  'pose_model_asset': PoseService.modelAsset,
  'person_detector_asset': PoseService.detectorAsset,
  'sample_rate_limit': carnePoseService.maxSampleRate,
  'sample_budget': carnePoseService.maxSamples,
  'ambiguous_competitor': 'requires_user_selection',
  'pose_gap_limit_s': .6,
  'implement': 'forearm_grip_proxy',
  'source_revision': const String.fromEnvironment(
    'STRATHVISION_REVISION',
    defaultValue: 'unrecorded',
  ),
};

/// Production CARNE analysis uses real local pose and never bridges missing
/// observations. Identity matching is separate and is not inferred here.
StrokeAnalyzer isolateStrokeAnalyzer(
  AnalysisPack pack, {
  CarneAthleteState? athletes,
}) {
  final state = athletes ?? CarneAthleteState();
  return (clip) async {
    final result = await loadCarneTrack(clip, state);
    return Isolate.run(() => analyzeContinuousTrack(pack, clip, result.track));
  };
}

typedef MarksLookup = Future<List<Mark>> Function(String path);

/// Stores the next package version (with `carne_asada/`) and lists it.
typedef ResearchWriter = Future<String> Function(
  Profile profile,
  Map<String, String> patches,
  Map<String, String> adapters,
  Map<String, String> research,
);

/// One line in the status feed.
class FeedLine {
  const FeedLine(this.text, {this.useAnywayClip, this.athleteClip});
  final String text;

  /// Set on "below the usable threshold" lines: the clip "use anyway" adds.
  final String? useAnywayClip;
  final String? athleteClip;
}

class _VoiceStrokeMark extends StrokeMark {
  const _VoiceStrokeMark({
    required this.noteId,
    required super.attribute,
    required super.label,
    required super.author,
    required super.createdAt,
  });
  final String noteId;
}

const _video = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'};
const _audio = {'.m4a', '.mp3', '.wav', '.aac', '.ogg', '.flac'};

/// The CARNE ASADA playground: one drop zone feeding a constrained mixture
/// editor. Desktop only; nothing here is needed for inference.
class CarneController extends ChangeNotifier {
  CarneController({
    required this.pack,
    required this.attributes,
    required this.bundle,
    required this.probe,
    required this.analyze,
    required this.marks,
    required this.write,
    ClipFingerprinter? fingerprint,
    CarneAthleteState? athletes,
    VoiceNoteLibrary? voiceLibrary,
    this.analysisMetadata = const {'provider': 'unspecified'},
    this.phaseLabel,
    this.metricLabel,
    DateTime Function()? clock,
  }) : athletes = athletes ?? CarneAthleteState(),
       voiceLibrary = voiceLibrary ?? VoiceNoteLibrary(),
       _clock = clock ?? DateTime.now,
       _fingerprint = fingerprint ?? hashVideoContent {
    startedAt = _clock().toUtc();
    session = CarneSession(
      pack: pack,
      profile: bundle.profile,
      priority: _defaultPriority(),
      clock: _clock,
      phaseLabel: phaseLabel,
      metricLabel: metricLabel,
    );
    feed.add(FeedLine(CarneCopy.priority(session.priority)));
  }

  final AnalysisPack pack;

  /// The pack's mark attributes, in order.
  final List<String> attributes;
  final ProfileBundle bundle;
  final ClipProber probe;
  final StrokeAnalyzer analyze;
  final MarksLookup marks;
  final ResearchWriter write;
  final String Function(String phase)? phaseLabel;
  final String Function(String metric)? metricLabel;
  final DateTime Function() _clock;
  final ClipFingerprinter _fingerprint;
  final Map<String, Object?> analysisMetadata;
  final CarneAthleteState athletes;
  final VoiceNoteLibrary voiceLibrary;
  final List<VoiceNote> _voiceNotes = [];
  final Map<String, TranscriptionCancellation> _voiceJobs = {};
  List<VoiceNote> get voiceNotes => List.unmodifiable(_voiceNotes);
  bool get voiceBusy => _voiceJobs.isNotEmpty;
  List<VoiceTarget> get voiceTargets => [
    for (final item in session.pile)
      if (!item.ignored && !_pendingAthletes.contains(item.stroke.clipId))
        VoiceTarget(
          clipId: item.stroke.clipId,
          name: item.clipName,
          strokeIndex: item.stroke.index,
          startMs: (item.stroke.startFrame / item.stroke.fps * 1000).ceil(),
          endMs: ((item.stroke.endFrame + 1) / item.stroke.fps * 1000).ceil(),
        ),
  ];
  final Set<String> _pendingAthletes = {};
  bool needsAthleteChoice(String id) => _pendingAthletes.contains(id);
  static const _uuid = Uuid();

  late final CarneSession session;

  /// Newest last.
  final List<FeedLine> feed = [];
  final String sessionId = _uuid.v4();
  late final DateTime startedAt;
  final Map<String, CarneSource> _sources = {};
  final List<Map<String, Object?>> _inputs = [];
  final List<Map<String, Object?>> _attempts = [];
  final Map<String, String> _pathHashes = {};
  final Map<String, DateTime> _changedPaths = {};
  Future<void> _queue = Future.value();
  int _pendingDrops = 0, _revision = 0;
  bool _savingRun = false, _savingProfile = false;
  bool get busy => _pendingDrops > 0 || _savingRun || _savingProfile;
  String? _activity;
  String _stopReason = 'empty';
  String _stopMessage = 'Add footage to start an experiment.';
  String get statusText => _activity ?? _stopMessage;
  String get stopReason => _stopReason;
  String? savedRunPath;
  int? _savedRunRevision;
  bool get runSaved => savedRunPath != null && _savedRunRevision == _revision;
  bool get canSaveRun => !busy && (_inputs.isNotEmpty || _attempts.isNotEmpty);
  bool get canSaveProfile =>
      !busy && session.edits.isNotEmpty && savedPath == null;
  String? savedPath;
  String? _lastClip;
  bool _disposed = false;

  String _defaultPriority() => attributes.firstWhere(
    (a) => pack.attributeMetrics.containsKey(a),
    orElse: () => attributes.isEmpty ? 'Priority' : attributes.first,
  );

  List<String> get priorities => [
    for (final a in attributes)
      if (pack.attributeMetrics.containsKey(a)) a,
  ];

  bool get canChangeSettings => session.edits.isEmpty;

  void setPriority(String attr) {
    if (busy || !canChangeSettings) return;
    _setPriority(attr);
  }

  void _setPriority(String attr, {bool update = true}) {
    if (!canChangeSettings || attr == session.priority) return;
    session.priority = attr;
    feed.add(FeedLine(CarneCopy.priority(attr)));
    _changed();
    if (update) _tryUpdate();
    _notify();
  }

  void setChaos(bool on) {
    if (busy || !canChangeSettings || on == session.chaos) return;
    session.chaos = on;
    feed.add(
      FeedLine(
        on
            ? 'Chaos is on for this session: the coach hull is loosened by one spread. It resets next session.'
            : 'Chaos is off. Edits stay inside the coach hull.',
      ),
    );
    _changed();
    _tryUpdate();
    _notify();
  }

  /// Everything dropped or chosen, routed by kind.
  Future<void> drop(List<String> paths) {
    if (paths.isEmpty) return Future.value();
    final incoming = List<String>.of(paths);
    _pendingDrops++;
    _changed();
    _notify();
    final job = _queue.then((_) async {
      try {
        for (final path in incoming) {
          final input = <String, Object?>{
            'path': path,
            'received_at': _clock().toUtc().toIso8601String(),
            'kind': _video.contains(p.extension(path).toLowerCase())
                ? 'video'
                : 'other',
            'status': 'processing',
          };
          _inputs.add(input);
          try {
            await _ingest(path, input);
          } on CarneAthleteChoiceNeeded catch (request) {
            athletes.record(request.clip, request.result);
            _pendingAthletes.add(request.clip.clipId);
            input['status'] = 'awaiting_competitor';
            input['athlete'] = athletes.metadata(request.clip.clipId);
            feed.add(
              FeedLine(
                'Choose the competitor in ${p.basename(path)}.',
                athleteClip: request.clip.clipId,
              ),
            );
          } catch (error) {
            input['status'] = 'failed';
            input['error'] = error.toString();
            feed.add(
              FeedLine(
                'Couldn’t process ${p.basename(path)}. '
                'The experiment report has details; the remaining files will still be processed.',
              ),
            );
          }
          _changed();
          _notify();
        }
        _tryUpdate();
      } finally {
        _pendingDrops--;
        _activity = null;
        _notify();
      }
    });
    _queue = job.catchError((Object error) {
      _stop(
        'error',
        'The experiment stopped. Save the report to review what happened.',
      );
      feed.add(FeedLine(error.toString()));
      _changed();
      _notify();
    });
    return _queue;
  }

  Future<void> _ingest(String path, Map<String, Object?> input) async {
    final ext = p.extension(path).toLowerCase();
    final name = p.basenameWithoutExtension(path);
    if (_video.contains(ext)) {
      _lastClip = null;
      _activity = 'Checking ${p.basename(path)}…';
      input['stage'] = 'fingerprint';
      _notify();
      final hash = await _fingerprint(path);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException('Expected a SHA-256 content fingerprint.');
      }
      final id = 'sha256:$hash';
      input['sha256'] = hash;
      input['clip_id'] = id;
      if (_pathHashes[path] != null && _pathHashes[path] != hash) {
        await _invalidateVoice('sha256:${_pathHashes[path]}', 'source_changed');
        _changedPaths[path] = _clock().toUtc();
        feed.add(
          FeedLine(
            'The footage in ${p.basename(path)} changed. '
            'Add new marks before using feedback on the replacement.',
          ),
        );
      }
      _pathHashes[path] = hash;
      final existing = _sources[id];
      if (existing != null) {
        existing.paths.add(path);
        for (final alias in existing.paths) {
          await _refreshMarks(existing, alias, input);
        }
        input['status'] = 'duplicate';
        input.remove('stage');
        _lastClip = id;
        feed.add(
          FeedLine(
            input.containsKey('feedback_error')
                ? 'Already added ${p.basename(path)}. Some feedback could not be refreshed; footage counted once.'
                : 'Already added ${p.basename(path)}. Refreshed its marks; footage counted once.',
          ),
        );
        return;
      }
      input['stage'] = 'probe';
      final info = await probe(path);
      if (info == null ||
          info.durationMs <= 0 ||
          !info.fps.isFinite ||
          info.fps <= 0) {
        input['status'] = 'invalid_video';
        feed.add(FeedLine('Can’t open $name as video.'));
        return;
      }
      _activity = 'Analyzing ${p.basename(path)}…';
      input['stage'] = 'analysis';
      _notify();
      final strokes = await analyze(
        ClipSource(
          clipId: id,
          path: path,
          durationMs: info.durationMs,
          fps: info.fps,
        ),
      );
      if (strokes.any((s) => s.clipId != id)) {
        throw StateError('Analysis returned strokes for a different source.');
      }
      final source = CarneSource(hash: hash, name: name, info: info)
        ..paths.add(path);
      final lines = session.addClip(name, strokes);
      _sources[id] = source;
      _pendingAthletes.remove(id);
      await _refreshMarks(source, path, input);
      for (final l in lines) {
        feed.add(
          FeedLine(
            l,
            useAnywayClip: l == CarneCopy.belowThreshold && strokes.isNotEmpty
                ? id
                : null,
          ),
        );
      }
      if (strokes.isEmpty) {
        feed.add(FeedLine('No complete strokes found in ${p.basename(path)}.'));
      }
      input['status'] = 'analyzed';
      input.remove('stage');
      _lastClip = id;
      if (athletes.found.containsKey(id)) {
        feed.add(
          FeedLine(
            'Competitor tracked in ${p.basename(path)}.',
            athleteClip: id,
          ),
        );
      }
    } else if (ext == '.txt' || ext == '.md') {
      input['kind'] = 'text';
      await _note(await _readText(path));
      input['status'] = 'note_received';
    } else if (_audio.contains(ext)) {
      input['kind'] = 'audio';
      final note = await voiceLibrary.preserve(path);
      final existing = _voiceNotes
          .where((n) => n.audioSha256 == note.audioSha256)
          .firstOrNull;
      if (existing != null) {
        input['status'] = 'duplicate_audio';
        input['voice_note_id'] = existing.id;
        feed.add(
          const FeedLine(
            'This voice note is already saved. Open Voice notes to review it.',
          ),
        );
        return;
      }
      _voiceNotes.add(note);
      input['voice_note_id'] = note.id;
      input['audio_sha256'] = note.audioSha256;
      input['status'] = 'awaiting_transcription';
      feed.add(
        const FeedLine(
          'Voice note saved on this computer. Open Voice notes to transcribe and review it.',
        ),
      );
    } else if (ext == '.zip' || ext == '.json') {
      input['kind'] = 'package';
      try {
        final other = await readProfileBundle(path);
        final o = other.profile;
        if (o.packId != pack.packId || o.eventId != pack.eventId) {
          input['status'] = 'wrong_event';
          feed.add(
            const FeedLine('That package is for another event. Ignoring it.'),
          );
        } else {
          final n = session.mergeCoachStrokes(o);
          input['status'] = 'package_received';
          input['coach_strokes_added'] = n;
          feed.add(
            FeedLine(
              n == 0
                  ? '${o.coachName} · v${o.version} adds no new coach strokes.'
                  : CarneCopy.mergedCoach(n, '${o.coachName} · v${o.version}'),
            ),
          );
        }
      } on AnalysisError catch (e) {
        input['status'] = 'failed';
        input['error'] = e.toJson();
        feed.add(FeedLine(e.message));
      }
    } else {
      input['status'] = 'unsupported';
      feed.add(FeedLine('Can’t use $name${ext.isEmpty ? '' : ext}.'));
    }
  }

  Future<void> _refreshMarks(
    CarneSource source,
    String path,
    Map<String, Object?> input,
  ) async {
    try {
      final changedAt = _changedPaths[path];
      source.marksByPath[path] = [
        for (final mark in await marks(path))
          if (changedAt == null || mark.createdAt.toUtc().isAfter(changedAt))
            mark,
      ];
      if (changedAt != null) {
        input['feedback_requires_new_marks_after'] = changedAt
            .toIso8601String();
      }
    } catch (error) {
      // A failed refresh cannot authorize learning from stale feedback.
      source.marksByPath.remove(path);
      input['feedback_error'] = error.toString();
      feed.add(
        FeedLine(
          'Couldn’t refresh feedback for ${p.basename(path)}. Other inputs will still be processed.',
        ),
      );
    }
    for (final item in session.pile.where(
      (s) => s.stroke.clipId == source.clipId,
    )) {
      item.marks
        ..clear()
        ..addAll([
          for (final mark in source.marks)
            if (mark.timeMs / 1000 >=
                    item.stroke.startFrame / item.stroke.fps &&
                mark.timeMs / 1000 <
                    (item.stroke.endFrame + 1) / item.stroke.fps)
              StrokeMark(
                attribute: mark.attribute,
                label: mark.label.name,
                author: mark.author.name,
                createdAt: mark.createdAt,
              ),
          ..._voiceMarks(item.stroke.clipId, item.stroke.index),
        ]);
    }
  }

  Iterable<StrokeMark> _voiceMarks(String clipId, int index) sync* {
    for (final note in _voiceNotes) {
      final binding = note.acceptedBinding;
      if (note.status != VoiceNoteStatus.accepted ||
          binding == null ||
          binding['invalidated_at'] != null ||
          binding['clip_id'] != clipId ||
          binding['stroke_index'] != index) {
        continue;
      }
      yield _VoiceStrokeMark(
        noteId: note.id,
        attribute: binding['attribute'] as String,
        label: binding['label'] as String,
        author: binding['author_role'] as String,
        createdAt: DateTime.parse(binding['accepted_at'] as String),
      );
    }
  }

  VoiceNote _voice(String id) => _voiceNotes.firstWhere((n) => n.id == id);

  Future<void> _invalidateVoice(String clipId, String reason) async {
    final invalid = _voiceNotes
        .where(
          (n) =>
              n.acceptedBinding?['clip_id'] == clipId &&
              n.acceptedBinding?['invalidated_at'] == null,
        )
        .toList();
    if (invalid.isEmpty) return;
    final ids = invalid.map((n) => n.id).toSet();
    for (final item in session.pile) {
      item.marks.removeWhere(
        (m) => m is _VoiceStrokeMark && ids.contains(m.noteId),
      );
    }
    // Existing proposals can depend on any earlier mark. Restore the baseline
    // conservatively; the normal bounded loop may reconsider remaining marks.
    while (session.edits.isNotEmpty) {
      session.undo();
    }
    for (final note in invalid) {
      note.acceptedBinding!['invalidated_at'] = _clock()
          .toUtc()
          .toIso8601String();
      note.acceptedBinding!['invalidated_reason'] = reason;
    }
    // Invalidate all in memory first, even if a later disk write fails.
    for (final note in invalid) {
      await voiceLibrary.save(note);
    }
    feed.add(
      const FeedLine(
        'Source changed. Earlier voice feedback was invalidated and session edits reset for fresh review.',
      ),
    );
    _changed();
  }

  Future<void> configureTranscriber(String configPath) async {
    if (voiceBusy) {
      throw StateError('Wait for transcription to finish or cancel it first.');
    }
    await voiceLibrary.configure(configPath);
    feed.add(
      const FeedLine(
        'Local voice tools are ready. Audio stays on this computer.',
      ),
    );
    _changed();
    _notify();
  }

  Future<void> transcribeVoice(String id) async {
    final note = _voice(id);
    if (_disposed ||
        voiceBusy ||
        busy ||
        note.status == VoiceNoteStatus.accepted) {
      return;
    }
    final cancellation = TranscriptionCancellation();
    _voiceJobs[id] = cancellation;
    note.status = VoiceNoteStatus.transcribing;
    note.error = null;
    _changed();
    _notify();
    try {
      await voiceLibrary.verifyAudio(note);
      final transcriber = await voiceLibrary.loadTranscriber();
      final result = await transcriber.transcribe(
        note.audioPath,
        cancellation: cancellation,
      );
      if (cancellation.isCancelled || _disposed) {
        note.status = VoiceNoteStatus.cancelled;
      } else {
        await voiceLibrary.verifyAudio(note);
        if (cancellation.isCancelled || _disposed) {
          note.status = VoiceNoteStatus.cancelled;
          return;
        }
        final transcribedHash = result.metadata['audio_sha256'];
        if (transcribedHash != null && transcribedHash != note.audioSha256) {
          throw StateError(
            'The transcribed audio changed. Add the original voice note again.',
          );
        }
        note.transcript = result;
        note.draftText = result.text;
        note.status = VoiceNoteStatus.draft;
        feed.add(
          FeedLine(
            'Transcript ready for ${note.name}. Review it before using feedback.',
          ),
        );
      }
    } catch (error) {
      note.status = cancellation.isCancelled
          ? VoiceNoteStatus.cancelled
          : VoiceNoteStatus.failed;
      note.error = error is TranscriptionException
          ? error.message
          : error.toString();
    } finally {
      try {
        await voiceLibrary.save(note);
      } catch (error) {
        note.error =
            'Couldn’t save the transcript record. Retry before accepting feedback. $error';
      }
      _voiceJobs.remove(id);
      _changed();
      _notify();
    }
  }

  void cancelVoice(String id) => _voiceJobs[id]?.cancel();

  Future<void> editVoiceDraft(String id, String text) async {
    final note = _voice(id);
    if (note.status != VoiceNoteStatus.draft) return;
    if (text.length > 32000) {
      throw StateError('Keep the reviewed transcript under 32,000 characters.');
    }
    final previous = note.draftText;
    note.draftText = text;
    try {
      await voiceLibrary.save(note);
    } catch (_) {
      note.draftText = previous;
      rethrow;
    }
    _changed();
    _notify();
  }

  Future<void> rejectVoice(String id) async {
    final note = _voice(id);
    if (busy ||
        note.status == VoiceNoteStatus.accepted ||
        note.status == VoiceNoteStatus.transcribing) {
      return;
    }
    final previous = note.status;
    note.status = VoiceNoteStatus.rejected;
    try {
      await voiceLibrary.save(note);
    } catch (_) {
      note.status = previous;
      rethrow;
    }
    _changed();
    _notify();
  }

  Future<void> acceptVoice({
    required String id,
    required String text,
    required String clipId,
    required int strokeIndex,
    required String authorName,
    required String authorRole,
    required String attribute,
    required String label,
  }) async {
    if (busy || _disposed) {
      throw StateError('Wait for the current operation to finish.');
    }
    final note = _voice(id);
    if (note.status != VoiceNoteStatus.draft) {
      throw StateError('This transcript is no longer awaiting review.');
    }
    if (text.trim().isEmpty ||
        text.length > 32000 ||
        authorName.trim().isEmpty ||
        authorName.length > 200 ||
        !{'coach', 'athlete'}.contains(authorRole) ||
        !attributes.contains(attribute) ||
        !{'red', 'green'}.contains(label)) {
      throw StateError(
        'Review the text and select the author, attribute and red or green feedback.',
      );
    }
    _pendingDrops++;
    _notify();
    final job = _queue.then((_) async {
      final source = _sources[clipId];
      final matching = session.pile
          .where(
            (s) => s.stroke.clipId == clipId && s.stroke.index == strokeIndex,
          )
          .toList();
      if (source == null ||
          matching.length != 1 ||
          matching.single.ignored ||
          _pendingAthletes.isNotEmpty ||
          note.status != VoiceNoteStatus.draft) {
        throw StateError(
          'Choose a current clip and swing after resolving competitor selection.',
        );
      }
      var sourcePresent = false;
      for (final path in source.paths) {
        try {
          if (await _fingerprint(path) == source.hash) sourcePresent = true;
        } catch (_) {
          /* Try another preserved alias. */
        }
      }
      if (!sourcePresent) {
        throw StateError(
          'The selected footage changed or is missing. Add it again and review the new source.',
        );
      }
      await voiceLibrary.verifyAudio(note);
      if (_disposed) {
        throw StateError(
          'The experiment closed before the feedback was accepted.',
        );
      }
      final target = voiceTargets.singleWhere(
        (t) => t.clipId == clipId && t.strokeIndex == strokeIndex,
      );
      final at = _clock().toUtc().toIso8601String();
      final previousText = note.draftText;
      note.acceptedBinding = {
        'session_id': sessionId,
        'clip_id': clipId,
        'source_sha256': source.hash,
        'source_name': source.name,
        'pack_id': pack.packId,
        'event_id': pack.eventId,
        'stroke_index': strokeIndex,
        'start_ms': target.startMs,
        'end_ms': target.endMs,
        'time_ms': target.startMs,
        'author_name': authorName.trim(),
        'author_role': authorRole,
        'attribute': attribute,
        'label': label,
        'reviewed_text': text.trim(),
        'accepted_at': at,
      };
      note.draftText = text.trim();
      note.status = VoiceNoteStatus.accepted;
      try {
        // Durably record consent/provenance before adding a mark or learning.
        await voiceLibrary.save(note);
      } catch (_) {
        note.acceptedBinding = null;
        note.draftText = previousText;
        note.status = VoiceNoteStatus.draft;
        rethrow;
      }
      if (_disposed) return;
      matching.single.marks.add(
        _VoiceStrokeMark(
          noteId: note.id,
          attribute: attribute,
          label: label,
          author: authorRole,
          createdAt: DateTime.parse(at),
        ),
      );
      feed.add(
        FeedLine(
          'Reviewed feedback added to ${source.name} at ${(target.startMs / 1000).toStringAsFixed(2)} s.',
        ),
      );
      _changed();
      _tryUpdate();
    });
    _queue = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await job;
    } finally {
      _pendingDrops--;
      _notify();
    }
  }

  /// Text notes: `priority: ATTRIBUTE` and `ignore this clip`.
  Future<void> _note(String text) async {
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim().toLowerCase();
      if (line.startsWith('priority:')) {
        final want = line.substring('priority:'.length).trim();
        final attr = priorities
            .where((a) => a.toLowerCase() == want)
            .firstOrNull;
        // Apply all notes (including ignores) before the batch runs the loop.
        if (attr != null) _setPriority(attr, update: false);
      } else if (line == 'ignore this clip' && _lastClip != null) {
        final source = _sources[_lastClip!]!;
        session.ignore(source.name, clipId: source.clipId);
        feed.add(FeedLine('Ignoring ${source.name}.'));
      }
    }
  }

  /// Reads a text note (injectable for tests).
  Future<String> Function(String path) readText = _defaultRead;
  Future<String> _readText(String path) => readText(path);

  void useAnyway(String clip) {
    if (busy) return;
    final source = _sources[clip];
    if (source == null) return;
    session.useAnyway(source.name, clipId: source.clipId);
    feed.add(FeedLine('Added ${source.name} to the pile anyway.'));
    _changed();
    _tryUpdate();
    _notify();
  }

  Future<void> chooseAthlete(String id, AthleteTarget? target) async {
    if (busy || !canChangeSettings) return;
    final clip = athletes.clips[id];
    if (clip == null) return;
    if (target == null) {
      athletes.targets.remove(id);
    } else {
      athletes.targets[id] = target;
    }
    final aliases = _sources[id]?.paths.toList() ?? [clip.path];
    if (_sources.containsKey(id)) {
      await _invalidateVoice(id, 'competitor_changed');
      for (final path in aliases) {
        _changedPaths[path] = _clock().toUtc();
      }
      feed.add(
        const FeedLine(
          'Competitor changed. Add new marks for the selected competitor.',
        ),
      );
    }
    // Corrections replace this source's measurements; they never add minutes.
    session.pile.removeWhere((s) => s.stroke.clipId == id);
    _sources.remove(id);
    _changed();
    await drop(aliases);
  }

  /// Runs loop steps until nothing more is accepted (or the limit).
  void _tryUpdate() {
    if (_pendingAthletes.isNotEmpty) {
      _stop(
        'choose competitor',
        'Choose the competitor before this experiment can update.',
      );
      return;
    }
    if (_sources.isEmpty &&
        _inputs.any(
          (i) => i['status'] == 'failed' || i['status'] == 'invalid_video',
        )) {
      _stop(
        'input error',
        'No footage was added. Review the input errors below.',
      );
      return;
    }
    for (var i = 0; i < session.limit && !session.limitReached; i++) {
      final r = session.step();
      _changed();
      switch (r) {
        case StepAccepted(:final edit):
          _attempts.add({
            'at': _clock().toUtc().toIso8601String(),
            'outcome': 'accepted',
            'edit_index': session.edits.length,
            'explanation': edit.explanation,
          });
          feed.add(FeedLine(edit.status));
          feed.add(FeedLine(CarneCopy.tally(session.edits.length)));
        case StepRejected(:final message):
          _attempts.add({
            'at': _clock().toUtc().toIso8601String(),
            'outcome': 'rejected',
            'message': message,
          });
          feed.add(FeedLine(message));
          _stop('rejected', message);
          return;
        case StepIdle(:final reason):
          _attempts.add({
            'at': _clock().toUtc().toIso8601String(),
            'outcome': 'idle',
            'reason': reason,
          });
          _stop(reason, switch (reason) {
            'below baseline' => 'Insufficient usable footage for an update.',
            'no marks' =>
              'Waiting for coach or athlete feedback on ${session.priority.toLowerCase()}.',
            'no metrics for priority' =>
              'This profile has no measurements for ${session.priority.toLowerCase()}.',
            'nothing to change' =>
              'No supported update is available for ${session.priority.toLowerCase()}.',
            'no improvement' =>
              'No proposal improved ${session.priority.toLowerCase()} within the session limits.',
            'limit' => 'Session edit limit reached.',
            _ => 'No update is available for this session.',
          });
          return;
      }
    }
    if (session.limitReached) _stop('limit', 'Session edit limit reached.');
  }

  void _stop(String reason, String message) {
    _stopReason = reason;
    _stopMessage = message;
    if (feed.isEmpty || feed.last.text != message) feed.add(FeedLine(message));
  }

  void _changed() => _revision++;

  /// "Look for an update" button.
  void tryUpdate() {
    if (busy) return;
    _tryUpdate();
    _notify();
  }

  void undo() {
    if (busy) return;
    final e = session.undo();
    if (e == null) return;
    feed.add(FeedLine('Undid: ${e.explanation}'));
    feed.add(FeedLine(CarneCopy.tally(session.edits.length)));
    _changed();
    _stop(
      'undone',
      'Last update undone. Look for an update when you are ready.',
    );
    _notify();
  }

  /// A standalone audit snapshot; never imported as a coaching profile.
  Map<String, Object?> runReport() {
    final settings = <String, Object?>{
      'pack_id': pack.packId,
      'event_id': pack.eventId,
      'metric_schema_version': pack.metricSchemaVersion,
      'phases': pack.phases,
      'phase_events': pack.phaseEvents,
      'stroke_signal': pack.strokeSignal,
      'min_phase_frames': pack.minPhaseFrames,
      'min_pose_confidence': pack.minPoseConfidence,
      'critical_phases': pack.criticalPhases,
      'min_critical_pose_confidence': pack.minCriticalPoseConfidence,
      'max_implement_dropout_s': pack.maxImplementDropoutS,
      'attribute_metrics': pack.attributeMetrics,
      'metrics': [
        for (final m in pack.metrics)
          {
            'key': m.key,
            'kind': m.kind.wire,
            'phase': m.phase,
            'unit': m.unit,
            'joints': [for (final joint in m.joints) joint.name],
            'weight': m.weight,
            'min_spread': m.minSpread,
            'aggregate': m.aggregate.name,
          },
      ],
      'priority': session.priority,
      'edit_limit': session.limit,
      'chaos': session.chaos,
      'meters_minutes': {
        'good': session.meters.good,
        'great': session.meters.great,
        'excellent': session.meters.excellent,
      },
    };
    final report = <String, Object?>{
      'format': 'carne_asada_run/1',
      'session_id': sessionId,
      'started_at': startedAt.toIso8601String(),
      'exported_at': _clock().toUtc().toIso8601String(),
      'run_revision': _revision,
      'base_profile': {
        'profile_id': bundle.profile.profileId,
        'version': bundle.profile.version,
        'sha256_canonical_json': canonicalHash(bundle.profile.toJson()),
      },
      'base_profile_snapshot': bundle.profile.toJson(),
      'patches_sha256_canonical_json': canonicalHash(bundle.patchFiles),
      'adapters_sha256_canonical_json': canonicalHash(bundle.adapterFiles),
      'settings': settings,
      'settings_sha256_canonical_json': canonicalHash(settings),
      'analysis_pipeline': {
        ...analysisMetadata,
        'ground_truth_accuracy_verified': false,
      },
      'inputs': _inputs,
      'voice_notes': [for (final note in _voiceNotes) note.toJson()],
      'sources': [
        for (final source in _sources.values)
          {
            'clip_id': source.clipId,
            'sha256': source.hash,
            'display_name': source.name,
            'paths': source.paths.toList(),
            'duration_ms': source.info.durationMs,
            'fps': source.info.fps,
            'athlete': athletes.metadata(source.clipId),
            'strokes': session.pile
                .where((s) => s.stroke.clipId == source.clipId)
                .length,
            'quality_passing_strokes': session.pile
                .where(
                  (s) => s.stroke.clipId == source.clipId && s.stroke.usable,
                )
                .length,
            'rejections': {
              for (final issue in StrokeIssue.values)
                issue.name: session.pile
                    .where(
                      (s) =>
                          s.stroke.clipId == source.clipId &&
                          s.stroke.issues.contains(issue),
                    )
                    .length,
            },
          },
      ],
      'strokes': [
        for (final item in session.pile)
          {
            'clip_id': item.stroke.clipId,
            'index': item.stroke.index,
            'start_frame': item.stroke.startFrame,
            'end_frame': item.stroke.endFrame,
            'fps': item.stroke.fps,
            'quality_passed': item.stroke.usable,
            'issues': [for (final issue in item.stroke.issues) issue.name],
            'measurement': item.stroke.detail.outcome.toJson(),
            'phase_pose_confidence': item.stroke.detail.phasePoseConfidence,
            'implement_dropout_s': item.stroke.dropoutSeconds,
            'forced': item.forced,
            'ignored': item.ignored,
            'counts': item.counts,
            'marks': [
              for (final mark in item.marks)
                {
                  'attribute': mark.attribute,
                  'label': mark.label,
                  'author': mark.author,
                  'created_at': mark.createdAt.toUtc().toIso8601String(),
                },
            ],
          },
      ],
      'stop': {'reason': _stopReason, 'message': _stopMessage},
      'loop_attempts': _attempts,
      'session': session.editsLog(
        version: bundle.profile.version,
        sessionId: sessionId,
      ),
      'status_feed': [for (final line in feed) line.text],
      'saved_profile_path': savedPath,
    };
    // Do not expose mutable session collections to the caller/exporter.
    return jsonDecode(jsonEncode(report)) as Map<String, Object?>;
  }

  Future<void> saveRun(ExperimentWriter writer) {
    if (!canSaveRun) return Future.value();
    final revision = _revision;
    final contents =
        '${const JsonEncoder.withIndent('  ').convert(runReport())}\n';
    _savingRun = true;
    _activity = 'Saving experiment…';
    _notify();
    final job = Future<void>.microtask(() async {
      try {
        final path = await writer('carne_asada_run_$sessionId.json', contents);
        if (path != null) {
          savedRunPath = path;
          _savedRunRevision = revision;
          feed.add(const FeedLine('Experiment saved.'));
        }
      } catch (error) {
        feed.add(
          FeedLine('Couldn’t save the experiment. Try again. Details: $error'),
        );
        _changed();
      } finally {
        _savingRun = false;
        _activity = null;
        _notify();
      }
    });
    _queue = job;
    return job;
  }

  /// Writes the next package version: the edited mixture in profile.json
  /// and the session record in `carne_asada/mixture_edits_vN.json`.
  Future<void> save() {
    if (!canSaveProfile) return Future.value();
    _savingProfile = true;
    _activity = 'Saving the new profile version…';
    _notify();
    final job = Future<void>.microtask(_saveProfile);
    _queue = job;
    return job;
  }

  Future<void> _saveProfile() async {
    try {
      final p0 = session.editedProfile;
      final version = p0.version + 1;
      final next = Profile(
        profileId: p0.profileId,
        version: version,
        coachName: p0.coachName,
        packId: p0.packId,
        eventId: p0.eventId,
        metricSchemaVersion: p0.metricSchemaVersion,
        createdAt: _clock().toUtc(),
        sourceClipCount: p0.sourceClipCount,
        minClipsMet: p0.minClipsMet,
        selfConsistencyPassed: p0.selfConsistencyPassed,
        notes:
            '${p0.notes} CARNE ASADA: ${session.edits.length} edits on ${session.priority}.'
                .trim(),
        metrics: p0.metrics,
        referenceClips: p0.referenceClips,
      );
      savedPath = await write(next, bundle.patchFiles, bundle.adapterFiles, {
        'mixture_edits_v$version.json': const JsonEncoder.withIndent('  ')
            .convert(session.editsLog(version: version, sessionId: sessionId)),
      });
      _changed();
    } catch (error) {
      feed.add(
        FeedLine('Couldn’t save the profile. Try again. Details: $error'),
      );
      _changed();
    } finally {
      _savingProfile = false;
      _activity = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final job in _voiceJobs.values) {
      job.cancel();
    }
    super.dispose();
  }
}

Future<String> _defaultRead(String path) => File(path).readAsString();
