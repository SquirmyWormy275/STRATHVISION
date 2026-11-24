import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:strathvision/workbench/carne_controller.dart';
import 'package:strathvision/workbench/local_transcriber.dart';

import 'support/carne_fixture.dart';

// Synthetic controller fixtures establish consent/provenance, not speech or
// coaching accuracy. Real recorded speech is a separate native acceptance run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarneFixture fixture;
  late Directory root, storage;
  late File audio;
  setUpAll(() async => fixture = await CarneFixture.load());
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sv-voice-');
    storage = Directory(p.join(root.path, 'saved'));
    audio = await File(p.join(root.path, 'coach.wav'))
        .writeAsString('synthetic audio bytes');
  });
  tearDown(() async => root.delete(recursive: true));

  CarneController controller({
    VoiceTranscriber? transcriber,
    VoiceNoteLibrary? library,
    Future<String> Function(String)? fingerprint,
  }) {
    final c = fixture.controller(
      voiceLibrary:
          library ??
          VoiceNoteLibrary(
            directory: () async => storage,
            transcriber: transcriber ?? _FakeTranscriber(),
          ),
      fingerprint:
          fingerprint ??
          (path) async => sha256.convert(utf8.encode(path)).toString(),
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<VoiceNote> draft(CarneController c) async {
    await c.drop(['/clip.mp4', audio.path]);
    final note = c.voiceNotes.single;
    await c.transcribeVoice(note.id);
    expect(note.status, VoiceNoteStatus.draft);
    return note;
  }

  Future<void> accept(
    CarneController c,
    VoiceNote note, {
    String? name,
    String? source,
    int? stroke,
  }) {
    final target = c.voiceTargets.first;
    return c.acceptVoice(
      id: note.id,
      text: 'The reviewed correction.',
      clipId: source ?? target.clipId,
      strokeIndex: stroke ?? target.strokeIndex,
      authorName: name ?? 'Reviewer',
      authorRole: 'coach',
      attribute: 'Slope',
      label: 'green',
    );
  }

  test(
    'preserves original bytes without model and core review remains usable',
    () async {
      final c = controller(
        library: VoiceNoteLibrary(directory: () async => storage),
      );
      await c.drop([audio.path]);
      final note = c.voiceNotes.single;
      await audio.delete();
      await c.transcribeVoice(note.id);
      expect(note.status, VoiceNoteStatus.failed);
      expect(note.error, contains('optional'));
      expect(
        await File(note.audioPath).readAsString(),
        'synthetic audio bytes',
      );
      expect(c.voiceBusy, isFalse);
      await c.drop(['/clip.mp4']);
      expect(c.session.pile, isNotEmpty);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      expect(c.canSaveRun, isTrue);
    },
  );

  test(
    'draft commands cannot change priority, ignore footage or create marks',
    () async {
      final c = controller();
      final note = await draft(c);
      expect(note.draftText, contains('priority: hinge'));
      expect(c.session.priority, 'Slope');
      expect(c.session.pile.any((s) => s.ignored), isFalse);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      expect(c.session.edits, isEmpty);
      await c.rejectVoice(note.id);
      expect(note.status, VoiceNoteStatus.rejected);
      await expectLater(accept(c, note), throwsStateError);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
    },
  );

  test(
    'acceptance binds edited text, explicit source/event/time and author once',
    () async {
      final c = controller();
      final note = await draft(c);
      await expectLater(accept(c, note, name: ' '), throwsStateError);
      await expectLater(accept(c, note, source: 'wrong'), throwsStateError);
      await expectLater(accept(c, note, stroke: -1), throwsStateError);
      await accept(c, note);
      final binding = note.acceptedBinding!;
      expect(binding['reviewed_text'], 'The reviewed correction.');
      expect(
        binding['source_sha256'],
        c.voiceTargets.first.clipId.substring(7),
      );
      expect(binding['event_id'], c.pack.eventId);
      expect(binding['pack_id'], c.pack.packId);
      expect(binding['time_ms'], c.voiceTargets.first.startMs);
      expect(binding['end_ms'], greaterThan(binding['start_ms'] as int));
      expect(binding['author_name'], 'Reviewer');
      expect(binding['author_role'], 'coach');
      expect(c.session.pile.expand((s) => s.marks), hasLength(1));
      await expectLater(accept(c, note), throwsStateError);
      await c.drop(['/clip.mp4', audio.path]);
      expect(c.voiceNotes, hasLength(1));
      expect(c.session.pile.expand((s) => s.marks), hasLength(1));
      final saved = jsonDecode(
        await File(p.join(storage.path, '${note.id}.json')).readAsString(),
      ) as Map;
      expect(saved['binding'], binding);
      expect(
        (saved['transcription'] as Map)['text'],
        contains('ignore this clip'),
      );
      final report = c.runReport();
      expect((report['voice_notes'] as List).single['binding'], binding);
      expect(jsonEncode(report), isNot(contains('synthetic audio bytes')));
    },
  );

  test(
    'changed footage or saved audio blocks acceptance and permits recovery',
    () async {
      var current = 'a' * 64;
      final c = controller(fingerprint: (_) async => current);
      final note = await draft(c);
      current = 'b' * 64;
      await expectLater(accept(c, note), throwsStateError);
      expect(note.status, VoiceNoteStatus.draft);
      expect(c.busy, isFalse);
      current = 'a' * 64;
      await File(note.audioPath).writeAsString('changed');
      await expectLater(accept(c, note), throwsStateError);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      await File(note.audioPath).writeAsString('synthetic audio bytes');
      await accept(c, note);
      expect(note.status, VoiceNoteStatus.accepted);
    },
  );

  test('replacement footage invalidates accepted voice marks', () async {
    var hash = 'a' * 64;
    final c = controller(fingerprint: (_) async => hash);
    final note = await draft(c);
    await accept(c, note);
    hash = 'b' * 64;
    await c.drop(['/clip.mp4']);
    expect(note.acceptedBinding!['invalidated_reason'], 'source_changed');
    expect(c.session.pile.expand((s) => s.marks), isEmpty);
  });

  test(
    'only explicit review enables learning with sufficient footage',
    () async {
      var replacement = false;
      final c = controller(
        fingerprint: (path) async => sha256
            .convert(
              utf8.encode(
                path == '/one.mp4' && replacement ? 'replacement' : path,
              ),
            )
            .toString(),
      );
      await c.drop(['/one.mp4', '/two.mp4', '/three.mp4', audio.path]);
      expect(c.session.baselineMet, isTrue);
      final note = c.voiceNotes.single;
      await c.transcribeVoice(note.id);
      expect(c.session.edits, isEmpty);
      final stroke = c.session.pile.firstWhere((s) => s.counts).stroke;
      await c.acceptVoice(
        id: note.id,
        text: 'Reviewed synthetic feedback.',
        clipId: stroke.clipId,
        strokeIndex: stroke.index,
        authorName: 'Fixture reviewer',
        authorRole: 'coach',
        attribute: 'Slope',
        label: 'green',
      );
      expect(c.session.edits, isNotEmpty);
      for (final edit in c.session.edits) {
        final hull = c.session.hull[edit.metric]!;
        expect(edit.after.center, inInclusiveRange(hull.$1, hull.$2));
      }
      expect(c.session.edits.length, lessThanOrEqualTo(c.session.limit));
      expect(note.acceptedBinding, isNotNull);
      replacement = true;
      await c.drop(['/one.mp4']);
      expect(note.acceptedBinding!['invalidated_reason'], 'source_changed');
      expect(c.session.edits, isEmpty);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
    },
  );

  test(
    'failed invalidation save cannot resurrect any accepted voice mark',
    () async {
      var hash = 'a' * 64;
      final library = _FailingLibrary(storage);
      final c = controller(library: library, fingerprint: (_) async => hash);
      final first = await draft(c);
      await accept(c, first);
      final secondAudio = await File(p.join(root.path, 'second.wav'))
          .writeAsString('different synthetic audio bytes');
      await c.drop([secondAudio.path]);
      final second = c.voiceNotes.last;
      await c.transcribeVoice(second.id);
      await accept(c, second);
      expect(c.session.pile.expand((s) => s.marks), hasLength(2));

      library.fail = true;
      hash = 'b' * 64;
      await c.drop(['/clip.mp4']);
      expect((c.runReport()['inputs'] as List).last['status'], 'failed');
      for (final note in [first, second]) {
        expect(note.acceptedBinding!['invalidated_reason'], 'source_changed');
      }
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      expect(c.session.edits, isEmpty);

      // The failed replacement left the original source in the session.
      // Restoring it forces _refreshMarks to read both accepted bindings.
      hash = 'a' * 64;
      await c.drop(['/clip.mp4']);
      expect((c.runReport()['inputs'] as List).last['status'], 'duplicate');
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      expect(c.session.edits, isEmpty);
    },
  );

  test(
    'cancellation during final audio verification discards the result',
    () async {
      final library = _VerificationGateLibrary(storage);
      final c = controller(library: library);
      await c.drop([audio.path]);
      final note = c.voiceNotes.single;
      final job = c.transcribeVoice(note.id);
      await library.verifying.future;
      c.cancelVoice(note.id);
      library.resume.complete();
      await job;

      expect(note.status, VoiceNoteStatus.cancelled);
      expect(note.transcript, isNull);
      expect(note.draftText, isNull);
      expect(c.voiceBusy, isFalse);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
      final saved = jsonDecode(
        await File(p.join(storage.path, '${note.id}.json')).readAsString(),
      ) as Map;
      expect(saved['status'], 'cancelled');
      expect(saved.containsKey('transcription'), isFalse);

      await c.transcribeVoice(note.id);
      expect(note.status, VoiceNoteStatus.draft);
    },
  );

  test(
    'cancellation during final persistence retracts draft and permits retry',
    () async {
      final library = _DraftSaveGateLibrary(storage);
      final c = controller(library: library);
      await c.drop([audio.path]);
      final note = c.voiceNotes.single;
      final job = c.transcribeVoice(note.id);
      await library.savedDraft.future;
      expect(c.voiceBusy, isTrue);
      c.cancelVoice(note.id);
      library.resume.complete();
      await job;

      expect(note.status, VoiceNoteStatus.cancelled);
      expect(note.transcript, isNull);
      expect(note.draftText, isNull);
      expect(c.voiceBusy, isFalse);
      expect(File(note.audioPath).existsSync(), isTrue);
      final saved = jsonDecode(
        await File(p.join(storage.path, '${note.id}.json')).readAsString(),
      ) as Map;
      expect(saved['status'], 'cancelled');
      expect(saved['draft_text'], isNull);
      expect(saved.containsKey('transcription'), isFalse);
      expect(
        c.feed.any((line) => line.text.startsWith('Transcript ready')),
        isFalse,
      );

      await c.transcribeVoice(note.id);
      expect(note.status, VoiceNoteStatus.draft);
      expect(note.draftText, isNotEmpty);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);
    },
  );

  test(
    'mismatched transcribed audio cannot become a draft; retry works',
    () async {
      var wrongHash = true;
      final expectedHash = sha256.convert(await audio.readAsBytes()).toString();
      final c = controller(
        transcriber: _FakeTranscriber(
          run: () async => VoiceTranscript(
            text: 'Text from the selected audio',
            engine: 'fake',
            model: 'fake',
            metadata: {'audio_sha256': wrongHash ? 'f' * 64 : expectedHash},
          ),
        ),
      );
      await c.drop(['/clip.mp4', audio.path]);
      final note = c.voiceNotes.single;
      await c.transcribeVoice(note.id);
      expect(note.status, VoiceNoteStatus.failed);
      expect(note.error, contains('transcribed audio changed'));
      expect(note.transcript, isNull);
      expect(note.draftText, isNull);
      await expectLater(accept(c, note), throwsStateError);
      expect(c.session.pile.expand((s) => s.marks), isEmpty);

      wrongHash = false;
      await c.transcribeVoice(note.id);
      expect(note.status, VoiceNoteStatus.draft);
      expect(note.transcript!.metadata['audio_sha256'], note.audioSha256);
      expect(note.draftText, 'Text from the selected audio');
    },
  );

  test('cancellation does not block footage review or apply late results; retry works', () async {
    final pending = Completer<VoiceTranscript>();
    final started = Completer<void>();
    var calls = 0;
    final c = controller(
      transcriber: _FakeTranscriber(
        run: () async {
          if (calls++ == 0) {
            started.complete();
            return pending.future;
          }
          return const VoiceTranscript(
            text: 'Retry text',
            engine: 'fake',
            model: 'fake',
          );
        },
      ),
    );
    await c.drop([audio.path]);
    final note = c.voiceNotes.single;
    final job = c.transcribeVoice(note.id);
    await started.future;
    expect(c.voiceBusy, isTrue);
    expect(c.busy, isFalse);
    await c.drop(['/clip.mp4']);
    c.cancelVoice(note.id);
    pending.complete(
      const VoiceTranscript(text: 'Late draft', engine: 'fake', model: 'fake'),
    );
    await job;
    expect(note.status, VoiceNoteStatus.cancelled);
    expect(note.draftText, isNull);
    expect(c.session.pile.expand((s) => s.marks), isEmpty);
    await c.transcribeVoice(note.id);
    expect(note.draftText, 'Retry text');
    expect(c.voiceBusy, isFalse);
  });

  test('persistence failure cannot authorize a mark', () async {
    final library = _FailingLibrary(storage);
    final c = controller(library: library);
    final note = await draft(c);
    library.fail = true;
    final before = note.draftText;
    await c.saveRun((_, _) async => '/synthetic-snapshot.json');
    expect(c.runSaved, isTrue);
    await expectLater(
      c.editVoiceDraft(note.id, 'Unsaved edit'),
      throwsStateError,
    );
    expect(note.draftText, before);
    expect(c.runSaved, isTrue);
    await expectLater(accept(c, note), throwsStateError);
    expect(note.status, VoiceNoteStatus.draft);
    expect(note.acceptedBinding, isNull);
    expect(c.session.pile.expand((s) => s.marks), isEmpty);
    library.fail = false;
    await accept(c, note);
    expect(c.session.pile.expand((s) => s.marks), hasLength(1));
  });
}

