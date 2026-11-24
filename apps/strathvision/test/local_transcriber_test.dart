import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:strathvision/workbench/local_transcriber.dart';

// These are adapter/protocol tests with fake subprocesses, not ASR accuracy
// evidence. Genuine recorded audio is checked separately by transcription_check.
void main() {
  late Directory root;
  late File engine, model, audio;
  late List<List<String>> calls;
  late List<String> workingDirectories;
  final modelData = utf8.encode('small fixture, not speech model weights');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sv-transcriber-test-');
    engine = await File(p.join(root.path, 'local engine'))
        .writeAsString('engine fixture');
    model = await File(p.join(root.path, 'model.bin')).writeAsBytes(modelData);
    audio = await File(p.join(root.path, 'voice note.wav'))
        .writeAsBytes(_wave());
    calls = [];
    workingDirectories = [];
  });
  tearDown(() async => root.delete(recursive: true));

  Map<String, Object?> result({String text = ' Keep the swing steady.'}) => {
    'model': {'type': 'base', 'multilingual': true},
    'result': {'language': 'en'},
    'transcription': [
      {
        'text': text,
        'offsets': {'from': 0, 'to': 1000},
      },
    ],
  };

  Future<Process> success(List<String> args, String cwd) async {
    final output = args[args.indexOf('--output-file') + 1];
    await File('$output.json').writeAsString(jsonEncode(result()));
    return _FakeProcess.finished();
  }

  WhisperTranscriber transcriber({
    Future<Process> Function(List<String>, String)? run,
    String version = 'whisper.cpp version: 1.9.6\n',
    Duration timeout = const Duration(seconds: 5),
    String? executablePath,
    String? modelPath,
    String? executableSha256,
  }) => WhisperTranscriber.testing(
    executablePath: executablePath ?? engine.path,
    modelPath: modelPath ?? model.path,
    executableSha256: executableSha256,
    expectedModelSha256: sha256.convert(modelData).toString(),
    expectedModelBytes: modelData.length,
    tempParent: root,
    timeout: timeout,
    processStarter: (path, args, cwd) async {
      expect(path, engine.path);
      calls.add(args);
      workingDirectories.add(cwd);
      if (args.singleOrNull == '--version') {
        return _FakeProcess.finished(stdout: utf8.encode(version));
      }
      return (run ?? success)(args, cwd);
    },
  );

  Future<VoiceTranscript> run(
    WhisperTranscriber adapter, {
    TranscriptionCancellation? cancellation,
    String? path,
  }) => adapter.transcribe(
    path ?? audio.path,
    cancellation: cancellation ?? TranscriptionCancellation(),
  );

  TypeMatcher<TranscriptionException> failure(String code) =>
      isA<TranscriptionException>().having((e) => e.code, 'code', code);

  Future<void> expectCleaned() async {
    for (final directory in workingDirectories) {
      expect(await Directory(directory).exists(), isFalse);
    }
    expect(await audio.exists(), isTrue);
  }

  test('verified local CPU invocation returns unreviewed transcript and byte provenance', () async {
    final original = await audio.readAsBytes();
    final value = await run(
      transcriber(
        run: (args, cwd) async {
          expect(
            args,
            containsAll(['--no-gpu', '--language', 'auto', '--threads', '2']),
          );
          expect(args, isNot(contains('--translate')));
          final snapshot = File(args[args.indexOf('--file') + 1]);
          expect(snapshot.path, isNot(audio.path));
          expect(await snapshot.readAsBytes(), original);
          return success(args, cwd);
        },
      ),
    );
    expect(value.text, 'Keep the swing steady.');
    expect(value.engine, 'whisper.cpp/1.9.6');
    expect(value.model, 'base');
    expect(value.language, 'en');
    expect(value.metadata['audio_sha256'], sha256.convert(original).toString());
    expect(value.metadata['audio_duration_ms'], 1000);
    expect(value.metadata['reviewed'], isFalse);
    expect(calls.length, 2);
    await expectCleaned();
  });

  test('missing engine/model/audio fail without starting a process', () async {
    await expectLater(
      run(transcriber(executablePath: p.join(root.path, 'missing'))),
      throwsA(failure('missing_engine')),
    );
    await expectLater(
      run(transcriber(modelPath: p.join(root.path, 'missing'))),
      throwsA(failure('missing_model')),
    );
    await expectLater(
      run(transcriber(), path: p.join(root.path, 'missing.wav')),
      throwsA(failure('missing_audio')),
    );
    expect(calls, isEmpty);
  });

  test('modified model and configured executable hashes fail closed', () async {
    await model.writeAsBytes(List.filled(modelData.length, 0));
    await expectLater(run(transcriber()), throwsA(failure('invalid_model')));
    await model.writeAsBytes(modelData);
    await expectLater(
      run(transcriber(executableSha256: '0' * 64)),
      throwsA(failure('invalid_engine')),
    );
    expect(calls, isEmpty);
  });

  test(
    'unsupported format is actionable and validates bytes, not extension alone',
    () async {
      final mp3 = await File(p.join(root.path, 'voice.mp3'))
          .writeAsBytes([1, 2]);
      await expectLater(
        run(transcriber(), path: mp3.path),
        throwsA(
          failure('unsupported_audio').having(
            (e) => e.message,
            'recovery',
            contains('Convert'),
          ),
        ),
      );
      for (final bytes in [
        Uint8List.fromList([1, 2, 3]),
        _wave(sampleRate: 48000),
        _wave(channels: 2),
        _wave(bits: 32),
        _wave(format: 3),
        _wave()..[4] = 0,
        _wave().sublist(0, 43),
      ]) {
        await audio.writeAsBytes(bytes);
        await expectLater(
          run(transcriber()),
          throwsA(failure('unsupported_audio')),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'duration and file byte limits are enforced before launching ASR',
    () async {
      await audio.writeAsBytes(_wave(seconds: 601));
      await expectLater(run(transcriber()), throwsA(failure('audio_limit')));
      final file = await audio.open(mode: FileMode.write);
      await file.truncate(WhisperTranscriber.maxAudioBytes + 1);
      await file.close();
      await expectLater(run(transcriber()), throwsA(failure('audio_limit')));
      expect(calls, isEmpty);
    },
  );

  test('runtime version mismatch stops before inference and cleans temporary files', () async {
    await expectLater(
      run(transcriber(version: 'whisper.cpp version: 1.8.0')),
      throwsA(failure('invalid_engine')),
    );
    expect(calls.length, 1);
    await expectCleaned();
  });

  test(
    'malformed, absent, wrong-model and empty results never become feedback',
    () async {
      for (final contents in <String?>[
        null,
        '{broken',
        '[]',
        jsonEncode({'transcription': []}),
        jsonEncode({
          ...result(),
          'model': {'type': 'tiny', 'multilingual': true},
        }),
        jsonEncode({
          ...result(),
          'transcription': [
            {'text': 123},
          ],
        }),
      ]) {
        await expectLater(
          run(
            transcriber(
              run: (args, cwd) async {
                if (contents != null) {
                  await File('${args[args.indexOf('--output-file') + 1]}.json')
                      .writeAsString(contents);
                }
                return _FakeProcess.finished();
              },
            ),
          ),
          throwsA(failure('invalid_output')),
        );
        await expectCleaned();
      }
      await expectLater(
        run(
          transcriber(
            run: (args, cwd) async {
              await File('${args[args.indexOf('--output-file') + 1]}.json')
                  .writeAsString(jsonEncode(result(text: '   ')));
              return _FakeProcess.finished();
            },
          ),
        ),
        throwsA(failure('no_speech')),
      );
    },
  );

  test('process failure can be retried using the same adapter', () async {
    var first = true;
    final adapter = transcriber(
      run: (args, cwd) async {
        if (first) {
          first = false;
          return _FakeProcess.finished(code: 1);
        }
        return success(args, cwd);
      },
    );
    await expectLater(run(adapter), throwsA(failure('process_failed')));
    expect((await run(adapter)).text, isNotEmpty);
    await expectCleaned();
  });

  test('cancel before launch does no work', () async {
    final cancellation = TranscriptionCancellation()..cancel();
    await expectLater(
      run(transcriber(), cancellation: cancellation),
      throwsA(failure('cancelled')),
    );
    expect(calls, isEmpty);
  });

  test('cancel during inference kills child, cleans private files and permits retry', () async {
    final started = Completer<void>();
    final child = _FakeProcess();
    var first = true;
    final adapter = transcriber(
      run: (args, cwd) async {
        if (!first) return success(args, cwd);
        first = false;
        started.complete();
        return child;
      },
    );
    final cancellation = TranscriptionCancellation();
    final pending = run(adapter, cancellation: cancellation);
    final assertion = expectLater(pending, throwsA(failure('cancelled')));
    await started.future;
    cancellation.cancel();
    await assertion;
    expect(child.killed, isTrue);
    await expectCleaned();
    expect((await run(adapter)).text, isNotEmpty);
  });

  test('timeout kills a stalled child and leaves no temporary audio', () async {
    final child = _FakeProcess();
    await expectLater(
      run(
        transcriber(
          timeout: const Duration(milliseconds: 100),
          run: (_, _) async => child,
        ),
      ),
      throwsA(failure('timeout')),
    );
    expect(child.killed, isTrue);
    await expectCleaned();
  });

  test('stdout/stderr output flood is bounded and kills the child', () async {
    final child = _FakeProcess();
    await expectLater(
      run(
        transcriber(
          run: (_, _) async {
            child.err.add(
              List.filled(WhisperTranscriber.maxProcessOutputBytes + 1, 65),
            );
            return child;
          },
        ),
      ),
      throwsA(failure('output_limit')),
    );
    expect(child.killed, isTrue);
    await expectCleaned();
  });

  test('oversized JSON is rejected, including before a child exits', () async {
    final child = _FakeProcess();
    await expectLater(
      run(
        transcriber(
          run: (args, cwd) async {
            await File('${args[args.indexOf('--output-file') + 1]}.json')
                .writeAsBytes(
                  List.filled(WhisperTranscriber.maxOutputBytes + 1, 32),
                );
            return child;
          },
        ),
      ),
      throwsA(failure('output_limit')),
    );
    expect(child.killed, isTrue);
    await expectCleaned();
  });
}

Uint8List _wave({
  int seconds = 1,
  int sampleRate = 16000,
  int channels = 1,
  int bits = 16,
  int format = 1,
}) {
  final block = channels * bits ~/ 8;
  final dataSize = seconds * sampleRate * block;
  final bytes = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  header.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, format, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * block, Endian.little);
  header.setUint16(32, block, Endian.little);
  header.setUint16(34, bits, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  header.setUint32(40, dataSize, Endian.little);
  return bytes;
}

class _FakeProcess implements Process {
  _FakeProcess();
  factory _FakeProcess.finished({int code = 0, List<int> stdout = const []}) {
    final process = _FakeProcess();
    process.out.add(stdout);
    process.finish(code);
    return process;
  }
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;
  void finish(int code) {
    if (_exit.isCompleted) return;
    out.close();
    err.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 12345;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  IOSink get stdin => throw UnsupportedError('Adapter must not use stdin');
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-9);
    return true;
  }
}
