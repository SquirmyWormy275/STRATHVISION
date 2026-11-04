import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One video stage. The workspace controller talks only to this interface,
/// so locked-playback logic is testable without a real decoder.
abstract class StagePlayer {
  Duration get position;
  Duration get duration;
  bool get playing;
  bool get hasMedia;

  /// Emits whenever position, duration, or play state changes.
  Stream<void> get changes;

  Future<void> open(String path);
  Future<void> close();
  Future<void> play();
  Future<void> pause();

  /// Exact (frame-accurate) seek.
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);

  /// Frames per second of the open clip (container rate, else decoder
  /// estimate, else 30).
  Future<double> frameRate();

  /// Steps exactly one decoded frame. Pauses playback.
  Future<void> stepFrame({required bool forward});

  /// Renders the stage; [mirror] flips horizontally.
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
      // Exact seeks everywhere; keep frames when paused after a step.
      unawaited(native.setProperty('hr-seek', 'yes'));
      unawaited(native.setProperty('keep-open', 'yes'));
    }
  }

  final Player _player = Player();
  // Android: decode with MediaCodec straight onto the surface. mpv's GPU
  // output needs an EGL context some Android GPUs (and emulators) refuse.
  late final VideoController _video = VideoController(
    _player,
    configuration: Platform.isAndroid
        ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
        : const VideoControllerConfiguration(),
  );
  final _changes = StreamController<void>.broadcast();
  late final List<StreamSubscription<Object?>> _subs;
  bool _hasMedia = false;

  /// Target of an in-flight seek. mpv reports the new position asynchronously;
  /// until it does, callers see the target so chained seeks/steps compose.
  Duration? _pendingSeek;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// Position as last reported by mpv, ignoring any in-flight seek target.
  Duration get decoderPosition => _player.state.position;

  @override
  Duration get position {
    final pending = _pendingSeek;
    if (pending != null) {
      final reported = _player.state.position;
      final settled = (reported - pending).abs() < const Duration(milliseconds: 20);
      final expired = DateTime.now().difference(_pendingSince) >
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
    _fps = null;
    await _player.open(Media(path), play: false);
    _hasMedia = true;
    _changes.add(null);
  }

  @override
  Future<void> close() async {
    await _player.stop();
    _hasMedia = false;
    _changes.add(null);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) {
    _pendingSeek = position;
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
      // mpv reports the rate a little after the file opens (noticeably later
      // on Android); poll briefly before falling back.
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

  /// Snaps to the frame grid and exact-seeks one frame. Deterministic in both
  /// directions, unlike mpv's frame-back-step.
  @override
  Future<void> stepFrame({required bool forward}) async {
    if (_player.state.playing) await _player.pause();
    final fps = await frameRate();
    final frameUs = 1e6 / fps;
    final current = (position.inMicroseconds / frameUs).round();
    final target = (current + (forward ? 1 : -1)).clamp(0, 1 << 31);
    var to = Duration(microseconds: (target * frameUs).round());
    if (duration > Duration.zero && to > duration) to = duration;
    await _player.seek(to);
  }

  @override
  Widget view({required bool mirror}) {
    final video = Video(controller: _video, controls: NoVideoControls);
    if (!mirror) return video;
    return Transform.flip(flipX: true, child: video);
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
