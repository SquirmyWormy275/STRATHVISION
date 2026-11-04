import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../profiles/profile_package.dart';
import '../workspace/workspace_controller.dart';

/// Runs the engine for one clip with the given specialist patches applied.
typedef AnalysisRunner = Future<AnalysisOutcome> Function(
    ClipSource clip, List<SpecialistPatch> patches);

/// Runs the engine off the UI isolate so scrubbing stays at 60 fps.
AnalysisRunner isolateRunner(AnalysisPack pack) => (clip, patches) =>
    Isolate.run(() => AnalysisEngine(
            pack: pack, heads: applyPatches(defaultHeads(), patches))
        .analyze(clip));

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
  const ClipAnalysis({required this.outcome, this.comparison, this.profileKey});
  final AnalysisOutcome outcome;
  final ComparisonOutcome? comparison;
  final String? profileKey;
}

/// Analyze state for the open workspace. The workspace keeps working when
/// analysis fails or is never used.
class AnalysisController extends ChangeNotifier {
  AnalysisController({
    required this.workspace,
    required this.run,
    this.listProfiles,
    this.loadBundle = readProfileBundle,
    this.saveResult,
  });

  final WorkspaceController workspace;
  final AnalysisRunner run;
  final ProfileChoices? listProfiles;
  final BundleLoader loadBundle;
  final ResultSaver? saveResult;
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
      _profileError = null;
      if (choice != null) {
        try {
          bundle = _bundles[choice.key] ??= await loadBundle(choice.path);
          patches = loadPatches(bundle.patchFiles, defaultHeads());
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
      final outcome = await run(source, patches.applied);
      ComparisonOutcome? comparison;
      if (outcome is AnalysisSuccess && bundle != null) {
        comparison = compare(
          vector: outcome.vector,
          profile: bundle.profile,
          resultId: _uuid.v4(),
          appliedPatches: patches.appliedNames,
          rejectedPatches: [
            for (final e in patches.rejected) '${e.details['file']}',
          ],
        );
        if (comparison is ComparisonSuccess) {
          await saveResult?.call(comparison.result);
        }
      }
      _results[clip.clipId] = ClipAnalysis(
          outcome: outcome, comparison: comparison, profileKey: choice?.key);
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