class _FakeTranscriber implements VoiceTranscriber {
  _FakeTranscriber({this.run});
  final Future<VoiceTranscript> Function()? run;
  @override
  Future<VoiceTranscript> transcribe(
    String path, {
    required TranscriptionCancellation cancellation,
  }) async => run != null
      ? await run!()
      : const VoiceTranscript(
          text: 'priority: hinge\nignore this clip\n',
          engine: 'synthetic protocol fixture',
          model: 'none',
        );
}

class _FailingLibrary extends VoiceNoteLibrary {
  _FailingLibrary(Directory directory)
    : super(directory: () async => directory, transcriber: _FakeTranscriber());
  bool fail = false;
  @override
  Future<void> save(VoiceNote note) {
    if (fail) throw StateError('Simulated disk failure');
    return super.save(note);
  }
}

class _VerificationGateLibrary extends VoiceNoteLibrary {
  _VerificationGateLibrary(Directory directory)
    : super(directory: () async => directory, transcriber: _FakeTranscriber());
  final verifying = Completer<void>();
  final resume = Completer<void>();
  var calls = 0;

  @override
  Future<void> verifyAudio(VoiceNote note) async {
    await super.verifyAudio(note);
    if (++calls == 2) {
      verifying.complete();
      await resume.future;
    }
  }
}

class _DraftSaveGateLibrary extends VoiceNoteLibrary {
  _DraftSaveGateLibrary(Directory directory)
    : super(directory: () async => directory, transcriber: _FakeTranscriber());
  final savedDraft = Completer<void>();
  final resume = Completer<void>();
  var gateNextDraft = true;

  @override
  Future<void> save(VoiceNote note) async {
    await super.save(note);
    if (note.status == VoiceNoteStatus.draft && gateNextDraft) {
      gateNextDraft = false;
      savedDraft.complete();
      await resume.future;
    }
  }
}
