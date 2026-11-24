// Opt-in native acceptance through the same adapter used by the desktop app.
// Run from apps/strathvision after flutter pub get; see docs/VOICE_NOTES.md.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:strathvision/workbench/local_transcriber.dart';

String requiredEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw StateError('Set $name.');
  return value;
}

String normalized(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Future<String> fileHash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<void> main() async {
  final config = jsonDecode(
    await File(requiredEnv('STRATHVISION_TRANSCRIBER_CONFIG')).readAsString(),
  ) as Map<String, dynamic>;
  if (config['format'] != 'local-transcriber/1' ||
      config['engine'] != 'whisper.cpp' ||
      config['version'] != WhisperTranscriber.engineVersion ||
      config['source_commit'] != WhisperTranscriber.sourceCommit ||
      config['model_sha256'] != WhisperTranscriber.modelSha256 ||
      config['model_bytes'] != WhisperTranscriber.modelBytes) {
    throw StateError('Configuration does not match the pinned runtime/model.');
  }
  final audio = requiredEnv('STRATHVISION_TRANSCRIPTION_AUDIO');
  final transcriber = WhisperTranscriber(
    executablePath: config['executable'] as String,
    modelPath: config['model'] as String,
    executableSha256: config['executable_sha256'] as String,
  );
  final timer = Stopwatch()..start();
  final result = await transcriber.transcribe(
    audio,
    cancellation: TranscriptionCancellation(),
  );
  timer.stop();
  final expected =
      Platform.environment['STRATHVISION_TRANSCRIPTION_EXPECTED'] ??
      'ask not what your country can do for you';
  if (!normalized(result.text).contains(normalized(expected))) {
    throw StateError('Real-audio output did not contain the expected phrase.');
  }
  final report = <String, Object?>{
    'format': 'local-transcription-acceptance/1',
    'status': 'passed',
    'recorded_at': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'source_commit': config['source_commit'],
    'model_revision': config['model_revision'],
    'model_sha256': config['model_sha256'],
    'executable_sha256': await fileHash(config['executable'] as String),
    'audio_sha256': await fileHash(audio),
    'audio_bytes': await File(audio).length(),
    'elapsed_ms': timer.elapsedMilliseconds,
    'engine': result.engine,
    'model': result.model,
    'language': result.language,
    'text': result.text,
    'expected_phrase': expected,
    'metadata': result.metadata,
    'scope': 'Real speech through the app adapter, not a synthetic transcript.',
    'limitations': [
      'One short English historical speech sample; not coaching-language accuracy.',
      'Does not establish other languages, accents, noisy recordings or long-audio accuracy.',
      'Does not exercise physical desktop UI or human transcript review.',
    ],
  };
  final encoded = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  final reportPath = Platform.environment['STRATHVISION_TRANSCRIPTION_REPORT'];
  if (reportPath != null && reportPath.isNotEmpty) {
    final output = File(reportPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(encoded);
  }
  stdout.write(encoded);
}
