// Opt-in native UI smoke with real recorded speech and the installed local
// transcriber. The coach profile is a synthetic fixture; no video measurements,
// feedback acceptance or coaching-accuracy claim is made by this test.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/workbench/carne_controller.dart';

import '../test/support/carne_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const config = String.fromEnvironment('TRANSCRIBER_CONFIG');
  const audio = String.fromEnvironment('TRANSCRIPTION_AUDIO');
  const out = String.fromEnvironment('OUT');

  testWidgets(
    'real local speech is editable review text and never unbound feedback',
    (tester) async {
      final fixture = await tester.runAsync(CarneFixture.load);
      final storage = await tester.runAsync(
        () => Directory.systemTemp.createTemp('sv_native_voice_'),
      );
      final c = fixture!.controller(
        voiceLibrary: VoiceNoteLibrary(directory: () async => storage!),
      );
      final shot = GlobalKey();
      try {
        await tester.runAsync(() => c.configureTranscriber(config));
        await tester.runAsync(() => c.drop([audio]));
        expect(c.voiceNotes, hasLength(1));
        final note = c.voiceNotes.single;
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              home: CarneScreen(
                controller: c,
                title: 'Local voice review check',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('voice-notes')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(Key('voice-transcribe-${note.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('voice-transcribe-${note.id}')));
        // Pump the visible progress state while the real subprocess runs.
        for (var tries = 0; tries < 1200 && c.voiceBusy; tries++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(c.voiceBusy, isFalse, reason: 'Local transcription timed out');
        expect(note.status, VoiceNoteStatus.draft, reason: note.error);
        final recognized = note.draftText!;
        expect(
          recognized.toLowerCase(),
          contains('ask not what your country can do for you'),
        );
        expect(note.transcript!.engine, 'whisper.cpp/1.9.6');
        expect(c.session.pile, isEmpty);
        expect(c.session.edits, isEmpty);
        expect(note.acceptedBinding, isNull);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('voice-review-${note.id}')));
        await tester.pumpAndSettle();
        final transcript = find.byKey(const Key('voice-draft-text'));
        expect(
          tester.widget<TextField>(transcript).controller!.text,
          recognized,
        );
        expect(tester.widget<TextField>(transcript).readOnly, isFalse);
        expect(
          find.text(
            'Add and analyze a clip before linking feedback to a swing.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('voice-accept')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);

        final boundary =
            shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        );
        final png = await image!.toByteData(format: ui.ImageByteFormat.png);
        await tester.runAsync(() async {
          final screenshot = File(out);
          await screenshot.parent.create(recursive: true);
          await screenshot.writeAsBytes(png!.buffer.asUint8List());
        });
        image.dispose();

        final edited = '$recognized\nReviewed in the local UI smoke test.';
        await tester.enterText(transcript, edited);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('voice-review-close')));
        for (
          var tries = 0;
          tries < 100 &&
              find.byKey(const Key('voice-accept')).evaluate().isNotEmpty;
          tries++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(note.draftText, edited);
        expect(note.status, VoiceNoteStatus.draft);
        expect(note.acceptedBinding, isNull);
        expect(c.session.pile, isEmpty);
        expect(c.session.edits, isEmpty);
        await tester.tap(find.byKey(Key('voice-review-${note.id}')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(transcript).controller!.text, edited);
        final saved = await tester.runAsync(
          () => File('${storage!.path}/${note.id}.json').readAsString(),
        );
        expect((jsonDecode(saved!) as Map)['draft_text'], edited);
        await tester.runAsync(
          () => File('$out.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({'format': 'local-voice-review-ui/1', 'status': 'passed', 'recorded_at': DateTime.now().toUtc().toIso8601String(), 'platform': Platform.operatingSystem, 'engine': note.transcript!.engine, 'model': note.transcript!.model, 'transcript': recognized, 'audio_sha256': note.audioSha256, 'screenshot': out, 'draft_edits_persisted': true, 'feedback_accepted': false, 'video_inputs': 0, 'mixture_edits': c.session.edits.length, 'profile_fixture': 'Synthetic coach profile, no measured footage.', 'scope': 'Real speech and native Linux review UI; not coaching accuracy.'})}\n',
          ),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        c.dispose();
        await tester.runAsync(() => storage!.delete(recursive: true));
      }
    },
    skip: !Platform.isLinux || config.isEmpty || audio.isEmpty || out.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
