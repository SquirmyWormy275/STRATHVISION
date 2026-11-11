import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Pinned local transcription model (see docs/TRANSCRIPTION.md).
const whisperModelFile = 'ggml-base.en.bin';
const whisperModelBytes = 147964211;
const whisperModelSha256 =
    'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002';

enum TranscriptionFailure {
  missingEngine,
  missingModel,
  unsupportedAudio,
  cancelled,
  timedOut,
  failed,
}

class TranscriptionError implements Exception {
  const TranscriptionError(this.failure, this.message, [this.details = const {}]);
  final TranscriptionFailure failure;
  final String message;
  final Map<String, Object?> details;

  /// Worth one retry (DECISIONS.md: drop language binding after retry).
  bool get retryable =>
      failure == TranscriptionFailure.failed ||
      failure == TranscriptionFailure.timedOut;

  @override
  String toString() => 'TranscriptionError(${failure.name}): $message';
}

class TranscriptSegment {
  const TranscriptSegment(this.startMs, this.endMs, this.text);
  final int startMs, endMs;
  final String text;
  Map<String, Object?> toJson() =>
      {'start_ms': startMs, 'end_ms': endMs, 'text': text};
}

class Transcript {
  const Transcript({required this.segments, required this.engine});
  final List<TranscriptSegment> segments;

  /// Engine and model identity, recorded with any accepted text.
  final String engine;
  String get text => segments.map((s) => s.text).join(' ').trim();
}

/// Cooperative cancellation for one transcription.
class TranscriptionCancel {
  final _done = Completer<void>();
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

abstract class Transcriber {
  String get id;
  Future<Transcript> transcribe(String audioPath, {TranscriptionCancel? cancel});
}

/// Runs [exe] with [args]; returns (exit code, stdout, stderr). Must kill the
/// process and throw [TimeoutException] on timeout, or throw
/// [TranscriptionError] with [TranscriptionFailure.cancelled] on cancel.
typedef TranscribeRunner = Future<(int, String, String)> Function(
    String exe, List<String> args,
    {required Duration timeout, TranscriptionCancel? cancel});

Future<(int, String, String)> runBoundedProcess(String exe, List<String> args,
    {required Duration timeout, TranscriptionCancel? cancel}) async {
  if (cancel?.isCancelled ?? false) {
    throw const TranscriptionError(
        TranscriptionFailure.cancelled, 'Transcription was cancelled.');
  }
  final process = await Process.start(exe, args);
  unawaited(process.stdin.close());
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final outcome = await Future.any<Object>([
    process.exitCode,
    Future<Object>.delayed(timeout, () => const _Timeout()),
    if (cancel != null) cancel.whenCancelled.then<Object>((_) => const _Cancel()),
  ]);
  if (outcome is int) return (outcome, await out, await err);
  process.kill();
  await process.exitCode;
  if (outcome is _Cancel) {
    throw const TranscriptionError(
        TranscriptionFailure.cancelled, 'Transcription was cancelled.');
  }
  throw TimeoutException('Transcription timed out', timeout);
}

class _Timeout {
  const _Timeout();
}

class _Cancel {
  const _Cancel();
}

/// Local, offline transcription with whisper.cpp's `whisper-cli`. Audio is
/// converted to 16 kHz mono WAV with ffmpeg in a private temporary directory,
/// which is deleted afterwards. Nothing is uploaded.
class WhisperCppTranscriber implements Transcriber {
  WhisperCppTranscriber({
    required this.engine,
    required this.model,
    this.ffmpeg = 'ffmpeg',
    this.timeout = const Duration(minutes: 10),
    this.verifyModel = true,
    TranscribeRunner? run,
  }) : _run = run ?? runBoundedProcess;

  final String engine, model, ffmpeg;
  final Duration timeout;
  final bool verifyModel;
  final TranscribeRunner _run;
  bool _modelVerified = false;

  @override
  String get id => 'whisper.cpp:${p.basename(model)}';

