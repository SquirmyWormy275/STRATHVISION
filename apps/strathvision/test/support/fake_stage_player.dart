import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:strathvision/workspace/stage_player.dart';

/// Deterministic stand-in for a decoder: 30 fps, exact seeks, and
/// [advance] to simulate wall-clock playback at the current rate.
class FakeStagePlayer implements StagePlayer {
  FakeStagePlayer({
    this.clipDuration = const Duration(seconds: 20),
    this.lagSeeks = false,
  });

  /// When true, seeks only land on [settle], like a real decoder whose
  /// reported position updates after the seek call returns.
  final bool lagSeeks;
  Duration? _queuedSeek;

  static const frame = Duration(microseconds: 33333);

  final Duration clipDuration;
  final _changes = StreamController<void>.broadcast(sync: true);
  final List<String> log = [];

  String? openedPath;
  Duration _position = Duration.zero;
  bool _playing = false;
  double rate = 1.0;
  bool disposed = false;

  @override
  Duration get position => _position;
  @override
  Duration get duration => openedPath == null ? Duration.zero : clipDuration;
  @override
  bool get playing => _playing;
  @override
  bool get hasMedia => openedPath != null;
  @override
  Stream<void> get changes => _changes.stream;

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> open(String path) async {
    log.add('open $path');
    openedPath = path;
    _position = Duration.zero;
    _playing = false;
    _emit();
  }

  @override
  Future<void> close() async {
    openedPath = null;
    _position = Duration.zero;
    _playing = false;
    _emit();
  }

  @override
  Future<void> play() async {
    if (openedPath == null) return;
    _playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emit();
  }

  @override
  Future<void> seek(Duration p) async {
    log.add('seek ${p.inMilliseconds}');
    if (lagSeeks) {
      _queuedSeek = _clamp(p);
      return;
    }
    _position = _clamp(p);
    _emit();
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
    _emit();
  }

  @override
  Future<double> frameRate() async => 30;

  @override
  Future<void> stepFrame({required bool forward}) async {
    _playing = false;
    _position = _clamp(forward ? _position + frame : _position - frame);
    _emit();
  }

  /// Applies a lagged seek (see [lagSeeks]).
  void settle() {
    final q = _queuedSeek;
    if (q == null) return;
    _queuedSeek = null;
    _position = q;
    _emit();
  }

  /// Simulates [wall] of real time passing while playing.
  void advance(Duration wall) {
    if (!_playing) return;
    _position = _clamp(_position + wall * rate);
    _emit();
  }

  /// Forces an arbitrary position without going through seek (simulated drift).
  void jumpTo(Duration p) {
    _position = _clamp(p);
    _emit();
  }

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (openedPath != null && d > clipDuration) return clipDuration;
    return d;
  }

  @override
  Widget view({required bool mirror}) => ColoredBox(
        key: Key('fake-video${mirror ? '-mirrored' : ''}'),
        color: const Color(0xFF101010),
      );

  @override
  Future<void> dispose() async {
    disposed = true;
    await _changes.close();
  }
}
