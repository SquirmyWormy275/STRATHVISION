import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/workspace/project.dart';

import 'support/carne_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarneFixture fixture;
  late Directory dir;
  setUpAll(() async => fixture = await CarneFixture.load());
  setUp(() async => dir = await Directory.systemTemp.createTemp('carne_run_'));
  tearDown(() async => dir.delete(recursive: true));

  String video(String folder, String contents, {String name = 'same.mov'}) {
    final parent = Directory('${dir.path}/$folder')
      ..createSync(recursive: true);
    return (File('${parent.path}/$name')..writeAsStringSync(contents)).path;
  }

  test('copies and renamed duplicates count once; same names with different bytes are independent', () async {
    var analyses = 0;
    final c = fixture.controller(
      analyze: (clip) {
        analyses++;
        return fixture.strokes(clip);
      },
    );
    addTearDown(c.dispose);
    final a = video('a', 'first content');
    final copy = video('copy', 'first content', name: 'renamed.mov');
    final other = video('b', 'different content');
    await c.drop([a]);
    final seconds = c.session.usableSeconds, count = c.session.pile.length;
    await c.drop([copy, a]);
    expect(analyses, 1);
    expect(c.session.usableSeconds, seconds);
    expect(c.session.pile, hasLength(count));
    await c.drop([other]);
    expect(analyses, 2);
    final report = c.runReport();
    expect(report['sources'] as List, hasLength(2));
    expect(
      (report['inputs'] as List).where((i) => i['status'] == 'duplicate'),
      hasLength(2),
    );
    expect(
      ((report['sources'] as List).first as Map)['paths'],
      containsAll([a, copy]),
    );
  });

  test(
    'Ignore and Use anyway cannot affect an unrelated same-named video',
    () async {
      final c = fixture.controller(confidence: .55);
      addTearDown(c.dispose);
      final a = video('a', 'one'), b = video('b', 'two');
      await c.drop([a, b]);
      final sources = c.runReport()['sources'] as List;
      final idA = sources[0]['clip_id'] as String,
          idB = sources[1]['clip_id'] as String;
      expect(c.session.usableSeconds, 0);
      c.useAnyway(idA);
      expect(
        c.session.pile
            .where((s) => s.stroke.clipId == idA)
            .every((s) => s.forced),
        isTrue,
      );
      expect(
        c.session.pile
            .where((s) => s.stroke.clipId == idB)
            .any((s) => s.forced),
        isFalse,
      );
      final note = File('${dir.path}/ignore.txt')
        ..writeAsStringSync('ignore this clip');
      await c.drop([a, note.path]);
      expect(
        c.session.pile
            .where((s) => s.stroke.clipId == idA)
            .every((s) => s.ignored),
        isTrue,
      );
      expect(
        c.session.pile
            .where((s) => s.stroke.clipId == idB)
            .any((s) => s.ignored),
        isFalse,
      );
      expect(c.session.usableSeconds, 0);
    },
  );

  test('repeat drops refresh and remove feedback without duplicating marks or footage', () async {
    final byPath = <String, List<Mark>>{};
    var analyses = 0;
    final c = fixture.controller(
      marks: (path) async => byPath[path] ?? [],
      analyze: (clip) {
        analyses++;
        return fixture.strokes(clip);
      },
    );
    addTearDown(c.dispose);
    final a = video('a', 'same'), b = video('b', 'same');
    await c.drop([a]);
    final seconds = c.session.usableSeconds;
    final span = c.session.pile.first.stroke;
    final mark = Mark(
      markId: 'real-mark-id',
      clipId: 'project-clip',
      timeMs: (span.midSeconds * 1000).round(),
      attribute: 'Slope',
      label: MarkLabel.green,
      author: MarkAuthor.coach,
      createdAt: DateTime.utc(2026, 11, 4),
    );
    byPath[a] = [mark];
    byPath[b] = [mark];
    await c.drop([a, b]);
    expect(c.session.pile.fold(0, (n, s) => n + s.marks.length), 1);
    byPath[a] = [];
    byPath[b] = [];
    // Re-dropping either alias refreshes every observed path.
    await c.drop([b]);
    expect(c.session.pile.every((s) => s.marks.isEmpty), isTrue);
    expect(c.session.usableSeconds, seconds);
    expect(analyses, 1);
  });

  test(
    'a failed feedback refresh removes cached marks and can retry',
    () async {
      var fail = false;
      final c = fixture.controller(
        marks: (path) async {
          if (fail) throw StateError('fixture feedback lookup failure');
          return [
            Mark(
              markId: 'feedback',
              clipId: 'clip',
              timeMs: 10000,
              attribute: 'Slope',
              label: MarkLabel.green,
              author: MarkAuthor.coach,
              createdAt: DateTime.utc(2026, 11, 4),
            ),
          ];
        },
      );
      addTearDown(c.dispose);
      final path = video('feedback', 'video bytes');
      await c.drop([path]);
      expect(c.session.pile.any((s) => s.marks.isNotEmpty), isTrue);
      fail = true;
      await c.drop([path]);
      expect(c.session.pile.every((s) => s.marks.isEmpty), isTrue);
      expect(
        (c.runReport()['inputs'] as List).last['feedback_error'],
        isNotNull,
      );
      expect(
        c.feed.any(
          (line) => line.text.contains('Some feedback could not be refreshed'),
        ),
        isTrue,
      );
      fail = false;
      await c.drop([path]);
      expect(c.session.pile.any((s) => s.marks.isNotEmpty), isTrue);
    },
  );

  test(
    'feedback on a shared stroke boundary binds to exactly one stroke',
    () async {
      final byPath = <String, List<Mark>>{};
      final c = fixture.controller(marks: (path) async => byPath[path] ?? []);
      addTearDown(c.dispose);
      final a = video('a', 'boundary');
      await c.drop([a]);
      final strokes = c.session.pile.map((s) => s.stroke).toList();
      final next = strokes.firstWhere(
        (s) => strokes.any((p) => p.endFrame + 1 == s.startFrame),
      );
      byPath[a] = [
        Mark(
          markId: 'boundary',
          clipId: 'project-clip',
          timeMs: (next.startFrame / next.fps * 1000).round(),
          attribute: 'Slope',
          label: MarkLabel.green,
          author: MarkAuthor.coach,
          createdAt: DateTime.utc(2026, 11, 4),
        ),
      ];
      await c.drop([a]);
      expect(c.session.pile.fold(0, (n, s) => n + s.marks.length), 1);
    },
  );

  test('failed input does not abort the batch and can be retried', () async {
    var fail = true;
    final bad = video('bad', 'bad'), good = video('good', 'good');
    final c = fixture.controller(
      analyze: (clip) {
        if (clip.path == bad && fail) {
          throw StateError('fixture analysis failure');
        }
        return fixture.strokes(clip);
      },
    );
    addTearDown(c.dispose);
    await c.drop([bad, good]);
    final inputs = c.runReport()['inputs'] as List;
    expect(inputs[0]['status'], 'failed');
    expect(inputs[0]['stage'], 'analysis');
    expect(inputs[1]['status'], 'analyzed');
    expect(c.busy, isFalse);
    fail = false;
    await c.drop([bad]);
    expect(c.runReport()['sources'] as List, hasLength(2));
  });

  test(
    'priority and ignore notes finish before the batch tries an update',
    () async {
      final c = fixture.controller();
      addTearDown(c.dispose);
      final paths = [for (var i = 0; i < 3; i++) video('$i', 'note-$i')];
      await c.drop(paths);
      expect(c.session.baselineMet, isTrue);
      final before = (c.runReport()['loop_attempts'] as List).length;
      final note = File('${dir.path}/instructions.txt')
        ..writeAsStringSync('priority: hinge\nignore this clip');
      await c.drop([paths.last, note.path]);
      expect(c.session.priority, 'Hinge');
      expect(c.session.baselineMet, isFalse);
      expect(c.session.edits, isEmpty);
      expect((c.runReport()['loop_attempts'] as List).length, before + 1);
      expect(c.stopReason, 'below baseline');
    },
  );

  test('overlapping drops serialize duplicate checks and analysis', () async {
    final gate = Completer<void>(), started = Completer<void>();
    var analyses = 0;
    final c = fixture.controller(
      analyze: (clip) async {
        analyses++;
        if (!started.isCompleted) started.complete();
        await gate.future;
        return fixture.strokes(clip);
      },
    );
    addTearDown(c.dispose);
    final a = video('a', 'same'), b = video('b', 'same');
    final first = c.drop([a]), second = c.drop([b]);
    await started.future;
    expect(c.busy, isTrue);
    gate.complete();
    await Future.wait([first, second]);
    expect(analyses, 1);
    expect(c.busy, isFalse);
    expect(c.runReport()['sources'] as List, hasLength(1));
  });

  test(
    'changed bytes at one path get a new source ID and do not reuse old marks',
    () async {
      var clock = DateTime.utc(2026, 11, 4);
      final a = video('a', 'old');
      var analyses = 0;
      final c = fixture.controller(
        clock: () => clock,
        marks: (path) async => [
          Mark(
            markId: 'old',
            clipId: 'clip',
            timeMs: 10000,
            attribute: 'Slope',
            label: MarkLabel.green,
            author: MarkAuthor.coach,
            createdAt: DateTime.utc(2026, 11, 4),
          ),
        ],
        analyze: (clip) {
          analyses++;
          return fixture.strokes(clip);
        },
      );
      addTearDown(c.dispose);
      await c.drop([a]);
      final oldId = c.session.pile.first.stroke.clipId;
      File(a).writeAsStringSync('new');
      clock = clock.add(const Duration(seconds: 1));
      await c.drop([a]);
      expect(analyses, 2);
      final ids = c.session.pile.map((s) => s.stroke.clipId).toSet();
      expect(ids, hasLength(2));
      expect(
        c.session.pile
            .where((s) => s.stroke.clipId != oldId)
            .every((s) => s.marks.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'zero-edit and failed experiments export without writing a profile version',
    () async {
      var profileWrites = 0;
      final c = fixture.controller(
        probe: (path) async => null,
        write: (profile, patches, adapters, research) async {
          profileWrites++;
          return 'unexpected';
        },
      );
      addTearDown(c.dispose);
      final original = jsonEncode(fixture.profile.toJson());
      await c.drop([video('invalid', 'not a video')]);
      expect(c.stopReason, 'input error');
      expect(c.canSaveRun, isTrue);
      final output = File('${dir.path}/experiment.json');
      await c.saveRun((name, contents) async {
        await output.writeAsString(contents);
        return output.path;
      });
      final report = jsonDecode(await output.readAsString()) as Map;
      expect(report['format'], 'carne_asada_run/1');
      expect((report['session'] as Map)['edits'], isEmpty);
      expect((report['inputs'] as List).single['status'], 'invalid_video');
      expect(report['base_profile']['version'], fixture.profile.version);
      expect(c.savedPath, isNull);
      expect(c.runSaved, isTrue);
      expect(c.canSaveProfile, isFalse);
      await c.save();
      expect(profileWrites, 0);
      expect(jsonEncode(fixture.profile.toJson()), original);
    },
  );

  test('waiting for feedback is explicit; canceled/failed exports retry and later changes dirty the snapshot', () async {
    final c = fixture.controller();
    addTearDown(c.dispose);
    await c.drop([for (var i = 0; i < 3; i++) video('$i', 'bytes-$i')]);
    expect(c.session.baselineMet, isTrue);
    expect(c.stopReason, 'no marks');
    expect(c.statusText, contains('Waiting for coach or athlete feedback'));
    await c.saveRun((name, contents) async => null);
    expect(c.runSaved, isFalse);
    await c.saveRun(
      (name, contents) async =>
          throw const FileSystemException('fixture write failure'),
    );
    expect(c.busy, isFalse);
    expect(c.runSaved, isFalse);
    int? savedRevision;
    await c.saveRun((name, contents) async {
      savedRevision = (jsonDecode(contents) as Map)['run_revision'];
      return '/run.json';
    });
    expect(c.runSaved, isTrue);
    c.tryUpdate();
    expect(c.runSaved, isFalse);
    expect(c.runReport()['run_revision'] as int, greaterThan(savedRevision!));
    expect((c.runReport()['loop_attempts'] as List).last['reason'], 'no marks');
  });

  for (final size in [const Size(1000, 800), const Size(780, 420)]) {
    testWidgets(
      'zero-edit export stays reachable at $size and keeps profile save disabled',
      (tester) async {
        final c = fixture.controller();
        addTearDown(c.dispose);
        final a = video('a', 'screen');
        String? exported;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: CarneScreen(
              controller: c,
              title: 'Fixture',
              saveExperiment: (name, contents) async {
                exported = contents;
                return '/fixture-run.json';
              },
            ),
          ),
        );
        await tester.runAsync(() => c.drop([a]));
        await tester.pumpAndSettle();
        expect(
          find.text('Insufficient usable footage for an update.'),
          findsWidgets,
        );
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('save-carne')))
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(const Key('save-experiment')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-experiment')));
        await tester.pumpAndSettle();
        expect(exported, isNotNull);
        expect(find.text('Experiment saved'), findsOneWidget);
        expect((jsonDecode(exported!) as Map)['saved_profile_path'], isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
