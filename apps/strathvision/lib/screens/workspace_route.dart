import 'package:flutter/material.dart';

import '../analysis/analysis_controller.dart';
import '../vision/athlete.dart';
import '../vision/athlete_choices.dart';
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
    required this.pack,
    this.playerFactory = defaultStagePlayer,
    this.pickClip = pickClipFile,
    this.analysisRunner,
  });

  final AppDatabase db;
  final Project project;

  /// Active pack/event: attribute chips, analysis, compatible profiles.
  final PackInfo pack;
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
    attributes: widget.pack.topAttributes,
  );
  late final AthleteChoices _athletes = AthleteChoices(targetFor: (id) {
    final j = _controller.athleteFor(id);
    return j == null ? null : AthleteTarget.fromJson(j);
  });
  late final AnalysisController _analysis = AnalysisController(
    workspace: _controller,
    pack: widget.pack.analysisPack,
    run: widget.analysisRunner ?? visionRunner(widget.pack.analysisPack, athletes: _athletes),
    athletes: widget.analysisRunner == null ? _athletes : null,
    listProfiles: () => compatibleProfiles(widget.db, widget.pack),
    metricLabel: widget.pack.metricLabel,
    phaseLabel: (id) => widget.pack.phaseLabel(id).toLowerCase(),
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
    _athletes.dispose();
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
        pack: widget.pack,
      );
}
