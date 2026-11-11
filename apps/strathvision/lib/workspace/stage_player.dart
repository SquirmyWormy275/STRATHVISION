import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One video stage. The controller depends on this testable decoder boundary.
abstract class StagePlayer {
  Duration get position;
  Duration get duration;
  bool get playing;
  bool get hasMedia;
  Stream<void> get changes;
  Future<void> open(String path);
  Future<void> close();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<double> frameRate();
  Future<void> stepFrame({required bool forward});
  Widget view({required bool mirror});
  Future<void> dispose();
}

class MediaKitStagePlayer implements StagePlayer {
  MediaKitStagePlayer() {
    _subs = [
      _player.stream.position.listen((_) => _changes.add(null)),
      _player.stream.duration.listen((_) => _changes.add(null)),
      _player.stream.playing.listen((_) => _changes.add(null)),
    ];
    final native = _player.platform;
    if (native is NativePlayer) {
      unawaited(native.setProperty('hr-seek', 'yes'));
      unawaited(native.setProperty('keep-open', 'yes'));
    }
    // Create video output before open: otherwise media_kit can disable vid.
    _video;
  }
  final Player _player = Player();
  late final VideoController _video = VideoController(
    _player,
    configuration: Platform.isAndroid
        ? const VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
          )
        : const VideoControllerConfiguration(),
  );
  final _changes = StreamController<void>.broadcast();
  late final List<StreamSubscription<Object?>> _subs;
  bool _hasMedia = false;
  Duration? _pendingSeek;
  Duration? _confirmationTarget;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// Decoder-reported position, never an optimistic seek target.
  Duration get decoderPosition => _player.state.position;
  double? get aspectRatio {
    final w = _player.state.width, h = _player.state.height;
    return w == null || h == null || h <= 0 ? null : w / h;
  }

  Future<bool> settleSeek() async {
    final target = _confirmationTarget;
    if (target == null || playing) return true;
    final frameUs = 1e6 / await frameRate();
    final toleranceUs = (frameUs / 2).round() + 2000;
    // A seek at or past the last frame settles on that frame's start time,
    // about one frame before the reported duration.
    final durationUs = duration.inMicroseconds;
    final atEnd =
        durationUs > 0 && target.inMicroseconds >= durationUs - 1.5 * frameUs;
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {
      final decoderUs = decoderPosition.inMicroseconds;
      if ((decoderUs - target.inMicroseconds).abs() <= toleranceUs ||
          (atEnd && decoderUs >= durationUs - 2.5 * frameUs)) {
        if (_confirmationTarget == target) _confirmationTarget = null;
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  @override
  Duration get position {
    final pending = _pendingSeek;
    if (pending != null) {
      final reported = _player.state.position;
      final settled =
          (reported - pending).abs() < const Duration(milliseconds: 20);
      final expired =
          DateTime.now().difference(_pendingSince) >
          const Duration(milliseconds: 750);
      if (!settled && !expired && !_player.state.playing) return pending;
      _pendingSeek = null;
    }
    return _player.state.position;
  }

  @override
  Duration get duration => _player.state.duration;
  @override
  bool get playing => _player.state.playing;
  @override
  bool get hasMedia => _hasMedia;
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> open(String path) async {
    if (!await File(path).exists()) {
      throw FileSystemException('Video unavailable', path);
    }
    _fps = null;
    _pendingSeek = null;
    _confirmationTarget = null;
    _hasMedia = false;
    await _player.stop();
    final ready = Completer<void>();
    final durationSub = _player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !ready.isCompleted) ready.complete();
    });
    // mpv reports recoverable decoder messages (for example "Could not open
    // codec." from one track or a hardware decoder probe) on the same channel
    // as fatal open failures. Fail only if no playable duration follows.
    Timer? errorGrace;
    final errorSub = _player.stream.error.listen((message) {
      errorGrace ??= Timer(const Duration(seconds: 2), () {
        if (!ready.isCompleted) ready.completeError(FormatException(message));
      });
    });
    Future<void> start() async {
      await _player.open(Media(path), play: false);
      final native = _player.platform;
      if (native is NativePlayer) await native.setProperty('vid', 'auto');
      if (_player.state.duration > Duration.zero && !ready.isCompleted) {
        ready.complete();
      }
    }

    try {
      await Future.wait<void>([
        start(),
        ready.future.timeout(const Duration(seconds: 10)),
      ], eagerError: true);
      _hasMedia = true;
      _changes.add(null);
    } catch (_) {
      if (!ready.isCompleted) ready.complete();
      await _player.stop();
      _changes.add(null);
      rethrow;
    } finally {
      errorGrace?.cancel();
      await durationSub.cancel();
      await errorSub.cancel();
    }
  }

  @override
  Future<void> close() async {
    await _player.stop();
    _hasMedia = false;
    _pendingSeek = null;
    _confirmationTarget = null;
    _changes.add(null);
  }

  @override
  Future<void> play() {
    // Playback supersedes any unconfirmed seek; a later pause must not wait
    // for the decoder to return to the old target.
    _pendingSeek = null;
    _confirmationTarget = null;
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) {
    _pendingSeek = position;
    _confirmationTarget = position;
    _pendingSince = DateTime.now();
    _changes.add(null);
    return _player.seek(position);
  }

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  double? _fps;
  @override
  Future<double> frameRate() async {
    if (_fps != null) return _fps!;
    final native = _player.platform;
    if (native is NativePlayer && _hasMedia) {
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(end)) {
        for (final prop in ['container-fps', 'estimated-vf-fps']) {
          final v = double.tryParse(await native.getProperty(prop));
          if (v != null && v > 1 && v < 1000) return _fps = v;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    return 30;
  }

  @override
  Future<void> stepFrame({required bool forward}) async {
    if (_player.state.playing) await _player.pause();
    final fps = await frameRate();
    final frameUs = 1e6 / fps;
    final current = (position.inMicroseconds / frameUs).round();
    final target = (current + (forward ? 1 : -1)).clamp(0, 1 << 31);
    var to = Duration(microseconds: (target * frameUs).round());
    if (duration > Duration.zero && to > duration) to = duration;
    await seek(to);
  }

  @override
  Widget view({required bool mirror}) {
    final video = Video(
      controller: _video,
      controls: NoVideoControls,
      fit: BoxFit.contain,
    );
    return mirror ? Transform.flip(flipX: true, child: video) : video;
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _changes.close();
    await _player.dispose();
  }
}
