import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/workspace_controller.dart';

import 'support/fake_stage_player.dart';

Duration d(int ms) => Duration(milliseconds: ms);

class MemoryStore implements ProjectStore {
  Project? saved;
  int saves = 0;
  @override
  Future<void> saveProject(Project project) async {
    saved = project;
    saves++;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeStagePlayer a, b;
  late MemoryStore store;
  late WorkspaceController c;

  WorkspaceController make(Project p, {ProjectStore? s}) => WorkspaceController(
        project: p,
        store: s ?? store,
        playerA: a,
        playerB: b,
        attributes: const ['Timing', 'Path'],
        clock: () => DateTime.utc(2026, 11, 4),
      );

  setUp(() {
    a = FakeStagePlayer();
    b = FakeStagePlayer(clipDuration: const Duration(seconds: 25));
    store = MemoryStore();
    c = make(const Project(projectId: 'p1', name: 'Test'));
  });
  tearDown(() => c.dispose());

  Future<void> loadBoth() async {
    await c.loadClip(Stage.a, '/clips/a.mp4');
    await c.loadClip(Stage.b, '/clips/b.mp4');
  }

  /// Align: A at 2.000 s, B at 3.250 s, then Sync.
  Future<void> loadAndSync() async {
    await loadBoth();
    await c.scrub(Stage.a, d(2000));
    await c.scrub(Stage.b, d(3250));
    await c.setSyncPoint();
  }

  group('load + sync', () {
    test('loading clips puts them on stages and records them in the project',
        () async {
      await loadBoth();
      expect(a.openedPath, '/clips/a.mp4');
      expect(b.openedPath, '/clips/b.mp4');
      expect(c.project.clips.map((x) => x.displayName), ['a', 'b']);
      expect(c.clipOn(Stage.a)!.path, '/clips/a.mp4');
      expect(c.hasBothClips, isTrue);
    });

    test('reloading the same file reuses its clip id', () async {
      await c.loadClip(Stage.a, '/clips/a.mp4');
      await c.loadClip(Stage.b, '/clips/a.mp4');
      expect(c.project.clips, hasLength(1));
    });

    test('Set Sync Point records offset_ms = B - A and locks', () async {
      await loadAndSync();
      expect(c.sync!.offsetMs, 1250);
      expect(c.locked, isTrue);
      expect(store.saved!.syncRelationships.single.offsetMs, 1250);
    });

    test('setting sync again replaces the relationship for the pair', () async {
      await loadAndSync();
      await c.setLocked(false);
      await c.scrub(Stage.b, d(5000));
      await c.setSyncPoint();
      expect(c.project.syncRelationships, hasLength(1));
      expect(c.sync!.offsetMs, 3000);
    });

    test('Clear Sync removes the relationship and unlocks', () async {
      await loadAndSync();
      await c.clearSync();
      expect(c.sync, isNull);
      expect(c.locked, isFalse);
      expect(c.project.syncRelationships, isEmpty);
    });

    test('sync needs both stages loaded', () async {
      await c.loadClip(Stage.a, '/clips/a.mp4');
      await c.setSyncPoint();
      expect(c.sync, isNull);
    });
  });

  group('scrub', () {
    test('independent scrub moves only that stage', () async {
      await loadBoth();
      await c.scrub(Stage.a, d(4000));
      await c.scrub(Stage.b, d(1000));
      expect(a.position, d(4000));
      expect(b.position, d(1000));
    });

    test('locked scrub of A moves B to A + offset', () async {
      await loadAndSync();
      await c.scrub(Stage.a, d(6000));
      expect(b.position, d(7250));
    });

    test('locked scrub of B moves A to B - offset', () async {
      await loadAndSync();
      await c.scrub(Stage.b, d(9000));
      expect(a.position, d(7750));
      expect(b.position, d(9000));
    });

    test('locked scrub aligns B from the seek target, not a stale position',
        () async {
      a = FakeStagePlayer(lagSeeks: true);
      b = FakeStagePlayer(lagSeeks: true);
      final lag = make(const Project(projectId: 'lag', name: 'Lag'));
      await lag.loadClip(Stage.a, '/clips/a.mp4');
      await lag.loadClip(Stage.b, '/clips/b.mp4');
      await lag.scrub(Stage.b, d(1000));
      b.settle();
      await lag.setSyncPoint();
      expect(lag.sync!.offsetMs, 1000);

      await lag.scrub(Stage.a, d(4000));
      a.settle();
      b.settle();
      expect(a.position, d(4000));
      expect(b.position, d(5000));
      lag.dispose();
    });

    test('scrub is clamped to the clip', () async {
      await loadBoth();
      await c.scrub(Stage.a, const Duration(seconds: 99));
      expect(a.position, a.clipDuration);
    });
  });

  group('locked playback', () {
    test('plays both at 0.25x and stays on the offset', () async {
      await loadAndSync();
      await c.setRate(0.25);
      await c.play();
      expect(a.playing && b.playing, isTrue);
      expect(a.rate, 0.25);
      expect(b.rate, 0.25);

      a.advance(const Duration(seconds: 4));
      b.advance(const Duration(seconds: 4));
      expect(a.position, d(3000));
      expect(b.position - a.position, d(1250));
      await c.pause();
    });

    test('drift under 40 ms is left alone', () async {
      await loadAndSync();
      await c.play();
      b.jumpTo(b.position + d(30));
      final seeks = b.log.where((l) => l.startsWith('seek')).length;
      await c.correctDrift();
      expect(b.log.where((l) => l.startsWith('seek')).length, seeks);
      expect(b.rate, 1.0);
      await c.pause();
    });

    test('moderate drift nudges B speed instead of seeking', () async {
      await loadAndSync();
      await c.setRate(0.25);
      await c.play();
      final seeks = b.log.where((l) => l.startsWith('seek')).length;

      b.jumpTo(a.position + d(1250 + 100)); // B 100 ms ahead
      await c.correctDrift();
      expect(b.log.where((l) => l.startsWith('seek')).length, seeks);
      expect(b.rate, lessThan(0.25));
      expect(b.rate, greaterThanOrEqualTo(0.125));
      expect(c.bRateNudged, isTrue);

      b.jumpTo(a.position + d(1250 - 100)); // B 100 ms behind
      await c.correctDrift();
      expect(b.rate, greaterThan(0.25));

      b.jumpTo(a.position + d(1250)); // back on the offset
      await c.correctDrift();
      expect(b.rate, 0.25);
      expect(c.bRateNudged, isFalse);
      await c.pause();
    });

    test('nudged speed closes the gap during playback', () async {
      await loadAndSync();
      await c.setRate(0.25);
      await c.play();
      b.jumpTo(a.position + d(1250 + 120));
      for (var i = 0; i < 12; i++) {
        await c.correctDrift();
        a.advance(d(100));
        b.advance(d(100));
      }
      final drift = (b.position - a.position - d(1250)).abs();
      expect(drift, lessThanOrEqualTo(c.driftTolerance));
      await c.pause();
    });

    test('large drift is fixed with a hard seek', () async {
      await loadAndSync();
      await c.play();
      b.jumpTo(a.position + d(1250 + 400));
      await c.correctDrift();
      expect(b.position - a.position, d(1250));
      expect(b.rate, 1.0);
      await c.pause();
    });

    test('pausing restores B to the playback rate', () async {
      await loadAndSync();
      await c.setRate(0.5);
      await c.play();
      b.jumpTo(a.position + d(1250 + 100));
      await c.correctDrift();
      expect(b.rate, isNot(0.5));
      await c.pause();
      expect(b.rate, 0.5);
      expect(b.position - a.position, d(1250));
    });

    test('independent play plays only the active stage', () async {
      await loadBoth();
      c.setActiveStage(Stage.b);
      await c.play();
      expect(b.playing, isTrue);
      expect(a.playing, isFalse);
      await c.pause();
    });

    test('rate persists in the project', () async {
      await loadBoth();
      await c.setRate(0.25);
      expect(store.saved!.workspace.playbackRate, 0.25);
    });
  });

  group('frame step', () {
    test('locked pair steps together and keeps the offset', () async {
      await loadAndSync();
      await c.stepFrame(forward: true);
      expect(a.position, d(2000) + FakeStagePlayer.frame);
      expect(b.position - a.position, d(1250));

      await c.stepFrame(forward: false);
      await c.stepFrame(forward: false);
      expect(a.position, d(2000) - FakeStagePlayer.frame);
      expect(b.position - a.position, d(1250));
    });

    test('stepping pauses locked playback', () async {
      await loadAndSync();
      await c.play();
      await c.stepFrame(forward: true);
      expect(a.playing || b.playing, isFalse);
    });

    test('independent step moves only the active stage', () async {
      await loadBoth();
      await c.scrub(Stage.b, d(1000));
      await c.stepFrame(forward: true);
      expect(b.position, d(1000) + FakeStagePlayer.frame);
      expect(a.position, Duration.zero);
    });
  });

  group('mirror + swap', () {
    test('mirror B toggles and persists without breaking sync', () async {
      await loadAndSync();
      await c.toggleMirrorB();
      expect(c.mirrorB, isTrue);
      expect(store.saved!.workspace.mirrorB, isTrue);
      expect(c.locked, isTrue);
      expect(c.sync!.offsetMs, 1250);
    });

    test('swap reverses the pair and negates the offset', () async {
      await loadAndSync();
      await c.swapStages();
      expect(c.clipOn(Stage.a)!.displayName, 'b');
      expect(c.clipOn(Stage.b)!.displayName, 'a');
      expect(c.sync!.offsetMs, -1250);
      expect(c.locked, isTrue);
      expect(b.position - a.position, -d(1250));
    });
  });

  group('marks, annotations, undo', () {
    test('red/green stores attribute, clip, and time without moving playhead',
        () async {
      await loadBoth();
      await c.scrub(Stage.a, d(1500));
      c.selectAttribute('Path');
      await c.mark(MarkLabel.green);
      final m = store.saved!.marks.single;
      expect(m.attribute, 'Path');
      expect(m.label, MarkLabel.green);
      expect(m.clipId, c.clipOn(Stage.a)!.clipId);
      expect(m.timeMs, 1500);
      expect(m.strokeIndex, isNull);
      expect(m.author, MarkAuthor.athlete);
      expect(a.position, d(1500));
    });

    test('marks need an attribute and a loaded clip', () async {
      final bare = WorkspaceController(
          project: const Project(projectId: 'x', name: 'x'),
          store: store,
          playerA: FakeStagePlayer(),
          playerB: FakeStagePlayer());
      await bare.mark(MarkLabel.red);
      expect(bare.project.marks, isEmpty);
      bare.dispose();
    });

    test('annotate stores a note on the active stage', () async {
      await loadBoth();
      c.setActiveStage(Stage.b);
      await c.scrub(Stage.b, d(800));
      await c.annotate('  keep the hips quiet  ');
      final n = store.saved!.annotations.single;
      expect(n.text, 'keep the hips quiet');
      expect(n.clipId, c.clipOn(Stage.b)!.clipId);
      expect(n.timeMs, 800);
    });

    test('one-tap undo removes the last mark, then the sync', () async {
      await loadAndSync();
      await c.mark(MarkLabel.red);
      expect(c.project.marks, hasLength(1));
      await c.undo();
      expect(c.project.marks, isEmpty);
      expect(store.saved!.marks, isEmpty);
      await c.undo();
      expect(c.sync, isNull);
    });

    test('undoing a clip load restores the previous stage', () async {
      await loadBoth();
      await c.loadClip(Stage.b, '/clips/c.mp4');
      expect(b.openedPath, '/clips/c.mp4');
      await c.undo();
      expect(c.clipOn(Stage.b)!.path, '/clips/b.mp4');
      expect(b.openedPath, '/clips/b.mp4');
    });
  });

  group('persistence', () {
    test('project JSON uses the INTERFACES.md keys and round-trips', () async {
      await loadAndSync();
      await c.mark(MarkLabel.green);
      await c.annotate('note');
      final json = c.project.toJson();
      expect(json.keys, containsAll([
        'project_id', 'name', 'clips', 'sync_relationships', 'annotations',
        'linked_profile_ids', 'marks', 'workspace'
      ]));
      final rel = (json['sync_relationships'] as List).single as Map;
      expect(rel.keys,
          unorderedEquals(['clip_a_id', 'clip_b_id', 'offset_ms', 'created_at']));
      final again = Project.fromJson(json).toJson();
      expect(again.toString(), json.toString());
    });

    test('re-opening a project from the database restores the synced pair',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final first = make(const Project(projectId: 'p2', name: 'Reopen'), s: db);
      await first.loadClip(Stage.a, '/clips/a.mp4');
      await first.loadClip(Stage.b, '/clips/b.mp4');
      await first.scrub(Stage.a, d(2000));
      await first.scrub(Stage.b, d(3250));
      await first.setSyncPoint();
      await first.setRate(0.25);
      await first.mark(MarkLabel.green);
      first.dispose();

      final loaded = await db.loadProject('p2');
      a = FakeStagePlayer();
      b = FakeStagePlayer(clipDuration: const Duration(seconds: 25));
      final second = make(loaded!, s: db);
      await second.restore();

      expect(a.openedPath, '/clips/a.mp4');
      expect(b.openedPath, '/clips/b.mp4');
      expect(second.locked, isTrue);
      expect(second.sync!.offsetMs, 1250);
      expect(b.position - a.position, d(1250));
      expect(a.rate, 0.25);
      expect(second.project.marks.single.label, MarkLabel.green);

      await second.scrub(Stage.a, d(5000));
      expect(b.position, d(6250));
      second.dispose();
      await db.close();
    });
  });
}
