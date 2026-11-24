import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

abstract class VoiceTranscriber {
  Future<VoiceTranscript> transcribe(
    String audioPath, {
    required TranscriptionCancellation cancellation,
  });
}

/// Unreviewed speech recognition, never authorization to create coaching marks.
class VoiceTranscript {
  const VoiceTranscript({
    required this.text,
    required this.engine,
    required this.model,
    this.language,
    this.metadata = const {},
  });
  final String text, engine, model;
  final String? language;
  final Map<String, Object?> metadata;
}

class TranscriptionException implements Exception {
  const TranscriptionException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

class TranscriptionCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

typedef TranscriptionProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
);

Future<Process> _startProcess(
  String executable,
  List<String> args,
  String cwd,
) => Process.start(
  executable,
  args,
  workingDirectory: cwd,
  runInShell: false,
  includeParentEnvironment: false,
  environment: {
    // Windows needs this to locate system DLLs. No user/provider secrets
    // or whisper environment overrides are passed to the local runtime.
    if (Platform.isWindows && Platform.environment['SystemRoot'] != null)
      'SystemRoot': Platform.environment['SystemRoot']!,
  },
);

/// Optional desktop CPU transcription. Never downloads a model or sends audio.
///
/// The caller chooses an installed executable/model; the model and runtime
/// version must match the pins. Only PCM16, mono, 16 kHz RIFF/WAVE is accepted.
/// CLI/JSON protocol: ggml-org/whisper.cpp v1.9.6, examples/cli/cli.cpp.
class WhisperTranscriber implements VoiceTranscriber {
  WhisperTranscriber({
    required this.executablePath,
    required this.modelPath,
    this.executableSha256,
    this.timeout = const Duration(minutes: 15),
  }) : _modelHash = modelSha256,
       _modelBytes = modelBytes,
       processStarter = _startProcess,
       tempParent = Directory.systemTemp;

  /// Replaces process transport and model bytes for deterministic adapter tests.
  /// Production callers must use the constructor with the published model pin.
  WhisperTranscriber.testing({
    required this.executablePath,
    required this.modelPath,
    required String expectedModelSha256,
    required int expectedModelBytes,
    required this.processStarter,
    required this.tempParent,
    this.executableSha256,
    this.timeout = const Duration(minutes: 15),
  }) : _modelHash = expectedModelSha256,
       _modelBytes = expectedModelBytes;

  static const engineVersion = '1.9.6';
  static const sourceCommit = '96ec4d9823e9d0211944172da35f9f29134af990';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  static const modelBytes = 147951465;
  static const maxAudioBytes = 100 * 1024 * 1024;
  static const maxAudioSeconds = 10 * 60;
  static const maxOutputBytes = 1024 * 1024;
  static const maxProcessOutputBytes = 256 * 1024;
  final String executablePath, modelPath;
  final String? executableSha256;
  final Duration timeout;
  final String _modelHash;
  final int _modelBytes;
  final TranscriptionProcessStarter processStarter;
  final Directory tempParent;

