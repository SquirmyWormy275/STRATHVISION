import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'clip_probe.dart';
import 'profile_export.dart';
import 'profile_package.dart';
import '../vision/training_track.dart';
import 'source_identity.dart';

typedef ClipEvaluator = Future<ClipQuality> Function(
  ClipSource clip,
  String displayName,
);

/// Production evaluator: real pose on device, then quality evaluation.
ClipEvaluator visionEvaluator(AnalysisPack pack, {TrainingTrackLoader? load}) =>
    (clip, name) async {
      final track = await trainingTrack(clip, load: load);
      if (track.frames.isEmpty) {
        return ClipQuality(
          clipId: clip.clipId,
          displayName: name,
          usable: false,
          reasons: const ['No person could be found in this clip.'],
        );
      }
      return Isolate.run(
        () => ProfileBuilder(
          engine: AnalysisEngine(
            pack: pack,
            pose: PrecomputedPoseEstimator(track),
            implement: const GripImplementTracker(),
            phases: const EventPhaseDetector(),
            perStroke: true,
          ),
        ).evaluate(clip, displayName: name),
      );
    };

/// Evaluates a reference clip on a background isolate (stand-in pose).
ClipEvaluator isolateEvaluator(AnalysisPack pack) =>
    (clip, name) => Isolate.run(
      () =>
          ProfileBuilder(engine: AnalysisEngine(pack: pack))
              .evaluate(clip, displayName: name),
    );

/// Stores a built package in the app's profile store; returns its path.
typedef PackageStore = Future<String> Function(Profile profile);

/// Lets the user save a copy of the package; returns where, or null.
typedef PackageSaver = Future<String?> Function(
  String fileName,
  Uint8List bytes,
);

/// Adds the stored package to the Library.
typedef ProfileInstaller = Future<void> Function(
  ProfileMetadata metadata,
  String path,
);

enum ClipStatus { checking, done }

class BuilderClip {
  BuilderClip({required this.clipId, required this.path})
    : displayName = p.basenameWithoutExtension(path);

  String clipId;
  final String path;
  String? hash;
  final String displayName;
  ClipStatus status = ClipStatus.checking;
  ClipQuality? quality;

  bool get usable => quality?.usable ?? false;
}

/// State for building one coach profile from reference clips.
class ProfileBuilderController extends ChangeNotifier {
  ProfileBuilderController({
    required this.pack,
    required this.probe,
    required this.evaluate,
    required this.store,
    required this.save,
    required this.install,
    this.fingerprint = sourceHash,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AnalysisPack pack;
  final ClipProber probe;
  final ClipEvaluator evaluate;
  final PackageStore store;
  final PackageSaver save;
  final ProfileInstaller install;
  final Future<String> Function(String) fingerprint;
  Future<void> _queue = Future.value();
  final Map<String, BuilderClip> _hashes = {};
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  final List<BuilderClip> clips = [];
  String coachName = '';
  BuildOutcome? outcome;
  bool building = false;
  String? installedPath;
  String? savedTo;
  bool _disposed = false;

  int get usableCount => clips.where((c) => c.usable).length;
  bool get checking => clips.any((c) => c.status == ClipStatus.checking);
  int get minClips => pack.minClips;

  bool get canBuild =>
      coachName.trim().isNotEmpty && clips.isNotEmpty && !checking && !building;

  void setCoachName(String v) {
    coachName = v;
    _invalidate();
  }

  /// Clip import: probe, analyze, and judge each new clip.
  Future<void> addClips(List<String> paths) {
    final job = _queue.then((_) => _addClips(paths));
    _queue = job.catchError((Object _) {});
    return job;
  }

  Future<void> _addClips(List<String> paths) async {
    for (final path in paths) {
      if (_disposed) return;
      if (clips.any((c) => c.path == path)) continue;
      final c = BuilderClip(clipId: _uuid.v4(), path: path);
      clips.add(c);
      _invalidate();
      await _check(c);
    }
  }

  Future<void> _check(BuilderClip c) async {
    c.status = ClipStatus.checking;
    c.quality = null;
    _invalidate();
    try {
      final hash = await fingerprint(c.path);
      if (_disposed || !clips.contains(c)) return;
      if (_hashes.containsKey(hash) && _hashes[hash] != c) {
        c.quality = ClipQuality(
          clipId: c.clipId,
          displayName: c.displayName,
          usable: false,
          reasons: const ['This recording is already included.'],
        );
        return;
      }
      if (c.hash != hash && _hashes[c.hash] == c) _hashes.remove(c.hash);
      c.hash = hash;
      _hashes[hash] = c;
      c.clipId = 'sha256:$hash';
      final info = await probe(c.path);
      if (info == null) {
        throw AnalysisError(
          ErrorCode.phaseDetectionFailed,
          'This file could not be opened as video.',
        );
      }
      final quality = await evaluate(
        ClipSource(
          clipId: c.clipId,
          path: c.path,
          durationMs: info.durationMs,
          fps: info.fps,
        ),
        c.displayName,
      );
      if (_disposed || !clips.contains(c)) return;
      c.quality = quality;

    } catch (error) {
      c.quality = ClipQuality(
        clipId: c.clipId,
        displayName: c.displayName,
        usable: false,
        reasons: [
          error is AnalysisError
              ? error.message
              : 'This clip could not be checked. Retry or remove it.',
        ],
      );
    } finally {
      c.status = ClipStatus.done;
      _notify();
    }
  }

  Future<void> retryClip(BuilderClip c) {
    final job = _queue.then((_) async {
      if (!clips.contains(c) || c.usable || _disposed) return;
      await _check(c);
    });
    _queue = job.catchError((Object _) {});
    return job;
  }

  void removeClip(BuilderClip c) {
    if (_hashes[c.hash] == c) _hashes.remove(c.hash);
    clips.remove(c);
    _invalidate();
  }

  /// Applies the quality gates. A ready profile is stored and added to the
  /// Library right away; a rejection says what is missing.
  Future<void> build({Profile? previous}) async {
    if (!canBuild) return;
    building = true;
    _notify();
    try {
      final builder = ProfileBuilder(engine: AnalysisEngine(pack: pack));
      final out = builder.build(
        coachName: coachName.trim(),
        clips: [for (final c in clips) c.quality!],
        newProfileId: _uuid.v4(),
        now: _clock(),
        previous: previous,
      );
      outcome = out;
      if (out is BuildReady) {
        final path = await store(out.profile);
        // Re-read through the importer: the stored file must pass the same
        // checks as any imported package.
        await install(await readProfilePackage(path), path);
        installedPath = path;
      }
    } finally {
      building = false;
      _notify();
    }
  }

  /// Saves a copy of the ready package wherever the user chooses.
  Future<void> exportCopy() async {
    final out = outcome;
    if (out is! BuildReady) return;
    savedTo = await save(
      packageFileName(out.profile),
      zipProfilePackage(out.profile),
    );
    _notify();
  }

  void _invalidate() {
    outcome = null;
    installedPath = null;
    savedTo = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
