import 'dart:convert';
import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../profiles/clip_probe.dart';
import '../profiles/profile_package.dart';
import '../vision/training_track.dart';

/// Analyzes one probe clip against the coach reference with patches applied.
typedef ProbeAnalyzer = Future<AnalysisDetail> Function(
  ClipSource clip,
  Map<String, double> reference,
  List<SpecialistPatch> patches,
);

/// Production probe analyzer: real pose on device, per stroke.
ProbeAnalyzer visionProbeAnalyzer(
  AnalysisPack pack, {
  TrainingTrackLoader? load,
}) => (clip, reference, patches) async {
  final track = await trainingTrack(clip, load: load);
  if (track.frames.isEmpty) {
    return AnalysisDetail(
      AnalysisFailure(
        AnalysisError(
          ErrorCode.lowPoseConfidence,
          'No person could be found in this clip.',
        ),
      ),
      const {},
    );
  }
  return _analyzeTrack(pack, track, clip, reference, patches);
};

// A separate scope prevents the database-backed selection loader from being
// captured by Isolate.run along with the transferable analysis inputs.
Future<AnalysisDetail> _analyzeTrack(AnalysisPack pack, PoseTrack track,
    ClipSource clip, Map<String, double> reference, List<SpecialistPatch> patches) =>
    Isolate.run(() => AnalysisEngine(
      pack: pack, pose: PrecomputedPoseEstimator(track),
      implement: const GripImplementTracker(), phases: const EventPhaseDetector(),
      heads: applyPatches(headsFor(pack), patches), perStroke: true,
    ).analyzeDetailed(clip, reference: reference));

ProbeAnalyzer isolateProbeAnalyzer(AnalysisPack pack) =>
    (clip, reference, patches) => Isolate.run(
      () => AnalysisEngine(
        pack: pack,
        heads: applyPatches(headsFor(pack), patches),
      ).analyzeDetailed(clip, reference: reference),
    );

/// Stores a new package version and adds it to the Library; returns its path.
typedef VersionWriter = Future<String> Function(
  Profile profile,
  Map<String, String> patches,
  Map<String, String> adapters,
);

enum AdapterState { missing, stale, compiled, pending }

