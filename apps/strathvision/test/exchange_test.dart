import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/data/database.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/workspace/project.dart';

/// Export choices and import replace / keep / merge (DECISIONS.md).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase laptop, phone;
  late Directory dir;
  final now = DateTime.utc(2026, 11, 4, 9);

  Profile profile(int version) => Profile(
        profileId: 'prof-1',
        version: version,
        coachName: 'Coach',
        packId: 'timber',
        eventId: 'underhand',
        metricSchemaVersion: 'timber-underhand-1',
        createdAt: now,
        sourceClipCount: 15,
        minClipsMet: true,
        selfConsistencyPassed: true,
        notes: '',
        metrics: const {
          'entry_slope': ProfileMetric(center: -65, spread: 8, weight: 2, unit: '°', phase: 'downswing'),
        },
      );

  setUp(() async {
    laptop = AppDatabase(NativeDatabase.memory());
    phone = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('sv_x');
    final path = await storeProfilePackage(profile(2), Directory('${dir.path}/laptop'),
        patches: {'slope_residual_v1.patch': '{}'},
        research: {'mixture_edits_v2.json': '{"format":"carne_asada/1"}'});
    await laptop.saveProfile(await readProfilePackage(path), path);
    await laptop.saveProject(Project(
      projectId: 'p1',
      name: 'Review',
      clips: [Clip(clipId: 'c1', path: '/videos/swing_04.mp4', displayName: 'swing_04', addedAt: now)],
      marks: [
        Mark(markId: 'm1', clipId: 'c1', timeMs: 4200, attribute: 'Slope',
            label: MarkLabel.green, author: MarkAuthor.coach, createdAt: now),
        Mark(markId: 'm2', clipId: 'c1', timeMs: 5200, attribute: 'Timing',
            label: MarkLabel.red, author: MarkAuthor.athlete, createdAt: now),
      ],
    ));
    await laptop.saveComparison(
        projectId: 'p1',
        at: now,
        result: const ComparisonResult(
          resultId: 'r1', clipId: 'c1', profileId: 'prof-1', profileVersion: 2,
          overallScore: 0.7, rankedDeltas: [], metricsUsed: 1, metricsMissing: [],
          lowConfidencePhases: [], nearestReferenceClipIds: [], warnings: [], appliedPatches: [],
        ));
  });
  tearDown(() async {
    await laptop.close();
    await phone.close();
    dir.deleteSync(recursive: true);
  });

  Future<ExportPlan> plan(ExportChoice c) async => planExport(
      laptop, (await laptop.allProfiles()).single, c,
      attributes: const ['Slope', 'Spacing', 'Hinge', 'Path']);

  List<String> names(ExportPlan p) =>
      ZipDecoder().decodeBytes(p.zip()).files.map((f) => f.name).toList();

  test('coaching profile only: no marks, history, or research', () async {
    final p = await plan(ExportChoice.profileOnly);
    expect(names(p), containsAll(['profile.json', 'specialist_patches/slope_residual_v1.patch']));
    expect(names(p).where((n) => n.startsWith('marks') || n.startsWith('history') || n.startsWith('carne')),
        isEmpty);
    expect(p.summary.first, startsWith('Coach · v2'));
  });

  test('+ my marks: this event’s marks, file names only', () async {
    final p = await plan(ExportChoice.withMarks);
    final marks = jsonDecode(p.entries[marksFile]!) as List;
    expect(marks, hasLength(1)); // Timing is not a timber attribute
    expect(marks.single, {
      'clip': 'swing_04',
      'time_ms': 4200,
      'attribute': 'Slope',
      'label': 'green',
      'author': 'coach',
      'created_at': '2026-11-04T09:00:00.000Z',
    });
    expect(p.entries[marksFile], isNot(contains('/videos/')));
    expect(p.summary, contains('1 red/green marks (file names only, no video)'));
  });

  test('full local overlay adds history and research', () async {
    final p = await plan(ExportChoice.fullOverlay);
    expect(names(p), containsAll([marksFile, historyFile, 'carne_asada/mixture_edits_v2.json']));
    expect(p.summary, contains('1 past comparisons (match trend)'));
    expect(p.summary, contains('1 CARNE ASADA research record(s)'));
  });

  group('import on the phone', () {
    late String overlay;
    setUp(() async {
      final p = await plan(ExportChoice.fullOverlay);
      overlay = '${dir.path}/Coach_v2.zip';
      File(overlay).writeAsBytesSync(p.zip());
      // The phone already has v1 of the same profile.
      final v1 = await storeProfilePackage(profile(1), Directory('${dir.path}/phone_old'));
      await phone.saveProfile(await readProfilePackage(v1), v1);
    });
    Future<String> run(ImportChoice? c) async =>
        applyImport(phone, overlay, await readProfilePackage(overlay), c, () async => Directory('${dir.path}/store'));

    test('replace removes the other versions', () async {
      expect(await run(ImportChoice.replace), 'Replaced with Coach · v2');
      expect((await phone.allProfiles()).map((r) => r.version), [2]);
    });

    test('keep both installs alongside; same version twice is kept once', () async {
      expect(await run(ImportChoice.keep), 'Imported Coach · v2');
      expect((await phone.allProfiles()).map((r) => r.version).toSet(), {1, 2});
      expect(await run(ImportChoice.keep), 'Kept Coach · v2; it was already here.');
    });

    test('merge also brings marks and match history', () async {
      // A clip with the same file name exists on the phone.
      await phone.saveProject(Project(projectId: 'pp', name: 'Phone review', clips: [
        Clip(clipId: 'x', path: '/phone/swing_04.mp4', displayName: 'swing_04', addedAt: now),
      ]));
      final msg = await run(ImportChoice.merge);
      expect(msg, 'Merged Coach · v2, with 1 past comparisons and 1 marks (1 of 1 clips found here)');
      expect((await phone.comparisonsForProfile('prof-1')).single.resultId, 'r1');
      final marks = await phone.marksForPath('/phone/swing_04.mp4');
      expect(marks.single.attribute, 'Slope');
      expect(marks.single.author, MarkAuthor.coach);
      // Research never reaches the phone's bundle reader.
      final bundle = await readProfileBundle((await phone.allProfiles())
          .firstWhere((r) => r.version == 2)
          .sourcePath);
      expect(bundle.patchFiles.keys, ['slope_residual_v1.patch']);
    });

    test('first import of a new profile needs no choice', () async {
      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      expect(
          await applyImport(fresh, overlay, await readProfilePackage(overlay), null,
              () async => Directory('${dir.path}/s2')),
          'Imported Coach · v2');
    });
  });
}
