import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// One decoded frame: BGRA pixels. Rows may be padded: [stride] is the
/// number of bytes per row (mpv aligns rows, e.g. 1080 px → 4352 bytes).
class VideoFrame {
  const VideoFrame(this.bgra, this.width, this.height, this.stride);
  final Uint8List bgra;
  final int width, height, stride;
}

VideoFrame? _frame(Uint8List? bytes, int? w, int? h) {
  if (bytes == null || w == null || h == null || h == 0) return null;
  final stride = bytes.length ~/ h;
  if (stride < w * 4) return null;
  return VideoFrame(bytes, w, h, stride);
}

/// Decodes frames at exact times with a headless media_kit player (no
/// window, no sound). Video never leaves the device.
class FrameGrabber {
  FrameGrabber._(this._player, {this.toneMapped = false});
  final Player _player;

  /// The clip is HDR and frames are tone-mapped to standard video.
  final bool toneMapped;

  static Future<FrameGrabber?> open(String path) async {
    final p = Player();
    final native = p.platform;
    if (native is NativePlayer) {
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');
      await native.setProperty('hr-seek', 'yes');
      // frame-step plays one frame at playback speed, so at 1× each step
      // waited out the frame's display time (~90 ms per 1080p HDR frame;
      // 27 ms at 16×). Never drop frames: every step must be the next one.
      await native.setProperty('speed', '16');
      await native.setProperty('framedrop', 'no');
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
    await _firstFrame(p);
    // HDR video (phones record HLG / Dolby Vision) comes out of the
    // headless decoder washed out, so bright scenes lose the person
    // entirely. Tone-map it to standard video; SDR is left as is.
    var mapped = false;
    if (native is NativePlayer) {
      final gamma = await native.getProperty('video-params/gamma');
      if (gamma == 'pq' || gamma == 'hlg') mapped = await _toneMap(p, native);
    }
    return FrameGrabber._(p, toneMapped: mapped);
  }

  /// HDR → SDR filters, best first: zscale + Hable tone mapping (fast;
  /// needs libmpv built with zimg), then mpv's own colour conversion.
  static const toneMapFilters = [
    'lavfi=[zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,'
        'tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p]',
    'format=convert=yes:gamma=bt.1886:primaries=bt.709',
  ];

  static Future<bool> _toneMap(Player p, NativePlayer native) async {
    for (final vf in toneMapFilters) {
      try {
        await native.setProperty('vf', vf);
      } catch (_) {
        continue;
      }
      await p.seek(Duration.zero);
      if (await _firstFrame(p) && (await native.getProperty('vf')).isNotEmpty) return true;
      await native.setProperty('vf', '');
    }
    await p.seek(Duration.zero);
    await _firstFrame(p);
    return false;
  }

  /// Waits (up to 3 s) until a decoded frame is available: grabbing frame
  /// 0 straight after open raced the decoder and sometimes got nothing.
  static Future<bool> _firstFrame(Player p) async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(end)) {
      if (_frame(await p.screenshot(format: null), p.state.width, p.state.height) != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return false;
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
    return _frame(await _player.screenshot(format: null), _player.state.width, _player.state.height);
  }

  int _index = 0;

  /// Sequential decoding: the frame with index [index] (counting from 0 at
  /// the clip start), reached by stepping forward one decoded frame at a
  /// time. Exact and deterministic; [index] must not go backwards.
  Future<VideoFrame?> frameIndex(int index, {required double fps}) async {
    final native = _player.platform;
    if (native is! NativePlayer) return frameAt(Duration(microseconds: (index * 1e6 / fps).round()), fps: fps);
    while (_index < index) {
      // One frame-step decodes exactly one frame; it has landed when the
      // position moves. (mpv's estimated-frame-number is not usable: for
      // containers with a millisecond timebase, e.g. WebM, it counts
      // milliseconds.)
      final before = await native.getProperty('time-pos');
      await native.command(['frame-step']);
      _index++;
      final end = DateTime.now().add(const Duration(milliseconds: 1000));
      var reached = false;
      while (DateTime.now().isBefore(end)) {
        if (await native.getProperty('time-pos') != before) {
          reached = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (!reached && await native.getProperty('eof-reached') == 'yes') return null;
    }
    return _frame(await _player.screenshot(format: null), _player.state.width, _player.state.height);
  }

  Future<void> close() => _player.dispose();
}
