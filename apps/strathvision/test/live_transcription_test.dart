// Opt-in real-audio check for issue #4. Never runs in CI: it needs whisper.cpp
// (`whisper-cli`) and the pinned ggml-base.en model on this computer.
//   LIVE_TRANSCRIBE=1 LIVE_AUDIO=/path/note.m4a LIVE_EXPECT="priority slope" \
//   STRATHVISION_WHISPER_MODEL=/path/ggml-base.en.bin LIVE_OUT=/path/out.json \
//     flutter test test/live_transcription_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/workbench/transcriber.dart';

final _env = Platform.environment;
final _live = _env['LIVE_TRANSCRIBE'] == '1';

String _words(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

void main() {
  test('live: real audio transcribes locally with the pinned model', () async {
    final t = await WhisperCppTranscriber.detect();
    expect(t, isNotNull, reason: 'whisper-cli or model not found');
    final audio = _env['LIVE_AUDIO']!;
    final watch = Stopwatch()..start();
    final transcript = await t!.transcribe(audio);
    final seconds = watch.elapsedMilliseconds / 1000;
    final expected = _env['LIVE_EXPECT'];
    final out = _env['LIVE_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'engine': transcript.engine,
        'audio_file': audio.split('/').last,
        'seconds': seconds,
        'text': transcript.text,
        'expected': expected,
        'segments': [for (final s in transcript.segments) s.toJson()],
      }));
    }
    expect(transcript.text, isNotEmpty);
    if (expected != null) expect(_words(transcript.text), contains(_words(expected)));
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 15)));
}
