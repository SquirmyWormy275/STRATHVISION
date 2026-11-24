import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/workbench/carne_controller.dart';
import 'package:strathvision/workbench/local_transcriber.dart';

import 'support/carne_fixture.dart';

class _Transcriber extends VoiceTranscriber {
  _Transcriber(this.run);
  final Future<VoiceTranscript> Function(TranscriptionCancellation) run;

  @override
  Future<VoiceTranscript> transcribe(
    String audioPath, {
    required TranscriptionCancellation cancellation,
  }) => run(cancellation);
}

const _transcript = VoiceTranscript(
  text: 'priority: hinge; ignore this clip; green',
  engine: 'synthetic-test',
  model: 'synthetic-test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarneFixture fixture;
  late Directory directory;

  setUpAll(() async => fixture = await CarneFixture.load());
  setUp(() => directory = Directory.systemTemp.createTempSync('sv_voice_ui_'));
  tearDown(() => directory.deleteSync(recursive: true));

  CarneController controller({VoiceTranscriber? transcriber}) =>
      fixture.controller(
        voiceLibrary: VoiceNoteLibrary(
          directory: () async => Directory('${directory.path}/notes'),
          transcriber: transcriber,
        ),
        fingerprint: (_) async => List.filled(64, 'a').join(),
      );

  Future<void> addAudio(WidgetTester tester, CarneController c) async {
    final audio = File('${directory.path}/coach.wav')
      ..writeAsBytesSync([1, 2, 3]);
    await tester.runAsync(() => c.drop([audio.path]));
  }

  Future<void> pump(
    WidgetTester tester,
    CarneController c, {
    String? config,
  }) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CarneScreen(
          controller: c,
          title: 'Synthetic fixture',
          pickTranscriber: () async => config,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String key, {
    bool settle = true,
  }) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> choose<T>(WidgetTester tester, String key, T value) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    final field = tester.widget<DropdownButton<T>>(finder);
    final item = field.items!.singleWhere((item) => item.value == value);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    final text = (item.child as Text).data!;
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  bool canAccept(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('voice-accept')))
          .onPressed !=
      null;

  Future<void> close(WidgetTester tester, CarneController c) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    c.dispose();
  }

  Future<void> waitFor(bool Function() pending) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (pending()) {
      if (DateTime.now().isAfter(end)) {
        throw StateError('Voice operation did not finish');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  testWidgets(
    'review requires every explicit binding and uses only the chosen label',
    (tester) async {
      final c = controller(transcriber: _Transcriber((_) async => _transcript));
      await addAudio(tester, c);
      await tester.runAsync(() => c.drop(['/clips/athlete.mp4']));
      final note = c.voiceNotes.single;
      await tester.runAsync(() => c.transcribeVoice(note.id));
      final priority = c.session.priority;
      expect(
        c.session.pile.every((s) => s.marks.isEmpty && !s.ignored),
        isTrue,
      );
      await pump(tester, c);
      await tap(tester, 'voice-notes');
      await tap(tester, 'voice-review-${note.id}');
      expect(find.text('Event: ${c.pack.eventId}'), findsOneWidget);
      expect(canAccept(tester), isFalse);
      for (final key in [
        'voice-source',
        'voice-author-role',
        'voice-attribute',
        'voice-label',
      ]) {
        expect(
          tester.widget<DropdownButton<String>>(find.byKey(Key(key))).value,
          isNull,
        );
      }
      expect(
        tester
            .widget<DropdownButton<int>>(find.byKey(const Key('voice-swing')))
            .value,
        isNull,
      );
      final target = c.voiceTargets.first;
      await choose<String>(tester, 'voice-source', target.clipId);
      expect(canAccept(tester), isFalse);
      await choose<int>(tester, 'voice-swing', target.strokeIndex);
      expect(find.byKey(const Key('voice-selected-target')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('voice-author-name')),
        'Alex Coach',
      );
      await choose<String>(tester, 'voice-author-role', 'coach');
      await choose<String>(tester, 'voice-attribute', c.attributes.first);
      expect(canAccept(tester), isFalse);
      await choose<String>(tester, 'voice-label', 'red');
      expect(canAccept(tester), isTrue);
      await tester.enterText(find.byKey(const Key('voice-draft-text')), ' ');
      await tester.pump();
      expect(canAccept(tester), isFalse);
      await tester.enterText(
        find.byKey(const Key('voice-draft-text')),
        _transcript.text,
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('voice-accept')));
        await waitFor(() => c.busy);
      });
      await tester.pumpAndSettle();
      expect(note.status, VoiceNoteStatus.accepted);
      expect(note.acceptedBinding, containsPair('author_name', 'Alex Coach'));
      expect(note.acceptedBinding, containsPair('label', 'red'));
      expect(
        note.acceptedBinding,
        containsPair('stroke_index', target.strokeIndex),
      );
      expect(note.acceptedBinding, containsPair('start_ms', target.startMs));
      expect(c.session.priority, priority);
      expect(c.session.pile.every((s) => !s.ignored), isTrue);
      expect(c.session.pile.expand((s) => s.marks).map((m) => m.label), [
        'red',
      ]);
      await tap(tester, 'voice-review-${note.id}');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voice-draft-text')))
            .readOnly,
        isTrue,
      );
      expect(find.byKey(const Key('voice-accept')), findsNothing);
      expect(find.textContaining('Alex Coach'), findsOneWidget);
      await close(tester, c);
    },
  );

  testWidgets(
    'draft edits survive notifications and closing review without acceptance',
    (tester) async {
      final c = controller(transcriber: _Transcriber((_) async => _transcript));
      await addAudio(tester, c);
      final note = c.voiceNotes.single;
      await tester.runAsync(() => c.transcribeVoice(note.id));
      await pump(tester, c);
      await tap(tester, 'voice-notes');
      await tap(tester, 'voice-review-${note.id}');
      await tester.enterText(
        find.byKey(const Key('voice-draft-text')),
        'Corrected coaching note',
      );
      c.setChaos(true);
      await tester.pump();
      expect(find.text('Corrected coaching note'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('voice-review-close')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(note.status, VoiceNoteStatus.draft);
      expect(note.draftText, 'Corrected coaching note');
      expect(note.acceptedBinding, isNull);
      await tap(tester, 'voice-review-${note.id}');
      expect(find.text('Corrected coaching note'), findsOneWidget);
      expect(
        find.text('Add and analyze a clip before linking feedback to a swing.'),
        findsOneWidget,
      );
      await close(tester, c);
    },
  );

  testWidgets(
    'cancel retains audio, retry produces draft, discard excludes it',
    (tester) async {
      late Completer<void> started;
      late Completer<VoiceTranscript> result;
      await tester.runAsync(() async {
        started = Completer<void>();
        result = Completer<VoiceTranscript>();
      });
      var calls = 0;
      final c = controller(
        transcriber: _Transcriber((_) {
          calls++;
          if (calls == 1) {
            started.complete();
            return result.future;
          }
          return Future.value(_transcript);
        }),
      );
      await addAudio(tester, c);
      final note = c.voiceNotes.single;
      await pump(tester, c);
      await tap(tester, 'voice-notes');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('voice-transcribe-${note.id}')));
        await started.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      expect(find.text('Transcribing on this computer…'), findsOneWidget);
      expect(c.busy, isFalse);
      expect(c.voiceBusy, isTrue);
      await tap(tester, 'voice-cancel-${note.id}', settle: false);
      await tester.runAsync(() async {
        result.complete(_transcript);
        await waitFor(() => c.voiceBusy);
      });
      await tester.pumpAndSettle();
      expect(find.text('Cancelled — audio retained'), findsOneWidget);
      expect(File(note.audioPath).existsSync(), isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('voice-transcribe-${note.id}')));
        await waitFor(() => c.voiceBusy);
      });
      await tester.pumpAndSettle();
      expect(find.text('Draft — review before use'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('voice-discard-${note.id}')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Discarded — excluded from learning'), findsOneWidget);
      expect(note.acceptedBinding, isNull);
      expect(c.session.pile, isEmpty);
      await close(tester, c);
    },
  );

  testWidgets(
    'missing setup is actionable and core controls remain available',
    (tester) async {
      final c = controller();
      await addAudio(tester, c);
      final note = c.voiceNotes.single;
      await pump(
        tester,
        c,
        config: '${directory.path}/missing-transcriber.json',
      );
      await tap(tester, 'voice-notes');
      expect(find.textContaining('16 kHz mono PCM16 WAV'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('voice-transcribe-${note.id}')));
        await waitFor(() => c.voiceBusy);
      });
      await tester.pumpAndSettle();
      expect(note.status, VoiceNoteStatus.failed);
      expect(
        find.textContaining('Local transcription is optional.'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('voice-setup')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          Platform.isMacOS
              ? 'The macOS app needs a bundled, signed helper'
              : 'Choose the transcriber.json created by voice setup.',
        ),
        Platform.isMacOS ? findsWidgets : findsOneWidget,
      );
      await tap(tester, 'voice-close');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('choose-files')))
            .onPressed,
        isNotNull,
      );
      await close(tester, c);
    },
  );
}
