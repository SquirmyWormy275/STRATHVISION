import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/workbench/transcriber.dart';

void main() {
  late Directory dir;
  late String model, audio;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv-tx-');
    model = '${dir.path}/ggml-base.en.bin';
    File(model).writeAsStringSync('model');
    audio = '${dir.path}/coach.m4a';
    File(audio).writeAsStringSync('audio');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const json = {
    'transcription': [
      {'offsets': {'from': 0, 'to': 1800}, 'text': ' Priority: slope.'},
      {'offsets': {'from': 1800, 'to': 1900}, 'text': '  '},
      {'offsets': {'from': 1900, 'to': 4200}, 'text': ' Keep the hips quiet.'},
    ],
  };

  /// Simulates ffmpeg and whisper-cli by writing the files they would write.
  TranscribeRunner fake({int ffmpegExit = 0, int whisperExit = 0, List<String>? log}) =>
      (exe, args, {required timeout, cancel}) async {
        log?.add(exe);
        if (exe == 'ffmpeg') {
          if (ffmpegExit == 0) File(args.last).writeAsStringSync('wav');
          return (ffmpegExit, '', ffmpegExit == 0 ? '' : 'Invalid data found');
        }
        if (whisperExit == 0) {
          final base = args[args.indexOf('-of') + 1];
          File('$base.json').writeAsStringSync(jsonEncode(json));
        }
        return (whisperExit, '', whisperExit == 0 ? '' : 'error');
      };

  WhisperCppTranscriber make(TranscribeRunner run, {bool verify = false}) =>
      WhisperCppTranscriber(
          engine: 'whisper-cli', model: model, run: run, verifyModel: verify);

  Matcher fails(TranscriptionFailure f) =>
      throwsA(isA<TranscriptionError>().having((e) => e.failure, 'failure', f));

  test('converts locally, parses timed segments and removes temporary files',
      () async {
    final log = <String>[];
    final before = Directory.systemTemp.listSync().length;
    final t = await make(fake(log: log)).transcribe(audio);
    expect(log, ['ffmpeg', 'whisper-cli']);
    expect(t.text, 'Priority: slope. Keep the hips quiet.');
    expect(t.segments.map((s) => (s.startMs, s.endMs)), [(0, 1800), (1900, 4200)]);
    expect(t.engine, 'whisper.cpp:ggml-base.en.bin');
    expect(Directory.systemTemp.listSync().length, before);
    expect(File(audio).readAsStringSync(), 'audio', reason: 'original untouched');
  });

  test('missing or unpinned model is reported before running anything', () async {
    final log = <String>[];
    File(model).deleteSync();
    await expectLater(make(fake(log: log)).transcribe(audio),
        fails(TranscriptionFailure.missingModel));
    File(model).writeAsStringSync('not the pinned model');
    await expectLater(make(fake(log: log), verify: true).transcribe(audio),
        fails(TranscriptionFailure.missingModel));
    expect(log, isEmpty);
  });

  test('unreadable audio, missing tools and engine failure are distinct', () async {
    await expectLater(make(fake(ffmpegExit: 1)).transcribe(audio),
        fails(TranscriptionFailure.unsupportedAudio));
    await expectLater(make(fake()).transcribe('${dir.path}/gone.wav'),
        fails(TranscriptionFailure.unsupportedAudio));
    await expectLater(
        make((exe, args, {required timeout, cancel}) async =>
                throw ProcessException(exe, args, 'not found'))
            .transcribe(audio),
        fails(TranscriptionFailure.missingEngine));
    final failed = make(fake(whisperExit: 3)).transcribe(audio);
    await expectLater(failed, fails(TranscriptionFailure.failed));
    await expectLater(failed,
        throwsA(isA<TranscriptionError>().having((e) => e.retryable, 'retryable', isTrue)));
  });

  test('timeout from the runner becomes timedOut', () async {
    await expectLater(
        make((exe, args, {required timeout, cancel}) async =>
                throw TimeoutException('slow', timeout))
            .transcribe(audio),
        fails(TranscriptionFailure.timedOut));
  });

  test('malformed engine output is a failure, not a crash', () {
    expect(() => parseWhisperJson('{"nope": 1}'),
        throwsA(isA<TranscriptionError>()));
  });

  group('bounded process (real subprocess)', () {
    test('cancel kills a running process promptly', () async {
      final cancel = TranscriptionCancel();
      final watch = Stopwatch()..start();
      final run = runBoundedProcess('sleep', ['30'],
          timeout: const Duration(minutes: 1), cancel: cancel);
      Timer(const Duration(milliseconds: 200), cancel.cancel);
      await expectLater(run, fails(TranscriptionFailure.cancelled));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('timeout kills a running process', () async {
      await expectLater(
          runBoundedProcess('sleep', ['30'],
              timeout: const Duration(milliseconds: 300)),
          throwsA(isA<TimeoutException>()));
    });

    test('a finished process returns its output', () async {
      final (code, out, _) = await runBoundedProcess('echo', ['hi'],
          timeout: const Duration(seconds: 10));
      expect((code, out.trim()), (0, 'hi'));
    });
  }, skip: Platform.isWindows ? 'uses POSIX sleep/echo' : null);

  test('detect needs both an engine and a model', () async {
    TranscribeRunner help(int code) =>
        (exe, args, {required timeout, cancel}) async =>
            (code, 'usage: whisper-cli [options] file0 file1 ...', '');
    expect(
        await WhisperCppTranscriber.detect(
            modelCandidates: ['${dir.path}/absent.bin'], environment: const {}, run: help(0)),
        isNull);
    final found = await WhisperCppTranscriber.detect(
        modelCandidates: [model], environment: const {}, run: help(0));
    expect(found?.model, model);
    expect(
        await WhisperCppTranscriber.detect(
            modelCandidates: [model],
            environment: const {},
            run: (exe, args, {required timeout, cancel}) async =>
                throw ProcessException(exe, args)),
        isNull);
    final custom = await WhisperCppTranscriber.detect(
        environment: {'STRATHVISION_WHISPER_BIN': '/opt/w/whisper-cli', 'STRATHVISION_WHISPER_MODEL': model},
        run: help(0));
    expect((custom?.engine, custom?.model), ('/opt/w/whisper-cli', model));
  });
}
