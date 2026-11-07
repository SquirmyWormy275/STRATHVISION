import 'dart:isolate';
import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../profiles/profile_package.dart';
import '../vision/athlete.dart';
import '../vision/athlete_choices.dart';
import '../vision/pose_service.dart';
import '../workspace/workspace_controller.dart';

typedef AnalysisRunner = Future<AnalysisDetail> Function(ClipSource clip,
    List<SpecialistPatch> patches, Map<String, double> reference);
AnalysisRunner visionRunner(AnalysisPack pack, {PoseService? poses, AthleteChoices? athletes}) =>
    (clip, patches, reference) async {
      final found = await (poses ?? PoseService.instance)
          .trackAthlete(clip, target: athletes?.targetFor(clip.clipId));
      athletes?.record(clip, found);
      return analyzeWithTrack(pack, clip, found.track, patches: patches, reference: reference);
    };
Future<AnalysisDetail> analyzeWithTrack(AnalysisPack pack, ClipSource clip, PoseTrack track,
    {List<SpecialistPatch> patches = const [], Map<String, double> reference = const {}}) {
  if (track.frames.isEmpty) {
    return Future.value(AnalysisDetail(
        AnalysisFailure(AnalysisError(ErrorCode.lowPoseConfidence,
            'No person could be found in this clip.', {'pose_frames': 0})), const {}));
  }
  return Isolate.run(() => AnalysisEngine(pack: pack, pose: PrecomputedPoseEstimator(track),
      implement: const GripImplementTracker(), phases: const EventPhaseDetector(),
      heads: applyPatches(headsFor(pack), patches), perStroke: true)
      .analyzeDetailed(clip, reference: reference));
}
/// Synthetic test runner; never a fallback for failed production inference.
AnalysisRunner isolateRunner(AnalysisPack pack) =>
    (clip, patches, reference) => Isolate.run(() => AnalysisEngine(
      pack: pack, heads: applyPatches(headsFor(pack), patches))
      .analyzeDetailed(clip, reference: reference));

class ProfileChoice {
  const ProfileChoice({required this.profileId, required this.version,
    required this.label, required this.path});
  final String profileId, label, path;
  final int version;
  String get key => '$profileId@$version';
}
typedef ProfileChoices = Future<List<ProfileChoice>> Function();
typedef BundleLoader = Future<ProfileBundle> Function(String path);
typedef ResultSaver = Future<void> Function(ComparisonResult result);
class ClipAnalysis {
  const ClipAnalysis({required this.outcome, this.comparison, this.profileKey,
    this.focus, this.usable, this.strokes = 0, this.usableStrokes = 0});
  final AnalysisOutcome outcome;
  final int strokes, usableStrokes;
  final ComparisonOutcome? comparison;
  final String? profileKey, focus;
  final bool? usable;
}
bool suggestHigherFrameRate(ClipAnalysis a, double fps) =>
    fps < 50 && a.strokes >= 3 && a.usableStrokes < 0.6 * a.strokes;
const usableAdapter = 'usable_footage';
const priorityAdapter = 'priority_scorer';

