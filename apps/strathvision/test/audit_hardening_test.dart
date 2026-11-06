import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/builder_controller.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/inbox.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/profiles/profile_store.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/pose_service.dart';
import 'package:strathvision/vision/training_track.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workbench/workbench_controller.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv-audit-');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  Map<String, Object?> manifest() =>
      jsonDecode(File('test/fixtures/dummy_profile.json').readAsStringSync())
          as Map<String, Object?>;
  String zip(Map<String, Object?> m, {List<Map<String, Object?>>? marks}) {
    final a = Archive()..add(ArchiveFile.string('profile.json', jsonEncode(m)));
    if (marks != null) a.add(ArchiveFile.string(marksFile, jsonEncode(marks)));
    final f = File('${dir.path}/input.zip')
      ..writeAsBytesSync(ZipEncoder().encode(a));
    return f.path;
  }

  test('generated profile versions reject collision without replacing bytes', () async {
    final profile = Profile.fromJson(manifest());
    final directory = Directory('${dir.path}/generated');
    final first = await storeNewProfileVersion(db, profile, directory);
    final bytes = File(first).readAsBytesSync();
    final changed = Profile.fromJson({...manifest(), 'coach_name': 'Different'});
    await expectLater(storeNewProfileVersion(db, changed, directory), throwsStateError);
    expect((await db.allProfiles()).single.sourcePath, first);
    expect(File(first).readAsBytesSync(), bytes);
    expect(directory.listSync(), hasLength(1));
  });

  test('concurrent generated saves cannot replace an installed version', () async {
    final profile = Profile.fromJson(manifest());
    final directory = Directory('${dir.path}/generated');
    Future<bool> save() async {
      try {
        await storeNewProfileVersion(db, profile, directory);
        return true;
      } on StateError {
        return false;
      }
    }
    expect(await Future.wait([save(), save()]), containsAll([true, false]));
    expect(await db.allProfiles(), hasLength(1));
    expect(directory.listSync(), hasLength(1));
  });

  test('traversal manifests are rejected by manual and inbox import', () async {
    for (final id in [
      '../outside',
      r'..\outside',
      '/tmp/outside',
      '.',
      '..',
      'bad\u0000id',
    ]) {
      final path = zip({...manifest(), 'profile_id': id});
      await expectLater(
        readProfilePackage(path),
        throwsA(isA<AnalysisError>()),
      );
      expect(await scanInbox(db, dir.path, Directory('${dir.path}/store')), 0);
      expect(await db.allProfiles(), isEmpty);
    }
  });

  test('JSON import owns its copy after original is removed', () async {
    final f = File('${dir.path}/profile.json')
      ..writeAsStringSync(jsonEncode(manifest()));
    await applyImport(
      db,
      f.path,
      await readProfilePackage(f.path),
      null,
      () async => Directory('${dir.path}/store'),
    );
    f.deleteSync();
    final rows = await db.allProfiles();
    expect(
      (await readProfilePackage(rows.single.sourcePath)).coachName,
      'Dummy Coach',
    );
  });

  test(
    'malformed extras leave the previous installed version intact',
    () async {
      final original = zip(manifest());
      await applyImport(
        db,
        original,
        await readProfilePackage(original),
        null,
        () async => Directory('${dir.path}/store'),
      );
      final old = (await db.allProfiles()).single;
      final bad = zip(
        {...manifest(), 'version': 2},
        marks: [
          {'clip': 'x'},
        ],
      );
      await expectLater(
        applyImport(
          db,
          bad,
          await readProfilePackage(bad),
          ImportChoice.merge,
          () async => Directory('${dir.path}/store'),
        ),
        throwsA(isA<AnalysisError>()),
      );
      expect((await db.allProfiles()).single.sourcePath, old.sourcePath);
      expect((await db.allProfiles()).single.version, 1);
    },
  );

  test(
    'legacy same-name marks stay unbound and repeated merge is idempotent',
    () async {
      final video = File('${dir.path}/same.mp4')
        ..writeAsStringSync('unrelated recording');
      await db.saveProject(
        Project(
          projectId: 'p',
          name: 'local',
          clips: [
            Clip(
              clipId: 'c',
              path: video.path,
              displayName: 'same',
              addedAt: DateTime.now(),
            ),
          ],
        ),
      );
      final path = zip(
        manifest(),
        marks: [
          {
            'clip': 'same',
            'time_ms': 1,
            'attribute': 'Slope',
            'label': 'green',
            'author': 'coach',
            'created_at': '2026-11-01T00:00:00Z',
          },
        ],
      );
      for (var i = 0; i < 2; i++) {
        await applyImport(
          db,
          path,
          await readProfilePackage(path),
          ImportChoice.merge,
          () async => Directory('${dir.path}/store'),
        );
      }
      expect(await db.marksForPath(video.path), isEmpty);
      final projects = await db.select(db.projectRows).get();
      expect(projects, hasLength(2));
    },
  );

  ProfileBuilderController builder({ClipEvaluator? evaluate}) =>
      ProfileBuilderController(
        pack: placeholderPack.analysisPack,
        probe: (_) async => const ClipInfo(durationMs: 6000, fps: 30),
        evaluate:
            evaluate ??
            (clip, name) => ProfileBuilder(
              engine: AnalysisEngine(
                pack: placeholderPack.analysisPack,
                pose: const StubPoseEstimator(styleSeed: 42),
              ),
            ).evaluate(clip, displayName: name),
        store: (_) async => throw StateError('must not store'),
        save: (_, _) async => null,
        install: (_, _) async {},
      );

  test(
    '15 renamed copies count as one usable source and cannot build',
    () async {
      final c = builder();
      addTearDown(c.dispose);
      c.setCoachName('Coach');
      final files = [
        for (var i = 0; i < 15; i++)
          (File('${dir.path}/$i.mp4')..writeAsStringSync('same bytes')).path,
      ];
      await c.addClips(files);
      expect(c.usableCount, 1);
      expect(c.checking, false);
      await c.build();
      expect(c.outcome, isA<BuildRejected>());
    },
  );

  test('failed duplicate is decoded once and removal permits another copy', () async {
    var calls = 0;
    final c = builder(evaluate: (_, _) async { calls++; throw StateError('decoder'); });
    addTearDown(c.dispose);
    final a = File('${dir.path}/bad.mp4')..writeAsStringSync('bad bytes');
    final b = File('${dir.path}/copy.mp4')..writeAsStringSync('bad bytes');
    await c.addClips([a.path, b.path]);
    expect(calls, 1);
    expect(c.clips.last.quality!.reasons.single, contains('already included'));
    c.removeClip(c.clips.first);
    await c.retryClip(c.clips.single);
    expect(calls, 2);
    expect(c.checking, false);
  });

  test('failed analysis finishes batch and can retry', () async {
    var fail = true;
    final good = builder();
    addTearDown(good.dispose);
    final c = builder(
      evaluate: (clip, name) async {
        if (name == 'first' && fail) throw StateError('decoder');
        return good.evaluate(clip, name);
      },
    );
    addTearDown(c.dispose);
    final a = File('${dir.path}/first.mp4')..writeAsStringSync('first');
    final b = File('${dir.path}/second.mp4')..writeAsStringSync('second');
    await c.addClips([a.path, b.path]);
    expect(c.checking, false);
    expect(c.usableCount, 1);
    fail = false;
    await c.retryClip(c.clips.first);
    expect(c.usableCount, 2);
  });

  test('production training isolates do not capture the review database', () async {
    const clip = ClipSource(clipId: 'synthetic', path: 'unused', durationMs: 6000, fps: 30);
    final track = await const StubPoseEstimator(styleSeed: 42).estimate(clip);
    Future<AthleteTrack> load(ClipSource _) async {
      await db.allProfiles(); // Deliberately captures a nonsendable native DB.
      return AthleteTrack(track: track,
          target: const AthleteTarget(quarterTurns: 0, frame: 0, x: .5, y: .5),
          ambiguous: false, orientationSure: true, candidatesFrame: 0, candidates: []);
    }
    expect(await visionEvaluator(placeholderPack.analysisPack, load: load)(clip, 'fixture'),
        isA<ClipQuality>());
    expect(await visionProbeAnalyzer(placeholderPack.analysisPack, load: load)(clip, {}, []),
        isA<AnalysisDetail>());
  });

  test('uncertain athlete and orientation cannot enter fitting', () async {
    const clip = ClipSource(
      clipId: 'c',
      path: 'unused',
      durationMs: 1000,
      fps: 30,
    );
    for (final flags in [(true, true), (false, false)]) {
      await expectLater(
        trainingTrack(
          clip,
          load: (_) async => AthleteTrack(
            track: const PoseTrack(fps: 30, frames: []),
            target: const AthleteTarget(
              quarterTurns: 0,
              frame: 0,
              x: .5,
              y: .5,
            ),
            ambiguous: flags.$1,
            orientationSure: flags.$2,
            candidatesFrame: 0,
            candidates: [],
          ),
        ),
        throwsA(isA<AnalysisError>()),
      );
    }
  });
}
