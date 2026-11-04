import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'project.dart';
import 'stage_player.dart';

enum Stage { a, b }

/// Persists projects. Implemented by the database; faked in tests.
abstract class ProjectStore {
  Future<void> saveProject(Project project);
}

/// Implements the Workspace Events contract (docs/INTERFACES.md):
/// load, independent scrub, set/clear sync, locked/independent play, rate,
/// frame step, mirror B, swap, annotate, red/green mark — plus one-tap undo.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required Project project,
    required this.store,
    required StagePlayer playerA,
    required StagePlayer playerB,
    List<String> attributes = const [],
    DateTime Function()? clock,
    this.driftTolerance = const Duration(milliseconds: 40),
    this.driftCheckInterval = const Duration(milliseconds: 250),
  })  : _project = project, // ignore: prefer_initializing_formals
        _players = {Stage.a: playerA, Stage.b: playerB},
        _attributes = List.of(attributes),
        _activeAttribute = attributes.isEmpty ? null : attributes.first,
        _clock = clock ?? DateTime.now {
    for (final s in Stage.values) {
      _subs.add(_players[s]!.changes.listen((_) => notifyListeners()));
    }
  }

  final ProjectStore store;
  final Duration driftTolerance;
  final Duration driftCheckInterval;
  final DateTime Function() _clock;
  final Map<Stage, StagePlayer> _players;
  final List<StreamSubscription<void>> _subs = [];
  final List<Project> _undo = [];
  static const _uuid = Uuid();

  Project _project;
  Stage _activeStage = Stage.a;
  final List<String> _attributes;
  String? _activeAttribute;
  Timer? _driftTimer;
  bool _disposed = false;

  // ---- read state ---------------------------------------------------------

  Project get project => _project;
  Stage get activeStage => _activeStage;
  StagePlayer player(Stage s) => _players[s]!;
  Clip? clipOn(Stage s) => _project.clipById(_stageClipId(s));
  SyncRelationship? get sync => _project.activeSync;
  bool get locked => _project.workspace.locked && sync != null;
  bool get mirrorB => _project.workspace.mirrorB;
  double get rate => _project.workspace.playbackRate;
  bool get canUndo => _undo.isNotEmpty;
  bool get playing => Stage.values.any((s) => player(s).playing);
  List<String> get attributes => List.unmodifiable(_attributes);
  String? get activeAttribute => _activeAttribute;
  bool get hasBothClips => clipOn(Stage.a) != null && clipOn(Stage.b) != null;

  List<Mark> marksFor(Stage s) {
    final id = _stageClipId(s);
    return _project.marks.where((m) => m.clipId == id).toList();
  }

  String? _stageClipId(Stage s) => s == Stage.a
      ? _project.workspace.stageAClipId
      : _project.workspace.stageBClipId;

  // ---- lifecycle ----------------------------------------------------------

  /// Opens the clips saved on each stage (re-opening a project).
  Future<void> restore() async {
    for (final s in Stage.values) {
      final clip = clipOn(s);
      if (clip != null) await player(s).open(clip.path);
    }
    for (final s in Stage.values) {
      await player(s).setRate(rate);
    }
    if (locked) await _alignB();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _driftTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _commit(Project next, {bool undoable = true}) async {
    if (undoable) _undo.add(_project);
    _project = next;
    _notify();
    await store.saveProject(_project);
  }

  // ---- events -------------------------------------------------------------

  void setActiveStage(Stage s) {
    _activeStage = s;
    _notify();
  }

  /// Load clip into stage A or B.
  Future<void> loadClip(Stage stage, String path) async {
    await _pauseAll();
    var clips = _project.clips;
    var clip = clips.where((c) => c.path == path).firstOrNull;
    if (clip == null) {
      clip = Clip(
        clipId: _uuid.v4(),
        path: path,
        displayName: p.basenameWithoutExtension(path),
        addedAt: _clock(),
      );
      clips = [...clips, clip];
    }
    final id = clip.clipId;
    final ws = stage == Stage.a
        ? _project.workspace.copyWith(stageAClipId: () => id)
        : _project.workspace.copyWith(stageBClipId: () => id);
    await player(stage).open(path);
    await player(stage).setRate(rate);
    _activeStage = stage;
    await _commit(_project.copyWith(clips: clips, workspace: ws));
    if (locked) await _alignB();
  }

  /// Scrub one stage. When locked, the other stage follows at the offset.
  Future<void> scrub(Stage stage, Duration position) async {
    _activeStage = stage;
    final s = sync;
    if (locked && s != null) {
      final a = stage == Stage.a
          ? position
          : position - Duration(milliseconds: s.offsetMs);
      final aTarget = _clamp(Stage.a, a);
      await player(Stage.a).seek(aTarget);
      // Seeks are asynchronous on a real decoder; align from the target, not
      // from A's (possibly stale) reported position.
      await _alignB(aPosition: aTarget);
    } else {
      await player(stage).seek(_clamp(stage, position));
    }
    _notify();
  }

  /// Records offset_ms = B - A at the current positions and locks the pair.
  Future<void> setSyncPoint() async {
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    if (a == null || b == null) return;
    final offset = player(Stage.b).position.inMilliseconds -
        player(Stage.a).position.inMilliseconds;
    final rel = SyncRelationship(
        clipAId: a, clipBId: b, offsetMs: offset, createdAt: _clock());
    await _commit(_project.copyWith(
      syncRelationships: [
        for (final r in _project.syncRelationships)
          if (!r.pairs(a, b)) r,
        rel,
      ],
      workspace: _project.workspace.copyWith(locked: true),
    ));
  }

  Future<void> clearSync() async {
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    if (sync == null) return;
    _stopDriftCorrection();
    await _commit(_project.copyWith(
      syncRelationships: [
        for (final r in _project.syncRelationships)
          if (!r.pairs(a, b)) r,
      ],
      workspace: _project.workspace.copyWith(locked: false),
    ));
  }

  /// Switch between locked and independent playback (needs a sync point).
  Future<void> setLocked(bool value) async {
    if (value && sync == null) return;
    if (value == _project.workspace.locked) return;
    await _commit(
        _project.copyWith(workspace: _project.workspace.copyWith(locked: value)),
        undoable: false);
    if (value) {
      await _alignB();
      if (playing) {
        await _playLocked();
      }
    } else {
      _stopDriftCorrection();
    }
  }

  Future<void> togglePlay() => playing ? _pauseAll() : play();

  /// Play locked (both at offset) or independent (active stage only).
  Future<void> play() async {
    if (locked) {
      await _playLocked();
    } else {
      await player(_activeStage).play();
    }
    _notify();
  }

  Future<void> _playLocked() async {
    await _alignB();
    await player(Stage.a).play();
    await player(Stage.b).play();
    _startDriftCorrection();
  }

  Future<void> pause() => _pauseAll();

  Future<void> _pauseAll() async {
    _stopDriftCorrection();
    for (final s in Stage.values) {
      if (player(s).playing) await player(s).pause();
    }
    if (locked) await _alignB();
    _notify();
  }

  /// Playback rate for both stages, including values below 1.0.
  Future<void> setRate(double value) async {
    for (final s in Stage.values) {
      await player(s).setRate(value);
    }
    await _commit(
        _project.copyWith(
            workspace: _project.workspace.copyWith(playbackRate: value)),
        undoable: false);
    if (locked) await _alignB();
  }

  /// Frame step the locked pair (A steps; B re-aligns to the offset) or the
  /// active stage.
  Future<void> stepFrame({required bool forward}) async {
    _stopDriftCorrection();
    if (locked) {
      for (final s in Stage.values) {
        if (player(s).playing) await player(s).pause();
      }
      await _stepAndSettle(Stage.a, forward);
      await _alignB();
    } else {
      final pl = player(_activeStage);
      if (pl.playing) await pl.pause();
      await _stepAndSettle(_activeStage, forward);
    }
    _notify();
  }

  Future<void> _stepAndSettle(Stage s, bool forward) async {
    final pl = player(s);
    final before = pl.position;
    final moved = pl.changes.firstWhere((_) => pl.position != before);
    await pl.stepFrame(forward: forward);
    // The decoder reports the new position asynchronously.
    await moved.timeout(const Duration(milliseconds: 300), onTimeout: () {});
  }

  Future<void> toggleMirrorB() => _commit(_project.copyWith(
      workspace: _project.workspace.copyWith(mirrorB: !mirrorB)));

  /// Swap the clips on A and B. A sync relationship is carried over with the
  /// pair reversed and the offset negated, so lock survives the swap.
  Future<void> swapStages() async {
    await _pauseAll();
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    final old = sync;
    final posA = player(Stage.a).position, posB = player(Stage.b).position;
    final rels = [
      for (final r in _project.syncRelationships)
        if (old == null || !r.pairs(a, b)) r,
      if (old != null && a != null && b != null)
        SyncRelationship(
            clipAId: b,
            clipBId: a,
            offsetMs: -old.offsetMs,
            createdAt: old.createdAt),
    ];
    final ws = _project.workspace
        .copyWith(stageAClipId: () => b, stageBClipId: () => a);
    await _commit(_project.copyWith(syncRelationships: rels, workspace: ws));
    await _reopenStages(seekA: posB, seekB: posA);
  }

  /// Annotate on the active stage at its current position.
  Future<void> annotate(String text) async {
    final clip = clipOn(_activeStage);
    if (clip == null || text.trim().isEmpty) return;
    await _commit(_project.copyWith(annotations: [
      ..._project.annotations,
      Annotation(
        annotationId: _uuid.v4(),
        clipId: clip.clipId,
        timeMs: player(_activeStage).position.inMilliseconds,
        text: text.trim(),
        createdAt: _clock(),
      ),
    ]));
  }

  void selectAttribute(String attribute) {
    if (!_attributes.contains(attribute)) _attributes.add(attribute);
    _activeAttribute = attribute;
    _notify();
  }

  /// Red/green on the selected attribute for the current stroke of the
  /// active stage. Does not move the playhead.
  Future<void> mark(MarkLabel label, {MarkAuthor author = MarkAuthor.athlete}) async {
    final clip = clipOn(_activeStage);
    final attribute = _activeAttribute;
    if (clip == null || attribute == null) return;
    await _commit(_project.copyWith(marks: [
      ..._project.marks,
      Mark(
        markId: _uuid.v4(),
        clipId: clip.clipId,
        timeMs: player(_activeStage).position.inMilliseconds,
        attribute: attribute,
        label: label,
        author: author,
        createdAt: _clock(),
      ),
    ]));
  }

  /// One-tap undo of the last mark, annotation, sync, load, swap, or mirror.
  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final before = _project;
    _project = _undo.removeLast();
    _notify();
    await store.saveProject(_project);
    final stagesChanged =
        before.workspace.stageAClipId != _project.workspace.stageAClipId ||
            before.workspace.stageBClipId != _project.workspace.stageBClipId;
    if (stagesChanged) {
      await _pauseAll();
      await _reopenStages();
    } else if (!locked) {
      _stopDriftCorrection();
    } else {
      await _alignB();
    }
  }

  // ---- internals ----------------------------------------------------------

  Future<void> _reopenStages({Duration? seekA, Duration? seekB}) async {
    for (final (s, seekTo) in [(Stage.a, seekA), (Stage.b, seekB)]) {
      final clip = clipOn(s);
      if (clip == null) {
        await player(s).close();
        continue;
      }
      await player(s).open(clip.path);
      await player(s).setRate(rate);
      if (seekTo != null) await player(s).seek(seekTo);
    }
    if (locked) await _alignB(aPosition: seekA);
    _notify();
  }

  Duration _clamp(Stage s, Duration d) {
    final max = player(s).duration;
    if (d < Duration.zero) return Duration.zero;
    if (max > Duration.zero && d > max) return max;
    return d;
  }

  /// Puts B exactly at A + offset. Pass [aPosition] when A was just seeked.
  Future<void> _alignB({Duration? aPosition}) async {
    final s = sync;
    if (s == null) return;
    final target = (aPosition ?? player(Stage.a).position) +
        Duration(milliseconds: s.offsetMs);
    await player(Stage.b).seek(_clamp(Stage.b, target));
  }

  void _startDriftCorrection() {
    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(driftCheckInterval, (_) => correctDrift());
  }

  void _stopDriftCorrection() {
    _driftTimer?.cancel();
    _driftTimer = null;
    if (_bRateNudged) {
      _bRateNudged = false;
      unawaited(player(Stage.b).setRate(rate));
    }
  }

  bool _bRateNudged = false;

  /// Drift above this is fixed with a hard seek; below it B's speed is nudged.
  /// Hard seeks stall a real decoder briefly, so seeking to fix small drift
  /// makes drift worse.
  static const hardResyncThreshold = Duration(milliseconds: 250);

  /// Wall time over which a speed nudge should close the gap.
  static const _catchUpSeconds = 0.5;

  /// Keeps B on A + offset while locked playback runs.
  @visibleForTesting
  Future<void> correctDrift() async {
    final s = sync;
    if (!locked || s == null) return;
    final target = _clamp(Stage.b,
        player(Stage.a).position + Duration(milliseconds: s.offsetMs));
    final drift = player(Stage.b).position - target; // + means B is ahead
    final size = drift.abs();

    if (size > hardResyncThreshold) {
      await player(Stage.b).seek(target);
      if (_bRateNudged) {
        _bRateNudged = false;
        await player(Stage.b).setRate(rate);
      }
    } else if (size > driftTolerance) {
      // Speed change that closes the gap in ~_catchUpSeconds of wall time,
      // capped at ±50% of the playback rate.
      final delta = (drift.inMicroseconds / 1e6 / _catchUpSeconds)
          .clamp(-rate * 0.5, rate * 0.5);
      _bRateNudged = true;
      await player(Stage.b).setRate(rate - delta);
    } else if (_bRateNudged) {
      _bRateNudged = false;
      await player(Stage.b).setRate(rate);
    }
  }

  /// B's current speed differs from [rate] to absorb drift.
  @visibleForTesting
  bool get bRateNudged => _bRateNudged;
}