/// Optional analysis, independent of the video review controls.
class AnalysisController extends ChangeNotifier {
  AnalysisController({required this.workspace, required this.pack, required this.run,
    this.listProfiles, this.loadBundle = readProfileBundle, this.saveResult,
    this.metricLabel, this.phaseLabel, this.athletes,
    this.preferredProfileKey, this.restoreProfileSelection = false});
  final String? preferredProfileKey;
  final bool restoreProfileSelection;
  bool _selectionEstablished = false;
  String? _requestedKey;
  bool get profileSelectionEstablished => _selectionEstablished || restoreProfileSelection;
  String? get requestedProfileKey => _selectionEstablished ? _requestedKey : preferredProfileKey;
  String? get missingProfileKey => requestedProfileKey != null && _loadedChoices &&
      !_choices.any((c) => c.key == requestedProfileKey) ? requestedProfileKey : null;
  void openPanel() { _open = true; _notify(); }
  final WorkspaceController workspace;
  final AnalysisPack pack;
  final AnalysisRunner run;
  final ProfileChoices? listProfiles;
  final BundleLoader loadBundle;
  final ResultSaver? saveResult;
  final String Function(String key)? metricLabel;
  final String Function(String id)? phaseLabel;
  final AthleteChoices? athletes;
  static const _uuid = Uuid();
  final Map<String, ClipAnalysis> _results = {};
  final Map<String, double> _fps = {};
  final Set<String> _running = {};
  final Map<String, ProfileBundle> _bundles = {};
  List<ProfileChoice> _choices = const [];
  ProfileChoice? _selected;
  AnalysisError? _profileError;
  bool _open = false, _loadedChoices = false, _disposed = false;
  bool get panelOpen => _open;
  List<ProfileChoice> get choices => _choices;
  ProfileChoice? get selectedProfile => _selected;
  AnalysisError? get profileError => _profileError;
  String? get clipId => workspace.clipOn(workspace.activeStage)?.clipId;
  ClipAnalysis? get analysis {
    final cached = _results[clipId];
    return cached?.profileKey == _selected?.key ? cached : null;
  }
  AnalysisOutcome? get result => analysis?.outcome;
  ComparisonOutcome? get comparison => analysis?.comparison;
  bool get running => clipId != null && _running.contains(clipId);
  double get fps => _fps[clipId] ?? 30;
  Future<void> chooseAthlete(AthleteTarget? target) async {
    final id = clipId;
    if (id == null) return;
    await workspace.setAthlete(id, target?.toJson()); await analyze();
  }
  void closePanel() { _open = false; _notify(); }
  /// A new review may default to newest; a restored review never silently upgrades.
  Future<void> refreshProfiles() async {
    final list = listProfiles;
    if (list == null) return;
    _choices = await list(); _loadedChoices = true;
    if (profileSelectionEstablished) {
      _selected = _choices.where((c) => c.key == requestedProfileKey).firstOrNull;
    } else {
      _selected = _choices.firstOrNull;
      _requestedKey = _selected?.key; _selectionEstablished = true;
    }
    _notify();
  }
  Future<void> selectProfile(ProfileChoice? choice) async {
    final hadResult = _results.containsKey(clipId);
    _selected = choice; _requestedKey = choice?.key;
    _selectionEstablished = true; _profileError = null; _notify();
    if (hadResult) await analyze();
  }
  Future<void> analyze() async {
    final stage = workspace.activeStage;
    final clip = workspace.clipOn(stage);
    if (clip == null) return;
    _open = true;
    if (_running.contains(clip.clipId)) return _notify();
    _running.add(clip.clipId); _notify();
    try {
      if (!_loadedChoices) await refreshProfiles();
      if (missingProfileKey != null) {
        _profileError = AnalysisError(ErrorCode.profileNotReady,
            'The saved profile version is unavailable. Select a profile or choose measurements only.', {});
        return;
      }
      final choice = _selected;
      ProfileBundle? bundle;
      var patches = PatchSet.empty;
      var adapters = AdapterSet.empty;
      _profileError = null;
      if (choice != null) {
        try {
          bundle = _bundles[choice.key] ??= await loadBundle(choice.path);
          patches = loadPatches(bundle.patchFiles, headsFor(pack));
          adapters = loadAdapters(bundle.adapterFiles, pack, pack.adapters);
        } on AnalysisError catch (e) { _profileError = e; }
      }
      final player = workspace.player(stage);
      final fps = await player.frameRate();
      final source = ClipSource(clipId: clip.clipId, path: clip.path,
        durationMs: player.duration.inMilliseconds, fps: fps);
      final reference = bundle == null ? const <String, double>{} : {
        for (final e in bundle.profile.metrics.entries) e.key: e.value.center,
      };
      final detail = await run(source, patches.applied, reference);
      if (_disposed) return;
      final outcome = detail.outcome;
      ComparisonOutcome? comparison;
      String? focus;
      bool? usable;
      if (outcome is AnalysisSuccess && bundle != null) {
        final pre = adapterInputs(outcome.vector,
            implementConfidence: detail.implementConfidence, fps: fps);
        usable = adapters.adapters[usableAdapter]?.decide(pre).values.every((v) => v);
        comparison = compare(vector: outcome.vector, profile: bundle.profile,
          resultId: _uuid.v4(), appliedPatches: patches.appliedNames,
          rejectedPatches: [for (final e in patches.rejected) '${e.details['file']}'],
          metricLabel: metricLabel, phaseLabel: phaseLabel,
          extraWarnings: [if (usable == false) 'This clip is below the usable threshold.', ...adapters.rejected]);
        if (comparison is ComparisonSuccess) {
          final scorer = adapters.adapters[priorityAdapter];
          if (scorer != null) {
            focus = scorer.top(adapterInputs(outcome.vector,
                implementConfidence: detail.implementConfidence,
                comparison: comparison.result, fps: fps));
            final keys = pack.attributeMetrics[focus] ?? const <String>[];
            final reliable = comparison.result.rankedDeltas.where((d) => d.confidence >= lowConfidence)
                .map((d) => d.metricKey).toSet();
            if (keys.isEmpty || !keys.every(reliable.contains)) focus = null;
          }
          await saveResult?.call(comparison.result);
        }
      }
      _results[clip.clipId] = ClipAnalysis(outcome: outcome, comparison: comparison,
        profileKey: choice?.key, focus: focus, usable: usable,
        strokes: detail.strokes, usableStrokes: detail.usableStrokes);
      _fps[clip.clipId] = fps;
    } finally { _running.remove(clip.clipId); _notify(); }
  }
  void _notify() { if (!_disposed) notifyListeners(); }
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
