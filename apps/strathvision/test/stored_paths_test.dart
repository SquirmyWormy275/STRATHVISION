import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:path/path.dart' as p;
import 'package:strathvision/data/database.dart';
import 'package:strathvision/data/stored_paths.dart';
import 'package:strathvision/media/picked_video.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/workspace/project.dart';

void main() {
  late Directory root;
  const oldId = '12345678-1234-1234-1234-123456789012';
  const newId = '87654321-4321-4321-4321-210987654321';
  Directory container(String id) =>
      Directory(p.join(root.path, 'Containers', 'Data', 'Application', id));
  Directory support(String id) =>
      Directory(p.join(container(id).path, 'Library', 'Application Support'));
  StoredPaths paths(String id, {bool onIOS = true}) =>
      StoredPaths(onIOS: onIOS, supportDirectory: () async => support(id));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sv-container-move-');
    await support(oldId).create(recursive: true);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'owned paths are relative in storage and preserve special filenames',
    () async {
      final path = p.join(
        support(oldId).path,
        'imported_clips',
        'clip-123',
        'épreuve #1% ?.MOV',
      );
      final stored = await paths(oldId).encode(path);
      expect(stored, startsWith('strathvision-support:/imported_clips/'));
      expect(stored, isNot(contains(oldId)));
      expect(
        await paths(newId).decode(stored),
        p.join(
          support(newId).path,
          'imported_clips',
          'clip-123',
          'épreuve #1% ?.MOV',
        ),
      );
    },
  );

  test('external files and desktop paths remain exactly as supplied', () async {
    final ios = paths(newId);
    final outside = [
      '/external/clip.MOV',
      p.join(container(oldId).path, 'tmp', 'clip.MOV'),
      p.join(support(oldId).path, 'unowned', 'clip.MOV'),
      '/another/app/Library/Application Support/profiles/profile.zip',
      '',
    ];
    for (final path in outside) {
      expect(await ios.encode(path), path);
      expect(await ios.decode(path), path);
    }
    final desktop = StoredPaths(
      onIOS: false,
      supportDirectory: () => throw StateError('must not access storage'),
    );
    final owned = p.join(support(oldId).path, 'profiles', 'profile.zip');
    expect(await desktop.encode(owned), owned);
    expect(await desktop.decode(owned), owned);
  });

  test('legacy owned paths rebase only inside the same container hierarchy', () async {
    final path = p.join(support(oldId).path, 'profiles', 'profile.zip');
    expect(
      await paths(newId).decode(path),
      p.join(support(newId).path, 'profiles', 'profile.zip'),
    );
    expect(await paths(newId).decode('/unrelated$path'), '/unrelated$path');
    final mobile = StoredPaths(
      onIOS: true,
      supportDirectory: () async => Directory(
        '/var/mobile/Containers/Data/Application/$newId/Library/Application Support',
      ),
    );
    expect(
      await mobile.decode(
        '/private/var/mobile/Containers/Data/Application/$oldId/Library/Application Support/profiles/a.zip',
      ),
      '/var/mobile/Containers/Data/Application/$newId/Library/Application Support/profiles/a.zip',
    );
  });

  test(
    'invalid tagged references cannot escape owned application storage',
    () async {
      for (final invalid in [
        'strathvision-support:/profiles/../../outside',
        'strathvision-support:/profiles/%2e%2e/%2e%2e/outside',
        'strathvision-support://elsewhere/profiles/a.zip',
        'strathvision-support:/profiles/a.zip?redirect=/outside',
        'strathvision-support:/profiles/a.zip#outside',
        'strathvision-support:/unowned/a.zip',
        'strathvision-support:/profiles/..%5coutside',
      ]) {
        await expectLater(
          paths(newId).decode(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    },
  );

  for (final legacy in [false, true]) {
    test(
      '${legacy ? 'legacy absolute' : 'relative'} database survives an actual container move',
      () async {
        final originalSupport = support(oldId);
        var db = AppDatabase(
          NativeDatabase(File(p.join(originalSupport.path, 'test.sqlite'))),
          paths(oldId),
        );
        final temporary = await File(p.join(root.path, 'picker.MOV'))
            .writeAsBytes([1, 2, 3, 4, 255]);
        final clipPath = await retainPickedVideo(
          temporary.path,
          onIOS: true,
          supportDirectory: () async => originalSupport,
        );
        final date = DateTime.utc(2026, 11, 24);
        final project = Project(
          projectId: 'review',
          name: 'Saved review',
          clips: [
            Clip(
              clipId: 'clip',
              path: clipPath,
              displayName: 'picker.MOV',
              addedAt: date,
              athlete: const {'frame': 0, 'x': 0.5, 'y': 0.5},
            ),
          ],
          annotations: [
            Annotation(
              annotationId: 'note',
              clipId: 'clip',
              timeMs: 1200,
              text: 'Keep this note',
              createdAt: date,
            ),
          ],
          marks: [
            Mark(
              markId: 'mark',
              clipId: 'clip',
              timeMs: 1200,
              attribute: 'Timing',
              label: MarkLabel.green,
              author: MarkAuthor.coach,
              createdAt: date,
            ),
          ],
          workspace: const WorkspaceState(
            stageAClipId: 'clip',
            playbackRate: 0.5,
          ),
        );
        await db.saveProject(project);
        final metadata = await readProfilePackage(
          'test/fixtures/dummy_profile.json',
        );
        await applyImport(
          db,
          'test/fixtures/dummy_profile.json',
          metadata,
          null,
          () async => Directory(p.join(originalSupport.path, 'profiles')),
        );
        final profile = (await db.allProfiles()).single;
        const result = ComparisonResult(
          resultId: 'result',
          clipId: 'clip',
          profileId: '7f1c2d3e-0000-4000-8000-000000000001',
          profileVersion: 1,
          overallScore: 0.7,
          rankedDeltas: [],
          metricsUsed: 1,
          metricsMissing: [],
          lowConfidencePhases: [],
          nearestReferenceClipIds: [],
          warnings: [],
          appliedPatches: [],
        );
        await db.saveComparison(projectId: 'review', result: result, at: date);
        if (legacy) {
          // Precisely the persisted representation in earlier iPhone releases.
          await db
              .update(db.projectRows)
              .write(
                ProjectRowsCompanion(json: Value(jsonEncode(project.toJson()))),
              );
          await db
              .update(db.profiles)
              .write(ProfilesCompanion(sourcePath: Value(profile.sourcePath)));
        } else {
          expect(
            (await db.select(db.projectRows).get()).single.json,
            isNot(contains(originalSupport.path)),
          );
          expect(
            (await db.select(db.profiles).get()).single.sourcePath,
            startsWith('strathvision-support:'),
          );
        }
        await db.close();
        await temporary.delete();
        await container(oldId).rename(container(newId).path);
        expect(await File(clipPath).exists(), isFalse);
        expect(await File(profile.sourcePath).exists(), isFalse);

        db = AppDatabase(
          NativeDatabase(File(p.join(support(newId).path, 'test.sqlite'))),
          paths(newId),
        );
        try {
          final restored = (await db.loadProject('review'))!;
          expect(await File(restored.clips.single.path).readAsBytes(), [
            1,
            2,
            3,
            4,
            255,
          ]);
          expect(restored.clips.single.clipId, 'clip');
          expect(restored.clips.single.athlete, project.clips.single.athlete);
          expect(restored.annotations.single.text, 'Keep this note');
          expect(restored.workspace.toJson(), project.workspace.toJson());
          expect(
            (await db.marksForPath(restored.clips.single.path)).single.markId,
            'mark',
          );
          expect((await db.allProjects()).single.toJson(), restored.toJson());
          final listed = (await db.watchProjects().first).single;
          expect(
            Project.fromJson(jsonDecode(listed.json)).toJson(),
            restored.toJson(),
          );
          final restoredProfile = (await db.allProfiles()).single;
          expect(
            (await readProfileBundle(restoredProfile.sourcePath))
                .profile
                .profileId,
            metadata.profileId,
          );
          expect(
            (await db.watchProfiles().first).single.sourcePath,
            restoredProfile.sourcePath,
          );
          expect(
            jsonDecode(
              (await db.comparisonsForProfile(metadata.profileId)).single.json,
            ),
            result.toJson(),
          );
          final exported = await planExport(
            db,
            restoredProfile,
            ExportChoice.profileOnly,
            attributes: const [],
          );
          expect(exported.entries, contains('profile.json'));
          // Saving an old absolute record upgrades it to a movable reference.
          await db.saveProject(restored);
          expect(
            (await db.select(db.projectRows).get()).single.json,
            isNot(contains(support(newId).path)),
          );
        } finally {
          await db.close();
        }
      },
    );
  }
}