  @override
  Future<VoiceTranscript> transcribe(
    String audioPath, {
    required TranscriptionCancellation cancellation,
  }) async {
    final op = _Operation(cancellation, timeout);
    Directory? temporary;
    try {
      op.check();
      if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
        throw const TranscriptionException(
          'unsupported_platform',
          'Voice transcription is available on desktop.',
        );
      }
      await _requireFile(
        executablePath,
        'missing_engine',
        'Choose the installed whisper.cpp transcription program.',
      );
      await _requireFile(
        modelPath,
        'missing_model',
        'Choose the downloaded multilingual base transcription model.',
      );
      await _requireFile(
        audioPath,
        'missing_audio',
        'The voice note is missing or unreadable. Choose the file again.',
      );
      if (!p.isAbsolute(executablePath) || !p.isAbsolute(modelPath)) {
        throw const TranscriptionException(
          'invalid_configuration',
          'Choose absolute paths for the transcription program and model.',
        );
      }
      if (p.extension(audioPath).toLowerCase() != '.wav') {
        throw _unsupportedAudio;
      }
      if (await File(audioPath).length() > maxAudioBytes) throw _audioTooLarge;
      if (await File(modelPath).length() != _modelBytes ||
          await _hashFile(File(modelPath), op, limit: _modelBytes) !=
              _modelHash) {
        throw const TranscriptionException(
          'invalid_model',
          'The model does not match the verified multilingual base model. Install it again.',
        );
      }
      final executableHash = await _hashFile(File(executablePath), op);
      if (executableSha256 != null && executableHash != executableSha256) {
        throw const TranscriptionException(
          'invalid_engine',
          'The transcription program changed. Install or configure it again.',
        );
      }
      temporary = await tempParent.createTemp('strathvision-transcription-');
      final audio = File(p.join(temporary.path, 'input.wav'));
      // Snapshot and hash the actual bytes passed to the engine. A path changing
      // while awaiting review cannot silently redefine this transcript's source.
      final audioHash = await _copyAudio(File(audioPath), audio, op);
      final durationMs = await _validateWave(audio, op);
      final version = await _run(['--version'], temporary, op);
      if (version.trim() != 'whisper.cpp version: $engineVersion') {
        throw const TranscriptionException(
          'invalid_engine',
          'Use the verified whisper.cpp 1.9.6 transcription program.',
        );
      }
      final outputStem = p.join(temporary.path, 'transcript');
      final output = File('$outputStem.json');
      await _run(
        [
          '--model',
          modelPath,
          '--file',
          audio.path,
          '--language',
          'auto',
          '--no-gpu',
          '--threads',
          '2',
          '--output-json',
          '--output-file',
          outputStem,
        ],
        temporary,
        op,
        output: output,
      );
      op.check();
      if (!await output.exists()) throw _invalidOutput;
      final data = await _readBounded(output, op, maxOutputBytes);
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(data));
      } on FormatException {
        throw _invalidOutput;
      }
      if (decoded is! Map ||
          decoded['transcription'] is! List ||
          decoded['model'] is! Map ||
          decoded['result'] is! Map) {
        throw _invalidOutput;
      }
      final model = decoded['model'] as Map;
      final language = (decoded['result'] as Map)['language'];
      if (model['type'] != 'base' ||
          model['multilingual'] != true ||
          language is! String ||
          !RegExp(r'^[a-z]{2,3}$').hasMatch(language)) {
        throw _invalidOutput;
      }
      final segments = decoded['transcription'] as List;
      if (segments.any((s) => s is! Map || s['text'] is! String)) {
        throw _invalidOutput;
      }
      final text = segments
          .map((s) => (s['text'] as String).trim())
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (text.isEmpty) {
        throw const TranscriptionException(
          'no_speech',
          'No speech was transcribed. Review the recording and try again.',
        );
      }
      op.check();
      return VoiceTranscript(
        text: text,
        engine: 'whisper.cpp/$engineVersion',
        model: 'base',
        language: language,
        metadata: Map.unmodifiable({
          'source_commit': sourceCommit,
          'model_sha256': _modelHash,
          'executable_sha256': executableHash,
          'audio_sha256': audioHash,
          'audio_duration_ms': durationMs,
          'segment_count': segments.length,
          'reviewed': false,
        }),
      );
    } on TranscriptionException {
      rethrow;
    } on FileSystemException {
      throw const TranscriptionException(
        'file_error',
        'A local transcription file could not be read or written. Check the files and try again.',
      );
    } on ProcessException {
      throw const TranscriptionException(
        'missing_engine',
        'The transcription program could not start. Check its installation and try again.',
      );
    } finally {
      op.dispose();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<String> _run(
    List<String> args,
    Directory cwd,
    _Operation op, {
    File? output,
  }) async {
    op.check();
    final process = await processStarter(executablePath, args, cwd.path);
    var exited = false;
    void kill() {
      if (!exited) process.kill(ProcessSignal.sigkill);
    }

    op.onStop = kill;
    final stdout = BytesBuilder(copy: false);
    var count = 0;
    final doneOut = Completer<void>(), doneErr = Completer<void>();
    void receive(List<int> bytes, {required bool keep}) {
      count += bytes.length;
      if (count > maxProcessOutputBytes) {
        op.stop(
          const TranscriptionException(
            'output_limit',
            'The transcription program produced too much output. Try a shorter recording.',
          ),
        );
      } else if (keep) {
        stdout.add(bytes);
      }
    }

    void streamError(Object error, StackTrace stack) => op.stop(
      const TranscriptionException(
        'process_failed',
        'The transcription program stopped unexpectedly. Try again.',
      ),
    );
    final outSub = process.stdout.listen(
      (b) => receive(b, keep: true),
      onDone: doneOut.complete,
      onError: streamError,
    );
    final errSub = process.stderr.listen(
      (b) => receive(b, keep: false),
      onDone: doneErr.complete,
      onError: streamError,
    );
    var polling = false;
    final poll = output == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) async {
            if (polling) return;
            polling = true;
            try {
              if (await output.exists() &&
                  await output.length() > maxOutputBytes) {
                op.stop(_outputTooLarge);
              }
            } on FileSystemException {
              // The writer can be between creation and opening. Final read verifies.
            } finally {
              polling = false;
            }
          });
    final exit = process.exitCode.then((code) {
      exited = true;
      return code;
    });
    try {
      op.check();
      final code = await op.wait(exit);
      await op.wait(Future.wait([doneOut.future, doneErr.future]));
      op.check();
      if (code != 0) {
        throw const TranscriptionException(
          'process_failed',
          'The transcription program could not finish. Check the recording and try again.',
        );
      }
      return utf8.decode(stdout.takeBytes(), allowMalformed: true);
    } finally {
      poll?.cancel();
      kill();
      // A failed or cancelled child must exit before its private files disappear.
      await exit.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      await outSub.cancel();
      await errSub.cancel();
      op.onStop = null;
    }
  }
}

