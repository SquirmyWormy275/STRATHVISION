import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../profiles/profile_package.dart';
import '../vision/athlete.dart';
import '../vision/athlete_choices.dart';
import '../vision/pose_service.dart';
import '../workspace/workspace_controller.dart';

/// Runs the engine for one clip with the given specialist patches applied.
/// [reference] holds the coach's metric centers (empty without a profile).
typedef AnalysisRunner = Future<AnalysisDetail> Function(ClipSource clip,
    List<SpecialistPatch> patches, Map<String, double> reference);

/// The production runner: finds the athlete (person detector + who is
/// chopping, or the user's saved choice in [athletes]), real 3D pose
/// (BlazePose) on them on this device, then the engine on a background
/// isolate (per-stroke, pack phase events).
AnalysisRunner visionRunner(AnalysisPack pack, {PoseService? poses, AthleteChoices? athletes}) =>
    (clip, patches, reference) async {
      final found = await (poses ?? PoseService.instance)
          .trackAthlete(clip, target: athletes?.targetFor(clip.clipId));
      athletes?.record(clip, found);
      return analyzeWithTrack(pack, clip, found.track, patches: patches, reference: reference);
    };

/// The engine on a precomputed real pose track, off the UI isolate.
Future<AnalysisDetail> analyzeWithTrack(AnalysisPack pack, ClipSource clip, PoseTrack track,
    {List<SpecialistPatch> patches = const [], Map<String, double> reference = const {}}) {
  if (track.frames.isEmpty) {
    return Future.value(AnalysisDetail(
        AnalysisFailure(AnalysisError(ErrorCode.lowPoseConfidence,
            'No person could be found in this clip.', {'pose_frames': 0})),
        const {}));
  }
  return Isolate.run(() => AnalysisEngine(
          pack: pack,
          pose: PrecomputedPoseEstimator(track),
          implement: const GripImplementTracker(),
          phases: const EventPhaseDetector(),
          heads: applyPatches(headsFor(pack), patches),
          perStroke: true)
      .analyzeDetailed(clip, reference: reference));
}

/// The engine with the stand-in pose (tests, and clips without video).
AnalysisRunner isolateRunner(AnalysisPack pack) =>
    (clip, patches, reference) => Isolate.run(() => AnalysisEngine(
            pack: pack, heads: applyPatches(headsFor(pack), patches))
        .analyzeDetailed(clip, reference: reference));

/// An installed profile the user can compare against.
class ProfileChoice {
  const ProfileChoice({
    required this.profileId,
    required this.version,
    required this.label,
    required this.path,
  });

  final String profileId;
  final int version;
  final String label;
  final String path;

  String get key => '$profileId@$version';
}

typedef ProfileChoices = Future<List<ProfileChoice>> Function();
typedef BundleLoader = Future<ProfileBundle> Function(String path);
typedef ResultSaver = Future<void> Function(ComparisonResult result);

/// Analysis for one clip: the Metric Vector (or error) and, when a profile
/// is selected, its comparison.
class ClipAnalysis {
  const ClipAnalysis({
    required this.outcome,
    this.comparison,
    this.profileKey,
    this.focus,
    this.usable,
    this.strokes = 0,
    this.usableStrokes = 0,
  });
  final AnalysisOutcome outcome;

  /// Strokes found, and how many could be measured.
  final int strokes;
  final int usableStrokes;
  final ComparisonOutcome? comparison;
  final String? profileKey;

  /// Attribute suggested by the package's priority adapter, if any.
  final String? focus;

  /// Verdict of the package's usable-footage adapter, if any.
  final bool? usable;
}

/// Whether to suggest filming at a higher frame rate: most strokes found
/// could not be measured (fast swings blur into each other at 30 fps or
/// less), and the clip is not already high frame rate.
bool suggestHigherFrameRate(ClipAnalysis a, double fps) =>
    fps < 50 && a.strokes >= 3 && a.usableStrokes < 0.6 * a.strokes;

/// Names of the adapters the app knows how to apply at inference.
const usableAdapter = 'usable_footage';
const priorityAdapter = 'priority_scorer';

/// Analyze state for the open workspace. The workspace keeps working when
/// analysis fails or is never used.
class AnalysisController extends ChangeNotifier {
  AnalysisController({
    required this.workspace,
    required this.pack,
    required this.run,
    this.listProfiles,
    this.loadBundle = readProfileBundle,
    this.saveResult,
    this.metricLabel,
    this.phaseLabel,
    this.athletes,
  });

  final WorkspaceController workspace;

  /// The active event's analysis section (heads for patches).
  final AnalysisPack pack;
  final AnalysisRunner run;
  final ProfileChoices? listProfiles;
  final BundleLoader loadBundle;
  final ResultSaver? saveResult;

  /// Pack labels for plain-language warnings.
  final String Function(String key)? metricLabel;
  final String Function(String id)? phaseLabel;

  /// Who is analysed per clip (vision runs only; null in tests and with
  /// the stand-in pose).
  final AthleteChoices? athletes;
  static const _uuid = Uuid();

  final Map<String, ClipAnalysis> _results = {};
  final Map<String, double> _fps = {};
  final Set<String> _running = {};
  final Map<String, ProfileBundle> _bundles = {};
  List<ProfileChoice> _choices = const [];
  ProfileChoice? _selected;
  AnalysisError? _profileError;
  bool _open = false;
  bool _loadedChoices = false;
  bool _disposed = false;

