import 'package:flutter/material.dart';

import '../analysis/analysis_controller.dart';
import '../data/database.dart';
import '../packs/placeholder_pack.dart';
import '../workspace/project.dart';
import '../workspace/stage_player.dart';
import '../workspace/workspace_controller.dart';
import 'workspace_screen.dart';

/// Ready profiles for the active pack's event, newest first.
Future<List<ProfileChoice>> compatibleProfiles(
    AppDatabase db, PackInfo pack) async {
  final a = pack.analysisPack;
  return [
    for (final r in await db.allProfiles())
      if (r.packId == a.packId &&
          r.eventId == a.eventId &&
          r.minClipsMet &&
          r.selfConsistencyPassed)
        ProfileChoice(
          profileId: r.profileId,
          version: r.version,
          label: '${r.coachName} · v${r.version}',
          path: r.sourcePath,
        ),
  ];
}

typedef StagePlayerFactory = StagePlayer Function();

StagePlayer defaultStagePlayer() => MediaKitStagePlayer();

/// Owns the two stage players and the controller for one open project.
class WorkspaceRoute extends StatefulWidget {
  const WorkspaceRoute({
    super.key,
    required this.db,
    required this.project,
    this.playerFactory = defaultStagePlayer,
    this.pickClip = pickClipFile,
    this.analysisRunner,
  });

  final AppDatabase db;
  final Project project;
  final StagePlayerFactory playerFactory;
  final ClipPathPicker pickClip;

  /// Runs analysis; defaults to the engine on a background isolate.
  final AnalysisRunner? analysisRunner;

  @override
  State<WorkspaceRoute> createState() => _WorkspaceRouteState();
}

class _WorkspaceRouteState extends State<WorkspaceRoute> {
  late final StagePlayer _a = widget.playerFactory();
  late final StagePlayer _b = widget.playerFactory();
  late final WorkspaceController _controller = WorkspaceController(
    project: widget.project,
    store: widget.db,
    playerA: _a,
    playerB: _b,
    attributes: placeholderPack.topAttributes,
  );
  late final AnalysisController _analysis = AnalysisController(
    workspace: _controller,
    run: widget.analysisRunner ?? isolateRunner(placeholderPack.analysisPack),
    listProfiles: () => compatibleProfiles(widget.db, placeholderPack),
    saveResult: (r) =>
        widget.db.saveComparison(projectId: widget.project.projectId, result: r),
  );

  @override
  void initState() {
    super.initState();
    _controller.restore();
  }

  @override
  void dispose() {
    _analysis.dispose();
    _controller.pause();
    _controller.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WorkspaceScreen(
        controller: _controller,
        pickClip: widget.pickClip,
        analysis: _analysis,
      );
}