  /// Finds an installed engine and the pinned model. Engine:
  /// `STRATHVISION_WHISPER_BIN`, else `whisper-cli` on PATH. Model:
  /// `STRATHVISION_WHISPER_MODEL`, else the first of [modelCandidates] that
  /// exists. Returns null when either is missing, so review stays usable.
  static Future<WhisperCppTranscriber?> detect({
    List<String> modelCandidates = const [],
    Map<String, String>? environment,
    TranscribeRunner? run,
  }) async {
    final env = environment ?? Platform.environment;
    final runner = run ?? runBoundedProcess;
    final model = [
      if (env['STRATHVISION_WHISPER_MODEL'] case final m? when m.isNotEmpty) m,
      ...modelCandidates,
    ].where((m) => File(m).existsSync()).firstOrNull;
    if (model == null) return null;
    for (final exe in [
      if (env['STRATHVISION_WHISPER_BIN'] case final b? when b.isNotEmpty) b,
      'whisper-cli',
    ]) {
      try {
        final (code, out, err) =
            await runner(exe, const ['--help'], timeout: const Duration(seconds: 10));
        if (code == 0 && '$out$err'.contains('whisper')) {
          return WhisperCppTranscriber(engine: exe, model: model, run: run);
        }
      } catch (_) {
        /* try the next candidate */
      }
    }
    return null;
  }

  Future<void> _checkModel() async {
    final file = File(model);
    if (!await file.exists()) {
      throw TranscriptionError(TranscriptionFailure.missingModel,
          'The transcription model is not installed.', {'model': model});
    }
    if (!verifyModel || _modelVerified) return;
    final size = await file.length();
    final digest = size == whisperModelBytes
        ? (await sha256.bind(file.openRead()).first).toString()
        : null;
    if (digest != whisperModelSha256) {
      throw TranscriptionError(TranscriptionFailure.missingModel,
          'The transcription model does not match the pinned version.',
          {'model': model, 'bytes': size});
    }
    _modelVerified = true;
  }

  @override
  Future<Transcript> transcribe(String audioPath,
      {TranscriptionCancel? cancel}) async {
    if (!await File(audioPath).exists()) {
      throw TranscriptionError(TranscriptionFailure.unsupportedAudio,
          'The voice note is unavailable.', {'path': audioPath});
    }
    await _checkModel();
    final work = await Directory.systemTemp.createTemp('sv-transcribe-');
    try {
      final wav = p.join(work.path, 'audio.wav');
      final (int, String, String) converted;
      try {
        converted = await _run(
            ffmpeg,
            ['-nostdin', '-v', 'error', '-y', '-i', audioPath, '-vn', '-ac', '1',
              '-ar', '16000', '-c:a', 'pcm_s16le', wav],
            timeout: timeout,
            cancel: cancel);
      } on ProcessException {
        throw const TranscriptionError(TranscriptionFailure.missingEngine,
            'ffmpeg is needed to read voice notes.');
      }
      if (converted.$1 != 0 || !await File(wav).exists()) {
        throw TranscriptionError(TranscriptionFailure.unsupportedAudio,
            'This audio could not be read.', {'stderr': _tail(converted.$3)});
      }
      final base = p.join(work.path, 'transcript');
      final (int, String, String) ran;
      try {
        ran = await _run(
            engine,
            ['-m', model, '-f', wav, '-l', 'en', '-oj', '-of', base, '-np'],
            timeout: timeout,
            cancel: cancel);
      } on ProcessException {
        throw const TranscriptionError(TranscriptionFailure.missingEngine,
            'The transcription engine is not installed.');
      }
      final out = File('$base.json');
      if (ran.$1 != 0 || !await out.exists()) {
        throw TranscriptionError(TranscriptionFailure.failed,
            'Transcription failed (exit ${ran.$1}).', {'stderr': _tail(ran.$3)});
      }
      return Transcript(
          segments: parseWhisperJson(await out.readAsString()), engine: id);
    } on TimeoutException {
      throw const TranscriptionError(
          TranscriptionFailure.timedOut, 'Transcription took too long.');
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {
        /* temporary only */
      }
    }
  }

  static String _tail(String s) =>
      s.length <= 400 ? s : s.substring(s.length - 400);
}

/// Parses whisper.cpp `-oj` output. Throws [TranscriptionError] when malformed.
List<TranscriptSegment> parseWhisperJson(String text) {
  try {
    final json = jsonDecode(text) as Map<String, Object?>;
    return [
      for (final s in (json['transcription'] as List).cast<Map<String, Object?>>())
        if ((s['text'] as String).trim().isNotEmpty)
          TranscriptSegment(
            ((s['offsets'] as Map)['from'] as num).toInt(),
            ((s['offsets'] as Map)['to'] as num).toInt(),
            (s['text'] as String).trim(),
          ),
    ];
  } catch (e) {
    throw TranscriptionError(TranscriptionFailure.failed,
        'The transcript could not be read.', {'error': '$e'});
  }
}