const _unsupportedAudio = TranscriptionException(
  'unsupported_audio',
  'Use a 16-bit PCM WAV file recorded at 16 kHz in mono. Convert this recording locally, then try again.',
);
const _audioTooLarge = TranscriptionException(
  'audio_limit',
  'Use a voice note no longer than 10 minutes and no larger than 100 MiB.',
);
const _invalidOutput = TranscriptionException(
  'invalid_output',
  'The transcription program returned an unreadable result. Try again; no feedback was applied.',
);
const _outputTooLarge = TranscriptionException(
  'output_limit',
  'The transcript was too large to read. Try a shorter recording.',
);

Future<void> _requireFile(String path, String code, String message) async {
  if (path.isEmpty ||
      (await File(path).stat()).type != FileSystemEntityType.file) {
    throw TranscriptionException(code, message);
  }
}

Future<String> _hashFile(File file, _Operation op, {int? limit}) async {
  var count = 0;
  final stream = file.openRead().map((bytes) {
    op.check();
    count += bytes.length;
    if (limit != null && count > limit) {
      throw const TranscriptionException(
        'invalid_model',
        'The model changed. Install it again.',
      );
    }
    return bytes;
  });
  return (await sha256.bind(stream).first).toString();
}

Future<String> _copyAudio(File source, File target, _Operation op) async {
  final sink = target.openWrite();
  var count = 0;
  final digest = sha256
      .bind(
        source.openRead().map((bytes) {
          op.check();
          count += bytes.length;
          if (count > WhisperTranscriber.maxAudioBytes) throw _audioTooLarge;
          sink.add(bytes);
          return bytes;
        }),
      )
      .first;
  try {
    final hash = await digest;
    await sink.flush();
    return hash.toString();
  } finally {
    await sink.close();
  }
}

Future<Uint8List> _readBounded(File file, _Operation op, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    op.check();
    if (bytes.length + chunk.length > limit) throw _outputTooLarge;
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Future<int> _validateWave(File file, _Operation op) async {
  final input = await file.open();
  try {
    final size = await input.length();
    final header = await input.read(12);
    if (header.length != 12 ||
        ascii.decode(header.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(header.sublist(8, 12), allowInvalid: true) != 'WAVE' ||
        ByteData.sublistView(header).getUint32(4, Endian.little) + 8 != size) {
      throw _unsupportedAudio;
    }
    var position = 12, chunks = 0;
    int? dataBytes;
    var validFormat = false;
    while (position < size) {
      op.check();
      if (++chunks > 1024 || position + 8 > size) throw _unsupportedAudio;
      await input.setPosition(position);
      final chunk = await input.read(8);
      if (chunk.length != 8) throw _unsupportedAudio;
      final name = ascii.decode(chunk.sublist(0, 4), allowInvalid: true);
      final length = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final end = position + 8 + length;
      if (end + (length % 2) > size) throw _unsupportedAudio;
      if (name == 'fmt ') {
        if (validFormat || length < 16) throw _unsupportedAudio;
        final format = await input.read(16);
        if (format.length != 16) throw _unsupportedAudio;
        final f = ByteData.sublistView(format);
        if (f.getUint16(0, Endian.little) != 1 ||
            f.getUint16(2, Endian.little) != 1 ||
            f.getUint32(4, Endian.little) != 16000 ||
            f.getUint32(8, Endian.little) != 32000 ||
            f.getUint16(12, Endian.little) != 2 ||
            f.getUint16(14, Endian.little) != 16) {
          throw _unsupportedAudio;
        }
        validFormat = true;
      } else if (name == 'data') {
        if (dataBytes != null || length == 0 || length.isOdd) {
          throw _unsupportedAudio;
        }
        dataBytes = length;
      }
      position = end + (length % 2);
    }
    if (!validFormat || dataBytes == null) throw _unsupportedAudio;
    if (dataBytes > 32000 * WhisperTranscriber.maxAudioSeconds) {
      throw _audioTooLarge;
    }
    return (dataBytes * 1000 / 32000).round();
  } finally {
    await input.close();
  }
}

class _Operation {
  _Operation(this.cancellation, Duration timeout) {
    cancellation._listeners.add(_cancel);
    _timer = Timer(
      timeout,
      () => stop(
        const TranscriptionException(
          'timeout',
          'Transcription took too long. Try a shorter voice note.',
        ),
      ),
    );
    if (cancellation.isCancelled) _cancel();
  }
  final TranscriptionCancellation cancellation;
  final _stopped = Completer<void>();
  late final Timer _timer;
  TranscriptionException? error;
  void Function()? onStop;
  void _cancel() => stop(
    const TranscriptionException('cancelled', 'Transcription cancelled.'),
  );
  void stop(TranscriptionException reason) {
    if (error != null) return;
    error = reason;
    _stopped.complete();
    onStop?.call();
  }

  void check() {
    if (error != null) throw error!;
  }

  Future<T> wait<T>(Future<T> work) =>
      Future.any([work, _stopped.future.then<T>((_) => throw error!)]);
  void dispose() {
    _timer.cancel();
    cancellation._listeners.remove(_cancel);
  }
}
