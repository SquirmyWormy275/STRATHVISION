import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../vision/frame_grabber.dart';

/// Presentation-only revision. Never substitutes for a feedback content hash.
Future<String?> presentationSignature(String path) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) return null;
  return sha256
      .convert(
        utf8.encode(
          '${await file.resolveSymbolicLinks()}:'
          '${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}',
        ),
      )
      .toString();
}

typedef PosterDecoder = Future<Uint8List?> Function(String path);

Future<Uint8List?> decodePoster(String path) async {
  final reader = await FrameGrabber.open(path);
  if (reader == null) return null;
  ui.Image? image;
  try {
    final frame = await reader.frameAt(
      Duration(
        milliseconds: math.min(
          500,
          math.max(0, reader.duration.inMilliseconds - 100),
        ),
      ),
    );
    if (frame == null) return null;
    final scale = math.min(1.0, 512 / math.max(frame.width, frame.height));
    final ready = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.bgra,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
      ready.complete,
      rowBytes: frame.stride,
      targetWidth: math.max(1, (frame.width * scale).round()),
      targetHeight: math.max(1, (frame.height * scale).round()),
      allowUpscaling: false,
    );
    image = await ready.future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return null;
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image?.dispose();
    await reader.close();
  }
}

class PosterRequest {
  final _completion = Completer<File?>();
  bool cancelled = false;
  Future<File?> get result => _completion.future;
  void cancel() {
    cancelled = true;
    complete(null);
  }

  void complete(File? file) {
    if (!_completion.isCompleted) _completion.complete(file);
  }
}

/// One lazy decoder, cancellable queued work, coalesced requests and disk LRU.
/// Cache failures do not affect playback. The cache never holds original files.
class ThumbnailService {
  ThumbnailService({
    PosterDecoder? decoder,
    Future<Directory> Function()? directory,
    this.diskLimit = 128 * 1024 * 1024,
  }) : _decode = decoder ?? decodePoster,
       _directory =
           directory ??
           (() async => Directory(
             p.join(
               (await getApplicationSupportDirectory()).path,
               'review-previews-v1',
             ),
           ));
  final PosterDecoder _decode;
  final Future<Directory> Function() _directory;
  final int diskLimit;
  Future<void> _tail = Future<void>.value();
  final _jobs = <String, List<PosterRequest>>{};
  bool _disposed = false, _suspended = false;
  Completer<void>? _resume;

  void suspend() {
    _suspended = true;
    _resume ??= Completer<void>();
  }

  void resume() {
    _suspended = false;
    _resume?.complete();
    _resume = null;
  }

  PosterRequest request(String path) {
    final request = PosterRequest();
    if (_disposed) {
      request.cancel();
      return request;
    }
    final waiting = _jobs[path];
    if (waiting != null) {
      waiting.add(request);
      return request;
    }
    final requests = _jobs[path] = [request];
    final work = _tail.then((_) async {
      File? result, temporary;
      try {
        if (_suspended) await _resume?.future;
        if (_disposed || requests.every((r) => r.cancelled)) return;
        final signature = await presentationSignature(path);
        if (signature == null) return;
        final root = await _directory();
        await root.create(recursive: true);
        if (p.isWithin(
          await root.resolveSymbolicLinks(),
          await File(path).resolveSymbolicLinks(),
        )) {
          throw const FileSystemException(
            'Original media cannot be inside the preview cache.',
          );
        }
        final file = File(p.join(root.path, '$signature.png'));
        if (await file.exists() && await file.length() > 0) {
          await file.setLastModified(DateTime.now());
          result = file;
          return;
        }
        final bytes = await _decode(path);
        // Keep a finished decode even if every tile was scrolled away; the
        // finally block only delivers to requests that are still live.
        if (_disposed ||
            bytes == null ||
            bytes.isEmpty ||
            await presentationSignature(path) != signature) {
          return;
        }
        temporary = File(
          p.join(
            root.path,
            '$signature.${DateTime.now().microsecondsSinceEpoch}.tmp',
          ),
        );
        await temporary.writeAsBytes(bytes, flush: true);
        if (!await file.exists()) await temporary.rename(file.path);
        result = file;
        final entries = <(File, FileStat)>[];
        await for (final entity in root.list(followLinks: false)) {
          if (entity is File &&
              RegExp(r'^[a-f0-9]{64}\.png$')
                  .hasMatch(p.basename(entity.path))) {
            entries.add((entity, await entity.stat()));
          }
        }
        entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
        var size = entries.fold<int>(0, (n, entry) => n + entry.$2.size);
        for (final entry in entries) {
          if (size <= diskLimit) break;
          if (entry.$1.path == file.path) continue;
          await entry.$1.delete();
          size -= entry.$2.size;
        }
      } catch (_) {
        // A finished fallback tile remains tappable, including for a missing drive.
      } finally {
        try {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        } catch (_) {
          /* cache only */
        }
        _jobs.remove(path);
        for (final r in requests) {
          if (!r.cancelled) r.complete(result);
        }
      }
    });
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }

  Future<void> dispose() async {
    _disposed = true;
    resume();
    for (final requests in _jobs.values) {
      for (final r in requests) {
        r.cancel();
      }
    }
    await _tail;
  }
}
