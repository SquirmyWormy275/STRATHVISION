import 'dart:async';
import 'dart:io';
import '../profiles/source_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'project.dart';
import 'stage_player.dart';

enum Stage { a, b }
abstract class ProjectStore {
  Future<void> saveProject(Project project);
}

/// Workspace Events contract: playback, sync, annotation and reversible marks.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required Project project, required this.store,
    required StagePlayer playerA, required StagePlayer playerB,
    List<String> attributes = const [], this.packId, this.eventId,
    DateTime Function()? clock,
    this.driftTolerance = const Duration(milliseconds: 40),
    this.driftCheckInterval = const Duration(milliseconds: 250),
  }) : _project = project,
       _players = {Stage.a: playerA, Stage.b: playerB},
       _attributes = List.of(attributes),
       _activeAttribute = attributes.isEmpty ? null : attributes.first,
       _clock = clock ?? DateTime.now {
    for (final s in Stage.values) {
      _subs.add(_players[s]!.changes.listen((_) => _notify()));
    }
  }
  final ProjectStore store;
  String? packId, eventId;
  final Duration driftTolerance, driftCheckInterval;
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
  Future<void> _pendingInputs = Future<void>.value();
  Future<void> _writes = Future<void>.value();
  int _revision = 0, _savedRevision = 0;

  /// Domain writes are ordered. Resume timers never write Project JSON.
  Future<void> _persist(Project snapshot, int revision) {
    final write = _writes.then((_) async {
      await store.saveProject(snapshot);
      if (revision > _savedRevision) _savedRevision = revision;
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
  Future<void> flush() async {
    await _pendingInputs;
    await _writes;
    if (_savedRevision < _revision) await _persist(_project, _revision);
  }
  /// Only future marks use a newly chosen context; historical marks are immutable.
  void configureContext({String? packId, String? eventId,
      required List<String> attributes, String? selectedAttribute}) {
    this.packId = packId; this.eventId = eventId;
    _attributes..clear()..addAll(attributes);
    _activeAttribute = attributes.contains(selectedAttribute) ? selectedAttribute : attributes.firstOrNull;
    _notify();
  }
  Duration displayedPosition(Stage stage) {
    final current = player(stage);
    return current is MediaKitStagePlayer ? current.decoderPosition : current.position;
  }
  Future<bool> settleFrames() async {
    for (final stage in locked ? Stage.values : [activeStage]) {
      final current = player(stage);
      if (current is MediaKitStagePlayer && !await current.settleSeek()) return false;
    }
    return true;
  }

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
  String? _stageClipId(Stage s) => s == Stage.a ? _project.workspace.stageAClipId : _project.workspace.stageBClipId;

  Future<void> restore() async {
    for (final s in Stage.values) {
      final clip = clipOn(s);
      if (clip != null) await player(s).open(clip.path);
    }
    for (final s in Stage.values) { await player(s).setRate(rate); }
    if (locked) await _alignB();
    _notify();
  }
  @override
  void dispose() {
    _disposed = true; _driftTimer?.cancel();
    for (final s in _subs) { s.cancel(); }
    super.dispose();
  }
  void _notify() { if (!_disposed) notifyListeners(); }
  Future<void> _commit(Project next, {bool undoable = true}) async {
    if (undoable) _undo.add(_project);
    _project = next; _notify();
    await _persist(_project, ++_revision);
  }
  void setActiveStage(Stage s) { _activeStage = s; _notify(); }

  Future<void> loadClip(Stage stage, String path) async {
    await _pauseAll();
    var clips = _project.clips;
    var clip = clips.where((c) => c.path == path).firstOrNull;
    if (clip == null) {
      clip = Clip(clipId: _uuid.v4(), path: path,
        displayName: p.basenameWithoutExtension(path), addedAt: _clock());
      clips = [...clips, clip];
    }
    final id = clip.clipId;
    final ws = stage == Stage.a
        ? _project.workspace.copyWith(stageAClipId: () => id)
        : _project.workspace.copyWith(stageBClipId: () => id);
    final previous = clipOn(stage), previousPosition = player(stage).position;
    try {
      await player(stage).open(path); await player(stage).setRate(rate);
    } catch (_) {
      if (previous != null && previous.path != path) {
        try {
          await player(stage).open(previous.path);
          await player(stage).setRate(rate);
          await player(stage).seek(previousPosition);
        } catch (_) { /* Retain the original reference and recovery controls. */ }
      }
      rethrow;
    }
    _activeStage = stage;
    await _commit(_project.copyWith(clips: clips, workspace: ws));
    if (locked) await _alignB();
  }
  /// Hide a stage without deleting footage, marks or saved sync relationships.
  Future<void> clearStage(Stage stage) async {
    if (clipOn(stage) == null) return;
    await _pauseAll();
    final ws = stage == Stage.a
        ? _project.workspace.copyWith(stageAClipId: () => null)
        : _project.workspace.copyWith(stageBClipId: () => null);
    await player(stage).close();
    _activeStage = stage == Stage.a ? Stage.b : Stage.a;
    await _commit(_project.copyWith(workspace: ws));
  }
  Map<String, Object?>? athleteFor(String clipId) => _project.clipById(clipId)?.athlete;
  Future<void> setAthlete(String clipId, Map<String, Object?>? athlete) async {
    if (_project.clipById(clipId) == null) return;
    await _commit(_project.copyWith(clips: [
      for (final c in _project.clips) c.clipId == clipId ? c.withAthlete(athlete) : c,
    ]));
  }

  /// Locked seeks align from the requested A target, not stale decoder state.
  Future<void> scrub(Stage stage, Duration position) async {
    _activeStage = stage;
    final s = sync;
    if (locked && s != null) {
      final a = stage == Stage.a ? position : position - Duration(milliseconds: s.offsetMs);
      final aTarget = _clamp(Stage.a, a);
      await player(Stage.a).seek(aTarget); await _alignB(aPosition: aTarget);
    } else { await player(stage).seek(_clamp(stage, position)); }
    _notify();
  }
  Future<void> setSyncPoint() async {
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    if (a == null || b == null) return;
    final offset = player(Stage.b).position.inMilliseconds - player(Stage.a).position.inMilliseconds;
    final rel = SyncRelationship(clipAId: a, clipBId: b, offsetMs: offset, createdAt: _clock());
    await _commit(_project.copyWith(syncRelationships: [
      for (final r in _project.syncRelationships) if (!r.pairs(a, b)) r, rel,
    ], workspace: _project.workspace.copyWith(locked: true)));
  }
  Future<void> clearSync() async {
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    if (sync == null) return;
    _stopDriftCorrection();
    await _commit(_project.copyWith(syncRelationships: [
      for (final r in _project.syncRelationships) if (!r.pairs(a, b)) r,
    ], workspace: _project.workspace.copyWith(locked: false)));
  }
  Future<void> setLocked(bool value) async {
    if (value && sync == null) return;
    if (value == _project.workspace.locked) return;
    await _commit(_project.copyWith(workspace: _project.workspace.copyWith(locked: value)), undoable: false);
    if (value) {
      await _alignB(); if (playing) await _playLocked();
    } else { _stopDriftCorrection(); }
  }
  Future<void> togglePlay() => playing ? _pauseAll() : play();
  Future<void> play() async {
    if (locked) { await _playLocked(); } else { await player(_activeStage).play(); }
    _notify();
  }
  Future<void> _playLocked() async {
    await _alignB(); await player(Stage.a).play(); await player(Stage.b).play();
    _startDriftCorrection();
  }
  Future<void> pause() => _pauseAll();
  Future<void> _pauseAll() async {
    _stopDriftCorrection();
    for (final s in Stage.values) { if (player(s).playing) await player(s).pause(); }
    if (locked) await _alignB();
    _notify();
  }
  Future<void> setRate(double value) async {
    for (final s in Stage.values) { await player(s).setRate(value); }
    await _commit(_project.copyWith(workspace: _project.workspace.copyWith(playbackRate: value)), undoable: false);
    if (locked) await _alignB();
  }
  Future<void> stepFrame({required bool forward}) async {
    _stopDriftCorrection();
    if (locked) {
      for (final s in Stage.values) { if (player(s).playing) await player(s).pause(); }
      await _stepAndSettle(Stage.a, forward); await _alignB();
    } else {
      final pl = player(_activeStage);
      if (pl.playing) await pl.pause();
      await _stepAndSettle(_activeStage, forward);
    }
    _notify();
  }
  Future<void> _stepAndSettle(Stage s, bool forward) async {
    final pl = player(s), before = player(s).position;
    final moved = pl.changes.firstWhere((_) => pl.position != before);
    await pl.stepFrame(forward: forward);
    await moved.timeout(const Duration(milliseconds: 300), onTimeout: () {});
  }
  Future<void> toggleMirrorB() => _commit(_project.copyWith(
      workspace: _project.workspace.copyWith(mirrorB: !mirrorB)));

  /// Reverse the sync offset with the pair; preserve linked playback.
  Future<void> swapStages() async {
    await _pauseAll();
    final a = _stageClipId(Stage.a), b = _stageClipId(Stage.b);
    final old = sync;
    final posA = player(Stage.a).position, posB = player(Stage.b).position;
    final rels = [
      for (final r in _project.syncRelationships) if (old == null || !r.pairs(a, b)) r,
      if (old != null && a != null && b != null)
        SyncRelationship(clipAId: b, clipBId: a, offsetMs: -old.offsetMs, createdAt: old.createdAt),
    ];
    final ws = _project.workspace.copyWith(stageAClipId: () => b, stageBClipId: () => a);
    await _commit(_project.copyWith(syncRelationships: rels, workspace: ws));
    await _reopenStages(seekA: posB, seekB: posA);
  }
  Future<void> annotate(String text) async {
    final clip = clipOn(_activeStage);
    if (clip == null || text.trim().isEmpty) return;
    await _commit(_project.copyWith(annotations: [..._project.annotations,
      Annotation(annotationId: _uuid.v4(), clipId: clip.clipId,
        timeMs: displayedPosition(_activeStage).inMilliseconds, text: text.trim(), createdAt: _clock()),
    ]));
  }
  void selectAttribute(String attribute) {
    if (!_attributes.contains(attribute)) _attributes.add(attribute);
    _activeAttribute = attribute; _notify();
  }
  Future<void> mark(MarkLabel label, {MarkAuthor author = MarkAuthor.athlete}) {
    final previous = _pendingInputs;
    final work = _mark(label, author: author);
    _pendingInputs = Future.wait<void>([previous, work]).then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }
  Future<void> _mark(MarkLabel label, {MarkAuthor author = MarkAuthor.athlete}) async {
    final clip = clipOn(_activeStage), attribute = _activeAttribute;
    if (clip == null || attribute == null) return;
    final timeMs = displayedPosition(_activeStage).inMilliseconds;
    final markedPack = packId, markedEvent = eventId;
    final createdAt = _clock();
    String? hash;
    try { if (File(clip.path).existsSync()) hash = await sourceHash(clip.path); }
    catch (_) { /* Retain locally without inventing provenance. */ }
    if (_disposed) return;
    await _commit(_project.copyWith(marks: [..._project.marks,
      Mark(markId: _uuid.v4(), clipId: clip.clipId, timeMs: timeMs,
        packId: markedPack, eventId: markedEvent, sourceSha256: hash,
        attribute: attribute, label: label, author: author, createdAt: createdAt),
    ]));
  }
  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final before = _project, restored = _undo.removeLast();
    _project = restored.copyWith(workspace: restored.workspace.copyWith(
      playbackRate: before.workspace.playbackRate,
      locked: before.workspace.locked && restored.activeSync != null));
    _notify(); await _persist(_project, ++_revision);
    final stagesChanged = before.workspace.stageAClipId != _project.workspace.stageAClipId ||
        before.workspace.stageBClipId != _project.workspace.stageBClipId;
    if (stagesChanged) { await _pauseAll(); await _reopenStages(); }
    else if (!locked) { _stopDriftCorrection(); }
    else { await _alignB(); }
  }
  Future<void> _reopenStages({Duration? seekA, Duration? seekB}) async {
    for (final (s, seekTo) in [(Stage.a, seekA), (Stage.b, seekB)]) {
      final clip = clipOn(s);
      if (clip == null) { await player(s).close(); continue; }
      await player(s).open(clip.path); await player(s).setRate(rate);
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
  Future<void> _alignB({Duration? aPosition}) async {
    final s = sync;
    if (s == null) return;
    final target = (aPosition ?? player(Stage.a).position) + Duration(milliseconds: s.offsetMs);
    await player(Stage.b).seek(_clamp(Stage.b, target));
  }
  void _startDriftCorrection() {
    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(driftCheckInterval, (_) => correctDrift());
  }
  void _stopDriftCorrection() {
    _driftTimer?.cancel(); _driftTimer = null;
    if (_bRateNudged) { _bRateNudged = false; unawaited(player(Stage.b).setRate(rate)); }
  }
  bool _bRateNudged = false;
  static const hardResyncThreshold = Duration(milliseconds: 250);
  static const _catchUpSeconds = 0.5;
  @visibleForTesting
  Future<void> correctDrift() async {
    final s = sync;
    if (!locked || s == null) return;
    final target = _clamp(Stage.b, player(Stage.a).position + Duration(milliseconds: s.offsetMs));
    final drift = player(Stage.b).position - target;
    final size = drift.abs();
    if (size > hardResyncThreshold) {
      await player(Stage.b).seek(target);
      if (_bRateNudged) { _bRateNudged = false; await player(Stage.b).setRate(rate); }
    } else if (size > driftTolerance) {
      final delta = (drift.inMicroseconds / 1e6 / _catchUpSeconds).clamp(-rate * 0.5, rate * 0.5);
      _bRateNudged = true; await player(Stage.b).setRate(rate - delta);
    } else if (_bRateNudged) { _bRateNudged = false; await player(Stage.b).setRate(rate); }
  }
  @visibleForTesting
  bool get bRateNudged => _bRateNudged;
}
