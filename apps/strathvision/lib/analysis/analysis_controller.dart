import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';

import '../workspace/workspace_controller.dart';

typedef AnalysisRunner = Future<AnalysisOutcome> Function(ClipSource clip);

/// Runs the engine off the UI isolate so scrubbing stays at 60 fps.
AnalysisRunner isolateRunner(AnalysisPack pack) =>
    (clip) => Isolate.run(() => AnalysisEngine(pack: pack).analyze(clip));

/// Analyze state for the open workspace. The workspace keeps working when
/// analysis fails or is never used.
class AnalysisController extends ChangeNotifier {
  AnalysisController({required this.workspace, required this.run});

  final WorkspaceController workspace;
  final AnalysisRunner run;

  final Map<String, AnalysisOutcome> _results = {};
  final Map<String, double> _fps = {};
  final Set<String> _running = {};
  bool _open = false;
  bool _disposed = false;

  bool get panelOpen => _open;

  /// Clip on the active stage, if any.
  String? get clipId => workspace.clipOn(workspace.activeStage)?.clipId;

  AnalysisOutcome? get result => clipId == null ? null : _results[clipId];
  bool get running => clipId != null && _running.contains(clipId);

  /// Frame rate the current result was computed at (for frame → time).
  double get fps => _fps[clipId] ?? 30;

  void closePanel() {
    _open = false;
    _notify();
  }

  /// Analyze the clip on the active stage and open the results panel.
  Future<void> analyze() async {
    final stage = workspace.activeStage;
    final clip = workspace.clipOn(stage);
    if (clip == null) return;
    _open = true;
    if (_running.contains(clip.clipId)) return _notify();
    _running.add(clip.clipId);
    _notify();
    final player = workspace.player(stage);
    final fps = await player.frameRate();
    final source = ClipSource(
      clipId: clip.clipId,
      path: clip.path,
      durationMs: player.duration.inMilliseconds,
      fps: fps,
    );
    try {
      _results[clip.clipId] = await run(source);
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
