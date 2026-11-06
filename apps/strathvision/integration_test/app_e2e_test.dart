// End-to-end on a desktop: the real app (real players, real storage, real
// analysis isolates, bundled packs) driven through every screen. Only the
// native file dialogs are replaced; they return real clip files.
//
//   flutter test integration_test/app_e2e_test.dart -d linux \
//     --dart-define=CLIP_DIR=$PWD/integration_test/assets \
//     --dart-define=SHOTS=/tmp/sv_shots
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/main.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/profile_package.dart';

const clipDir = String.fromEnvironment('CLIP_DIR');
const shotsDir = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('every screen works on the desktop', (tester) async {
    expect(clipDir, isNotEmpty);
    final work = await tester.runAsync(
      () => Directory.systemTemp.createTemp('sv_e2e'),
    );
    final support = await tester.runAsync(getApplicationSupportDirectory);
    final storeBefore = await tester.runAsync(() async {
      final d = Directory('${support!.path}/profiles');
      return d.existsSync()
          ? d.listSync().map((f) => f.path).toSet()
          : <String>{};
    });
    // Fifteen copies deliberately exercise content deduplication. They must
    // never establish an independently sourced profile.
    final refs = await tester.runAsync(
      () async => [
        for (var i = 1; i <= 15; i++)
          (await File('$clipDir/cleave.webm').copy(
            '${work!.path}/swing_${i.toString().padLeft(2, '0')}.webm',
          )).path,
      ],
    );
    final db = AppDatabase(NativeDatabase(File('${work!.path}/e2e.sqlite')));
    final packs = await tester.runAsync(() => loadPacks(rootBundle));
    final clipQueue = <String>[];
    final saved = <String>[];
    var shot = 0;

    // Real screen pixels of the app window when it is on the active
    // workspace (nothing else is captured); otherwise the app's own layer
    // tree (which may lag video textures).
    final shotKey = GlobalKey();
    Future<void> snap(String name) async {
      if (shotsDir.isEmpty) return;
      await tester.pump(const Duration(milliseconds: 300));
      final file = '$shotsDir/${(++shot).toString().padLeft(2, '0')}_$name.png';
      final grabbed = await tester.runAsync(() async {
        await Directory(shotsDir).create(recursive: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          final ws = jsonDecode(
            (await Process.run('hyprctl', ['activeworkspace', '-j'])).stdout
                as String,
          ) as Map;
          final cs = jsonDecode(
            (await Process.run('hyprctl', ['clients', '-j'])).stdout as String,
          ) as List;
          final w = cs
              .cast<Map>()
              .where((c) => c['title'] == 'strathvision')
              .firstOrNull;
          if (w == null || (w['workspace'] as Map)['id'] != ws['id']) {
            return false;
          }
          final at = w['at'] as List, size = w['size'] as List;
          final r = await Process.run('grim', [
            '-g',
            '${at[0]},${at[1]} ${size[0]}x${size[1]}',
            file,
          ]);
          return r.exitCode == 0;
        } on Object {
          return false;
        }
      });
      if (grabbed == true) return;
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      await tester.runAsync(() async {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(file).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> wait(WidgetTester t, Finder f, {int seconds = 30}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (f.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) {
          await snap('FAILED_waiting');
          final texts = find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .take(40)
              .toList();
          fail('timed out waiting for $f; visible text: $texts');
        }
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 200));
    }

    Future<void> idle(WidgetTester t, int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> tap(String key, {int after = 400}) async {
      debugPrint('e2e tap: $key');
      await wait(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)).first);
      await idle(tester, after);
    }

    Future<void> back() async {
      debugPrint('e2e back');
      await tester.pageBack();
      await idle(tester, 600);
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: StrathvisionApp(
          db: db,
          packs: packs!,
          pickClip: () async =>
              clipQueue.isEmpty ? null : clipQueue.removeAt(0),
          pickClips: () async => refs!,
          pickFiles: () async => refs!.take(4).toList(),
          saveFile: (name, bytes) async {
            final f = File('${work.path}/export_$name');
            await f.writeAsBytes(bytes);
            saved.add(f.path);
            return f.path;
          },
        ),
      ),
    );
    await idle(tester, 1500);
    expect(find.text('Underhand'), findsOneWidget);
    await snap('library_empty');

    // ---- Review workspace with real video ---------------------------------
    await tap('open-workspace', after: 1000);
    clipQueue.addAll(['$clipDir/clip30.mp4', '$clipDir/clip25.mp4']);
    await tap('load-A', after: 3000);
    await tap('load-B', after: 3000);
    expect(find.text('Not synced'), findsOneWidget);
    await snap('workspace_two_clips');
    await tap('set-sync', after: 800);
    expect(find.textContaining('Locked ·'), findsOneWidget);
    await tester.tap(find.text('.25×'));
    await idle(tester, 300);
    await tap('play', after: 2000);
    // Playback really moves in the app (0.25× for 2 s ≈ 0.5 s of clip).
    expect(
      find.text('0:00.00'),
      findsNothing,
      reason: 'both timelines should have advanced',
    );
    await snap('locked_playing_quarter_speed');
    await tap('play', after: 500); // pause
    await tap('step-forward', after: 600);
    await tap('mirror', after: 600);
    await tap('attr-Slope', after: 200);
    await tap('mark-green', after: 600);
    await snap('mirrored_marked');
    await tap('undo', after: 400);
    await tap('mark-green', after: 400);

    // ---- Analyze (no profile yet): real pose on a real swing ---------------
    await back();
    await tap('open-workspace', after: 1000);
    clipQueue.add('$clipDir/cleave.webm');
    await tap('load-A', after: 2000);
    await tap('analyze', after: 500);
    await wait(tester, find.byKey(const Key('analysis-metrics')), seconds: 120);
    await tester.dragUntilVisible(
      find.text('Entry slope'),
      find.byKey(const Key('analysis-metrics')),
      const Offset(0, -150),
    );
    await idle(tester, 300);
    expect(find.text('Entry slope'), findsOneWidget);
    await snap('analyze_measurements');
    await tap('analysis-close');
    await back();

    // Reopen the first review: sync, rate, mirror, marks restored.
    await wait(tester, find.textContaining('Review '));
    await tester.tap(find.textContaining('Review ').last);
    await idle(tester, 2500);
    expect(find.textContaining('Locked ·'), findsOneWidget);
    await snap('reopened_review');
    await back();

    // ---- Reject repeated footage; use the explicitly synthetic package ----
    await tap('build-profile', after: 800);
    await tester.enterText(
      find.byKey(const Key('coach-name')),
      'Duplicate Coach',
    );
    await tap('add-clips', after: 500);
    await wait(
      tester,
      find.text('This recording is already included.'),
      seconds: 120,
    );
    expect(find.text('15 clean clips · enough to build'), findsNothing);
    await snap('builder_duplicates_rejected');
    await back();
    // Generated by tool/make_phone_fixture.dart from StubPoseEstimator.
    // The remaining screens test plumbing, not a learned real-world coach.
    await tester.runAsync(() async {
      final file = '$clipDir/coach_package.zip';
      await applyImport(
        db,
        file,
        await readProfilePackage(file),
        null,
        () async => Directory('${support!.path}/profiles'),
      );
    });
    await wait(tester, find.text('Laptop Coach · v1'));
    await snap('library_with_synthetic_profile');

    debugPrint('e2e synthetic package installed');

    // ---- Compare a clip with the profile --------------------------------
    await tap('open-workspace', after: 1000);
    clipQueue.add('$clipDir/cleave.webm');
    await tap('load-A', after: 1500);
    await tap('analyze', after: 500);
    await wait(tester, find.byKey(const Key('comparison')), seconds: 120);
    expect(find.text('style match with Laptop Coach · v1'), findsOneWidget);
    await snap('comparison');
    final firstDelta = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('delta-'),
    );
    await tester.tap(firstDelta.first);
    await idle(tester, 600);
    await snap('delta_expanded');
    await back();

    // ---- Trend, export --------------------------------------------------
    final row = (await tester.runAsync(db.allProfiles))!.single;
    final id = '${row.profileId}-${row.version}';
    await wait(tester, find.text('Laptop Coach · v1')); // back in the Library
    await idle(tester, 800);
    await tap('trend-$id', after: 1500);
    await wait(tester, find.text('Style match by session'));
    await snap('trend');
    await back();
    await tap('export-$id', after: 500);
    await wait(tester, find.byKey(const Key('export-summary')), seconds: 20);
    await tester.tap(find.byKey(const Key('export-choice-withMarks')));
    await idle(tester, 1000);
    await snap('export_dialog');
    await tap('export-save', after: 1500);
    expect(saved, hasLength(1));

    // ---- Workbench: harness on coach clips ------------------------------
    await tap('workbench-$id', after: 1500);
    await tap('add-probe-clips', after: 500);
    await wait(tester, find.text('1 clips'), seconds: 600);
    await tap('run-harness', after: 1000);
    await wait(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w.key == const Key('patch-accepted') ||
            w.key == const Key('patch-rejected'),
      ),
    );
    await snap('workbench_harness');

    // ---- CARNE ASADA -----------------------------------------------------
    await tap('open-carne', after: 1500);
    await tap('choose-files', after: 500);
    await wait(tester, find.textContaining('Found '), seconds: 120);
    await idle(tester, 3000);
    await snap('carne_asada');
    await back();
    await back();

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      final d = Directory('${support!.path}/profiles');
      if (d.existsSync()) {
        for (final f in d.listSync()) {
          if (!storeBefore!.contains(f.path)) f.deleteSync();
        }
      }
      await work.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 40)));
}