  bool get panelOpen => _open;
  List<ProfileChoice> get choices => _choices;
  ProfileChoice? get selectedProfile => _selected;

  /// Set when the selected package could not be read.
  AnalysisError? get profileError => _profileError;

  /// Clip on the active stage, if any.
  String? get clipId => workspace.clipOn(workspace.activeStage)?.clipId;

  ClipAnalysis? get analysis => clipId == null ? null : _results[clipId];
  AnalysisOutcome? get result => analysis?.outcome;
  ComparisonOutcome? get comparison => analysis?.comparison;
  bool get running => clipId != null && _running.contains(clipId);

  /// Frame rate the current result was computed at (for frame → time).
  double get fps => _fps[clipId] ?? 30;

  /// Analyse [target] in the current clip from now on (saved with the
  /// project), and re-analyse. Null returns to the automatic pick.
  Future<void> chooseAthlete(AthleteTarget? target) async {
    final id = clipId;
    if (id == null) return;
    await workspace.setAthlete(id, target?.toJson());
    await analyze();
  }

  void closePanel() {
    _open = false;
    _notify();
  }

  /// Installed profiles; the newest is selected by default.
  Future<void> refreshProfiles() async {
    final list = listProfiles;
    if (list == null) return;
    _choices = await list();
    _loadedChoices = true;
    if (_selected == null || !_choices.any((c) => c.key == _selected!.key)) {
      _selected = _choices.firstOrNull;
    }
    _notify();
  }

  /// Picks the profile to compare with (null = measurements only), and
  /// re-analyzes the current clip so its patches apply.
  Future<void> selectProfile(ProfileChoice? choice) async {
    _selected = choice;
    _profileError = null;
    _notify();
    if (analysis != null) await analyze();
  }

  /// Analyze the clip on the active stage, compare it with the selected
  /// profile, store the result, and open the panel.
  Future<void> analyze() async {
    final stage = workspace.activeStage;
    final clip = workspace.clipOn(stage);
    if (clip == null) return;
    _open = true;
    if (_running.contains(clip.clipId)) return _notify();
    _running.add(clip.clipId);
    _notify();
    try {
      if (!_loadedChoices) await refreshProfiles();
      final choice = _selected;
      ProfileBundle? bundle;
      var patches = PatchSet.empty;
      var adapters = AdapterSet.empty;
      _profileError = null;
      if (choice != null) {
        try {
          bundle = _bundles[choice.key] ??= await loadBundle(choice.path);
          patches = loadPatches(bundle.patchFiles, headsFor(pack));
          adapters =
              loadAdapters(bundle.adapterFiles, pack, pack.adapters);
        } on AnalysisError catch (e) {
          _profileError = e;
        }
      }
      final player = workspace.player(stage);
      final fps = await player.frameRate();
      final source = ClipSource(
        clipId: clip.clipId,
        path: clip.path,
        durationMs: player.duration.inMilliseconds,
        fps: fps,
      );
      final reference = bundle == null
          ? const <String, double>{}
          : {
              for (final e in bundle.profile.metrics.entries)
                e.key: e.value.center,
            };
      final detail = await run(source, patches.applied, reference);
      final outcome = detail.outcome;
      ComparisonOutcome? comparison;
      String? focus;
      bool? usable;
      if (outcome is AnalysisSuccess && bundle != null) {
        // Adapters run locally: no LLM call at inference.
        final pre = adapterInputs(outcome.vector,
            implementConfidence: detail.implementConfidence, fps: fps);
        usable = adapters.adapters[usableAdapter]
            ?.decide(pre)
            .values
            .every((v) => v);
        comparison = compare(
          vector: outcome.vector,
          profile: bundle.profile,
          resultId: _uuid.v4(),
          appliedPatches: patches.appliedNames,
          rejectedPatches: [
            for (final e in patches.rejected) '${e.details['file']}',
          ],
          metricLabel: metricLabel,
          phaseLabel: phaseLabel,
          extraWarnings: [
            if (usable == false) 'This clip is below the usable threshold.',
            ...adapters.rejected,
          ],
        );
        if (comparison is ComparisonSuccess) {
          final scorer = adapters.adapters[priorityAdapter];
          if (scorer != null) {
            focus = scorer.top(adapterInputs(outcome.vector,
                implementConfidence: detail.implementConfidence,
                comparison: comparison.result,
                fps: fps));
            // A compiled preference must not bypass measurement confidence.
            final keys = pack.attributeMetrics[focus] ?? const <String>[];
            final reliable = comparison.result.rankedDeltas
                .where((d) => d.confidence >= lowConfidence)
                .map((d) => d.metricKey).toSet();
            if (keys.isEmpty || !keys.every(reliable.contains)) focus = null;
          }
          await saveResult?.call(comparison.result);
        }
      }
      _results[clip.clipId] = ClipAnalysis(
          outcome: outcome,
          comparison: comparison,
          profileKey: choice?.key,
          focus: focus,
          usable: usable,
          strokes: detail.strokes,
          usableStrokes: detail.usableStrokes);
      _fps[clip.clipId] = fps;
    } finally {
      _running.remove(clip.clipId);
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
