import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'carne_run.dart';
import 'local_transcriber.dart';

enum VoiceNoteStatus {
  received,
  transcribing,
  draft,
  accepted,
  rejected,
  failed,
  cancelled,
}

class VoiceNote {
  VoiceNote({
    required this.id,
    required this.name,
    required this.audioPath,
    required this.audioSha256,
  });
  final String id, name, audioPath, audioSha256;
  VoiceNoteStatus status = VoiceNoteStatus.received;
  String? draftText, error;
  VoiceTranscript? transcript;
  Map<String, Object?>? acceptedBinding;
  Map<String, Object?> toJson() => {
    'format': 'local_voice_note/1',
    'id': id,
    'name': name,
    'audio_path': audioPath,
    'audio_sha256': audioSha256,
    'status': status.name,
    'draft_text': draftText,
    'error': error,
    if (transcript case final result?)
      'transcription': {
        'text': result.text,
        'engine': result.engine,
        'model': result.model,
        'language': result.language,
        'metadata': result.metadata,
      },
    'binding': acceptedBinding,
  };
}

class VoiceTarget {
  const VoiceTarget({
    required this.clipId,
    required this.name,
    required this.strokeIndex,
    required this.startMs,
    required this.endMs,
  });
  final String clipId, name;
  final int strokeIndex, startMs, endMs;
}

/// Optional local files, outside profile packages. Nothing here downloads data.
/// Each session keeps its own audit records; reopening audio starts fresh review.
class VoiceNoteLibrary {
  VoiceNoteLibrary({Future<Directory> Function()? directory, this.transcriber})
    : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  final VoiceTranscriber? transcriber;
  static const maxAudioBytes = 100 * 1024 * 1024;

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'voice_notes'),
  );

  Future<Directory> _root() async =>
      (await _directory()).create(recursive: true);

  Future<VoiceNote> preserve(String path) async {
    final source = File(path);
    final size = await source.length();
    if (size == 0 || size > maxAudioBytes) {
      throw const FormatException(
        'Choose an audio file between 1 byte and 100 MiB.',
      );
    }
    final root = await _root();
    final id = const Uuid().v4();
    final pending = File(p.join(root.path, '$id.partial'));
    final sink = pending.openWrite();
    try {
      var copied = 0;
      await for (final bytes in source.openRead()) {
        copied += bytes.length;
        if (copied > maxAudioBytes) {
          throw const FormatException('Audio grew beyond the 100 MiB limit.');
        }
        sink.add(bytes);
      }
      await sink.flush();
      await sink.close();
      if (copied != size) {
        throw const FormatException('Audio changed while copying. Retry.');
      }
      final hash = await hashVideoContent(pending.path);
      final saved = File(
        p.join(root.path, '$hash${p.extension(path).toLowerCase()}'),
      );
      if (await saved.exists() && await hashVideoContent(saved.path) == hash) {
        await pending.delete();
      } else {
        await pending.rename(saved.path);
      }
      final note = VoiceNote(
        id: id,
        name: p.basename(path),
        audioPath: saved.path,
        audioSha256: hash,
      );
      await save(note);
      return note;
    } finally {
      await sink.close();
      if (await pending.exists()) await pending.delete();
    }
  }

  Future<void> verifyAudio(VoiceNote note) async {
    if (!await File(note.audioPath).exists() ||
        await hashVideoContent(note.audioPath) != note.audioSha256) {
      throw StateError(
        'The saved audio changed or is missing. Add the original voice note again.',
      );
    }
  }

  Future<void> save(VoiceNote note) async {
    final root = await _root();
    final file = File(p.join(root.path, '${note.id}.json'));
    final pending = File('${file.path}.partial');
    await pending.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(note.toJson())}\n',
      flush: true,
    );
    await pending.rename(file.path);
  }

  Future<VoiceTranscriber> loadTranscriber() async {
    if (transcriber != null) return transcriber!;
    final root = await _root();
    final settings = File(p.join(root.path, 'settings.json'));
    String? configPath =
        Platform.environment['STRATHVISION_TRANSCRIBER_CONFIG'];
    if (configPath == null && await settings.exists()) {
      if (await settings.length() > 16384) {
        throw const FormatException('Invalid voice settings.');
      }
      configPath =
          (jsonDecode(await settings.readAsString()) as Map)['config_path']
              as String?;
    }
    if (configPath == null) {
      throw const TranscriptionException(
        'missing_model',
        'Local transcription is optional. Set up the voice tools, then choose their transcriber.json file. Your audio is saved.',
      );
    }
    return _fromConfig(configPath);
  }

  Future<void> configure(String path) async {
    await _fromConfig(path);
    final root = await _root();
    await File(
      p.join(root.path, 'settings.json'),
    ).writeAsString(jsonEncode({'config_path': p.absolute(path)}), flush: true);
  }

  Future<VoiceTranscriber> _fromConfig(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() > 16384) {
      throw const FormatException(
        'Choose the transcriber.json created by voice setup.',
      );
    }
    final value = jsonDecode(await file.readAsString()) as Map;
    final executable = value['executable'], model = value['model'];
    if (value['format'] != 'local-transcriber/1' ||
        value['engine'] != 'whisper.cpp' ||
        value['version'] != WhisperTranscriber.engineVersion ||
        value['source_commit'] != WhisperTranscriber.sourceCommit ||
        value['model_sha256'] != WhisperTranscriber.modelSha256 ||
        value['model_bytes'] != WhisperTranscriber.modelBytes ||
        executable is! String ||
        !p.isAbsolute(executable) ||
        model is! String ||
        !p.isAbsolute(model) ||
        value['executable_sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(value['executable_sha256'] as String)) {
      throw const FormatException(
        'These voice tools do not match the supported version. Run voice setup again.',
      );
    }
    if (!await File(executable).exists() || !await File(model).exists()) {
      throw const FormatException(
        'The voice tools or model are missing. Run voice setup again.',
      );
    }
    return WhisperTranscriber(
      executablePath: executable,
      modelPath: model,
      executableSha256: value['executable_sha256'] as String,
    );
  }
}
