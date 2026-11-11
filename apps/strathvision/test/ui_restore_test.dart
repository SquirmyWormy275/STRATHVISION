import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/analysis/analysis_controller.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';
import 'support/fake_stage_player.dart';

class _Store implements ProjectStore {
  bool failNext = false;
  Project? saved;
  @override
  Future<void> saveProject(Project project) async {
    if (failNext) {
      failNext = false;
      throw StateError('Simulated storage failure');
    }
    saved = project;
  }
}

void main() {
  late FakeStagePlayer a, b;
  late _Store store;
  late WorkspaceController workspace;
  setUp(() {
    a = FakeStagePlayer();
    b = FakeStagePlayer();
    store = _Store();
    workspace = WorkspaceController(
      project: const Project(projectId: 'review', name: 'Review'),
      store: store,
      playerA: a,
      playerB: b,
      attributes: placeholderPack.topAttributes,
    );
  });
  tearDown(() async {
    workspace.dispose();
    await a.dispose();
    await b.dispose();
  });
  const old = ProfileChoice(profileId: 'coach', version: 1, label: 'One', path: '/one');
  const newer = ProfileChoice(profileId: 'coach', version: 2, label: 'Two', path: '/two');
  Future<AnalysisDetail> empty(ClipSource clip, List<SpecialistPatch> patches, Map<String, double> reference) async {
    return AnalysisDetail(
      AnalysisFailure(AnalysisError(ErrorCode.lowPoseConfidence, 'Test-only failure', const {})),
      const {},
    );
  }

  test('restored profile version does not silently upgrade', () async {
    final analysis = AnalysisController(
      workspace: workspace,
      pack: placeholderPack.analysisPack,
      run: empty,
      listProfiles: () async => [newer, old],
      preferredProfileKey: old.key,
      restoreProfileSelection: true,
    );
    addTearDown(analysis.dispose);
    await analysis.refreshProfiles();
    expect(analysis.selectedProfile?.key, old.key);
    await analysis.selectProfile(null);
    await analysis.refreshProfiles();
    expect(analysis.selectedProfile, isNull);
    expect(analysis.requestedProfileKey, isNull);
    expect(analysis.profileSelectionEstablished, isTrue);
  });

  test('no compatible profile does not pin measurements-only', () async {
    var installed = <ProfileChoice>[];
    final analysis = AnalysisController(
      workspace: workspace,
      pack: placeholderPack.analysisPack,
      run: empty,
      listProfiles: () async => installed,
    );
    addTearDown(analysis.dispose);
    await analysis.refreshProfiles();
    expect(analysis.selectedProfile, isNull);
    expect(analysis.profileSelectionEstablished, isFalse);
    installed = [newer];
    await analysis.refreshProfiles();
    expect(analysis.selectedProfile?.key, newer.key);
    expect(analysis.profileSelectionEstablished, isTrue);
  });

  test('missing exact version blocks comparison until explicit choice', () async {
    await workspace.loadClip(Stage.a, '/fixture/clip.mp4');
    var runs = 0;
    final analysis = AnalysisController(
      workspace: workspace,
      pack: placeholderPack.analysisPack,
      run: (clip, patches, reference) async {
        runs++;
        return empty(clip, patches, reference);
      },
      listProfiles: () async => [newer],
      preferredProfileKey: old.key,
      restoreProfileSelection: true,
    );
    addTearDown(analysis.dispose);
    await analysis.analyze();
    expect(runs, 0);
    expect(analysis.missingProfileKey, old.key);
    expect(analysis.profileError, isNotNull);
    expect(analysis.running, isFalse);
    await analysis.selectProfile(null);
    await analysis.analyze();
    expect(runs, 1);
    expect(analysis.missingProfileKey, isNull);
    expect(analysis.comparison, isNull);
  });

  test('failed save can flush without losing later edits', () async {
    await workspace.loadClip(Stage.a, '/fixture/clip.mp4');
    store.failNext = true;
    await expectLater(workspace.annotate('First note'), throwsStateError);
    await workspace.annotate('Second note');
    await workspace.flush();
    expect(store.saved!.annotations.map((a) => a.text), ['First note', 'Second note']);
  });

  test('single view and undo retain pair, offset and human marks', () async {
    await workspace.loadClip(Stage.a, '/fixture/current.mp4');
    await workspace.loadClip(Stage.b, '/fixture/reference.mp4');
    b.jumpTo(const Duration(milliseconds: 1500));
    await workspace.setSyncPoint();
    await workspace.mark(MarkLabel.green);
    await workspace.clearStage(Stage.b);
    expect(workspace.hasBothClips, isFalse);
    expect(workspace.project.marks, hasLength(1));
    expect(workspace.project.clips, hasLength(2));
    await workspace.undo();
    expect(workspace.hasBothClips, isTrue);
    expect(workspace.locked, isTrue);
    expect(workspace.sync!.offsetMs, 1500);
    expect(workspace.project.marks, hasLength(1));
  });
}