/// Desktop workbench for one installed profile: tune its specialist head
/// with the harness and compile the pack's adapters, then save the result as
/// the next package version. The phone only loads what this writes.
class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    required this.pack,
    required this.bundle,
    required this.probe,
    required this.analyze,
    required this.write,
    this.compiler,
    this.fingerprint,
    DateTime Function()? clock,
    String Function(String path)? clipId,
  }) : _clock = clock ?? DateTime.now,
       _clipId = clipId ?? ((_) => _uuid.v4()) {
    final heads = headsFor(pack);
    _patches = loadPatches(bundle.patchFiles, heads);
    _adapters = loadAdapters(bundle.adapterFiles, pack, pack.adapters);
  }

  final AnalysisPack pack;
  final ProfileBundle bundle;
  final ClipProber probe;
  final ProbeAnalyzer analyze;
  final VersionWriter write;

  /// Null when no compiler is configured (no API key on this computer).
  final AdapterCompiler? compiler;
  final Future<String> Function(String)? fingerprint;
  final Set<String> _sourceHashes = {};
  final List<String> clipErrors = [];
  final DateTime Function() _clock;
  final String Function(String path) _clipId;
  static const _uuid = Uuid();

  late final PatchSet _patches;
  late final AdapterSet _adapters;
  final List<String> probeClipNames = [];
  final List<HarnessClip> _clips = [];
  final Map<String, CompiledAdapter> _compiled = {};
  final Map<String, String> compileErrors = {};
  final Set<String> compiling = {};
  bool addingClips = false;
  HarnessRun? run;
  String? savedPath;
  bool saving = false;
  bool _disposed = false;

  /// The head the harness tunes (the first patchable head of the event).
  HeadDef? get head =>
      pack.heads.where((h) => h.acceptance != null).firstOrNull;

  SpecialistPatch? get currentPatch =>
      _patches.applied.where((x) => x.head == head?.name).firstOrNull;

  int get probeClipCount => _clips.length;

  Map<String, double> get _reference => {
    for (final e in bundle.profile.metrics.entries) e.key: e.value.center,
  };

  AdapterState adapterState(AdapterSpec spec) {
    if (_compiled.containsKey(spec.name)) return AdapterState.pending;
    if (_adapters.adapters.containsKey(spec.name)) return AdapterState.compiled;
    if (bundle.adapterFiles.containsKey('${spec.name}.paw')) {
      return AdapterState.stale;
    }
    return AdapterState.missing;
  }

  /// Patch accepted by the last run and not yet saved.
  SpecialistPatch? get pendingPatch =>
      run != null && run!.decision.accepted ? run!.patch : null;

  bool get hasChanges => pendingPatch != null || _compiled.isNotEmpty;

  /// Adds coach clips the probes are measured on.
  Future<void> addProbeClips(List<String> paths) async {
    if (addingClips) return;
    addingClips = true;
    clipErrors.clear();
    run = null;
    _notify();
    try {
      for (final path in paths) {
        if (_disposed) return;
        try {
          final hash = await fingerprint?.call(path);
          if (hash != null && _sourceHashes.contains(hash)) continue;
          final info = await probe(path);
          if (info == null) {
            throw AnalysisError(
              ErrorCode.phaseDetectionFailed,
              'This file could not be opened as video.',
            );
          }
          final d = await analyze(
            ClipSource(
              clipId: hash == null ? _clipId(path) : 'sha256:$hash',
              path: path,
              durationMs: info.durationMs,
              fps: info.fps,
            ),
            _reference,
            currentPatch == null ? const [] : [currentPatch!],
          );
          if (_disposed) return;
          if (d.outcome case AnalysisFailure(:final error)) throw error;
          if (head == null) continue;
          if (hash != null) _sourceHashes.add(hash);
          _clips.add(HarnessClip.fromDetail(d, head!.name));
          probeClipNames.add(p.basenameWithoutExtension(path));
        } catch (error) {
          clipErrors.add(
            '${p.basename(path)}: ${error is AnalysisError ? error.message : "Could not check this clip. Retry it."}',
          );
        }
        _notify();
      }
    } finally {
      addingClips = false;
      _notify();
    }
  }

  /// Probe readings for the current head over the probe clips.
  Map<String, double?>? get baseline => head == null || _clips.isEmpty
      ? null
      : SpecialistHarness(
          pack: pack,
          headName: head!.name,
          clips: _clips,
          current: currentPatch,
        ).baseline();

  /// Runs the harness: proposes a sparse patch and judges it by the pack's
  /// rules, reading only the probes.
  void runHarness() {
    if (head == null || _clips.isEmpty) return;
    run = SpecialistHarness(
      pack: pack,
      headName: head!.name,
      clips: _clips,
      current: currentPatch,
    ).search();
    _notify();
  }

  Future<void> compile(AdapterSpec spec) async {
    final c = compiler;
    if (c == null) return;
    compiling.add(spec.name);
    compileErrors.remove(spec.name);
    _notify();
    try {
      _compiled[spec.name] = await compileAdapter(spec, pack, c, now: _clock());
    } on AnalysisError catch (e) {
      final problems = (e.details['problems'] as List?)?.join('; ');
      compileErrors[spec.name] = problems == null
          ? e.message
          : '${e.message} $problems';
    } finally {
      compiling.remove(spec.name);
      _notify();
    }
  }

  /// Writes the next package version with the accepted patch and newly
  /// compiled adapters. Existing files are kept unless replaced.
  Future<void> save() async {
    if (!hasChanges || saving) return;
    saving = true;
    _notify();
    try {
      final patch = pendingPatch;
      final patches = {
        ...bundle.patchFiles,
        if (patch != null) patch.fileName: jsonEncode(patch.toJson()),
      };
      final adapters = {
        ...bundle.adapterFiles,
        for (final a in _compiled.values) a.fileName: jsonEncode(a.toJson()),
      };
      final notes = [
        if (patch != null) 'Added ${patch.name}.',
        if (_compiled.isNotEmpty) 'Compiled ${_compiled.keys.join(', ')}.',
      ].join(' ');
      final p = bundle.profile;
      final next = Profile(
        profileId: p.profileId,
        version: p.version + 1,
        coachName: p.coachName,
        packId: p.packId,
        eventId: p.eventId,
        metricSchemaVersion: p.metricSchemaVersion,
        createdAt: _clock().toUtc(),
        sourceClipCount: p.sourceClipCount,
        minClipsMet: p.minClipsMet,
        selfConsistencyPassed: p.selfConsistencyPassed,
        notes: '${p.notes} $notes'.trim(),
        metrics: p.metrics,
        referenceClips: p.referenceClips,
      );
      savedPath = await write(next, patches, adapters);
    } finally {
      saving = false;
      _notify();
    }
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
