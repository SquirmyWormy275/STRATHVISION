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
