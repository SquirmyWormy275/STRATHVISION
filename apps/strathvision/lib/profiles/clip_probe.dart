import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Duration and frame rate of a clip, read without showing it.
class ClipInfo {
  const ClipInfo({required this.durationMs, required this.fps});
  final int durationMs;
  final double fps;
}

typedef ClipProber = Future<ClipInfo?> Function(String path);

/// Reads duration and frame rate with a headless media_kit player.
/// Returns null when the file cannot be opened as video.
Future<ClipInfo?> probeClip(String path) async {
  final player = Player();
  try {
    final native = player.platform;
    if (native is NativePlayer) {
      // media_kit turns the video track off (vid=no) when no controller is
      // attached, and then mpv never reports the frame rate. Select it, but
      // render nowhere.
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');
    }
    // Configure headless output before loading: opening with default outputs
    // can initialize display/audio backends that this probe never needs.
    await player.open(Media(path), play: false);
    if (native is NativePlayer) {
      await native.setProperty('vid', 'auto');
    }
    final duration = player.state.duration > Duration.zero
        ? player.state.duration
        : await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 10));
    // mpv reports the frame rate a little after the duration; poll briefly.
    var fps = 30.0;
    if (native is NativePlayer) {
      final end = DateTime.now().add(const Duration(seconds: 3));
      search:
      while (DateTime.now().isBefore(end)) {
        for (final prop in ['container-fps', 'estimated-vf-fps']) {
          final v = double.tryParse(await native.getProperty(prop));
          if (v != null && v > 1 && v < 1000) {
            fps = v;
            break search;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    return ClipInfo(durationMs: duration.inMilliseconds, fps: fps);
  } on TimeoutException {
    return null;
  } finally {
    await player.dispose();
  }
}
