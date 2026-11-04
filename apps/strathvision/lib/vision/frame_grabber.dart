import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// One decoded frame: BGRA pixels.
class VideoFrame {
  const VideoFrame(this.bgra, this.width, this.height);
  final Uint8List bgra;
  final int width, height;
}

/// Decodes frames at exact times with a headless media_kit player (no
/// window, no sound). Video never leaves the device.
class FrameGrabber {
  FrameGrabber._(this._player);
  final Player _player;

  static Future<FrameGrabber?> open(String path) async {
    final p = Player();
    final native = p.platform;
    if (native is NativePlayer) {
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');
      await native.setProperty('hr-seek', 'yes');
    }
    await p.open(Media(path), play: false);
    if (native is NativePlayer) await native.setProperty('vid', 'auto');
    try {
      if (p.state.duration <= Duration.zero) {
        await p.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 10));
      }
    } on TimeoutException {
      await p.dispose();
      return null;
    }
    return FrameGrabber._(p);
  }

  Duration get duration => _player.state.duration;

  /// The frame at [t] (exact seek), or null if it could not be decoded.
  /// Waits for mpv itself to finish seeking and land within half a frame
  /// of [t], so the same request always returns the same frame.
  Future<VideoFrame?> frameAt(Duration t, {double fps = 30}) async {
    await _player.seek(t);
    final native = _player.platform;
    final target = t.inMicroseconds / 1e6;
    final tolerance = 0.5 / fps;
    final end = DateTime.now().add(const Duration(milliseconds: 2000));
    while (DateTime.now().isBefore(end)) {
      if (native is NativePlayer) {
        final pos = double.tryParse(await native.getProperty('time-pos'));
        if (pos != null && (pos - target).abs() <= tolerance) break;
      } else if ((_player.state.position - t).abs() < const Duration(milliseconds: 15)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    final w = _player.state.width, h = _player.state.height;
    final bytes = await _player.screenshot(format: null);
    if (bytes == null || w == null || h == null || bytes.length < w * h * 4) return null;
    return VideoFrame(bytes, w, h);
  }

  int _frame = 0;

  /// Sequential decoding: the frame with index [index] (counting from 0 at
  /// the clip start), reached by stepping forward one decoded frame at a
  /// time. Exact and deterministic; [index] must not go backwards.
  Future<VideoFrame?> frameIndex(int index, {required double fps}) async {
    final native = _player.platform;
    if (native is! NativePlayer) return frameAt(Duration(microseconds: (index * 1e6 / fps).round()), fps: fps);
    while (_frame < index) {
      await native.command(['frame-step']);
      _frame++;
      final want = '$_frame';
      final end = DateTime.now().add(const Duration(milliseconds: 1000));
      var reached = false;
      while (DateTime.now().isBefore(end)) {
        if (await native.getProperty('estimated-frame-number') == want) {
          reached = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (!reached && await native.getProperty('eof-reached') == 'yes') return null;
    }
    final w = _player.state.width, h = _player.state.height;
    final bytes = await _player.screenshot(format: null);
    if (bytes == null || w == null || h == null || bytes.length < w * h * 4) return null;
    return VideoFrame(bytes, w, h);
  }

  Future<void> close() => _player.dispose();
}
