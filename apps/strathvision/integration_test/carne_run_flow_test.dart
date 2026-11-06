// Native Linux UI/export and real-pose cache checks. Measurement fixtures in
// the first test are explicitly synthetic; the second uses the licensed clip.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/vision/pose_service.dart';

import '../test/support/carne_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  const out = String.fromEnvironment('OUT');
  const clipDir = String.fromEnvironment('CLIP_DIR');

  testWidgets(
    'native CARNE exports an unchanged run and shows duplicate/failure outcomes',
    (tester) async {
      expect(out, isNotEmpty);
      final fixture = await tester.runAsync(CarneFixture.load);
      final work = await tester.runAsync(
        () => Directory.systemTemp.createTemp('carne_native_'),
      );
      final paths = <String>[];
      await tester.runAsync(() async {
        for (final row in [
          ('one', 'a'),
          ('copy', 'a'),
          ('broken', 'invalid'),
          ('two', 'b'),
          ('three', 'c'),
        ]) {
          final file = File('${work!.path}/${row.$1}.mov');
          await file.writeAsString(row.$2);
          paths.add(file.path);
        }
      });
      var profileWrites = 0;
      final c = fixture!.controller(
        probe: (path) async => path.endsWith('broken.mov')
            ? null
            : const ClipInfo(durationMs: 60000, fps: 30),
        write: (profile, patches, adapters, research) async {
          profileWrites++;
          return 'unexpected';
        },
      );
      final shot = GlobalKey();
      final reportFile = File('$out/native-zero-edit-run.json');
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: MaterialApp(
            home: CarneScreen(
              controller: c,
              title: 'Research run check',
              pickFiles: () async => paths,
              saveExperiment: (name, contents) async {
                await reportFile.parent.create(recursive: true);
                await reportFile.writeAsString(contents, flush: true);
                return reportFile.path;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('choose-files')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-files')));
      for (
        var tries = 0;
        tries < 200 &&
            (c.busy || (c.runReport()['inputs'] as List).length < paths.length);
        tries++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(c.busy, isFalse);
      expect(c.stopReason, 'no marks');
      expect(c.runReport()['sources'] as List, hasLength(3));
      expect(c.session.edits, isEmpty);
      expect(
        find.textContaining('Waiting for coach or athlete feedback'),
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
      for (var tries = 0; tries < 100 && !c.runSaved; tries++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(c.runSaved, isTrue);
      final text = await tester.runAsync(reportFile.readAsString);
      final report = jsonDecode(text!) as Map;
      final inputs = report['inputs'] as List;
      expect(inputs.where((i) => i['status'] == 'duplicate'), hasLength(1));
      expect(inputs.where((i) => i['status'] == 'invalid_video'), hasLength(1));
      expect((report['session'] as Map)['edits'], isEmpty);
      expect(report['analysis_pipeline']['synthetic'], isTrue);
      expect(profileWrites, 0);
      expect(find.text('Experiment saved'), findsOneWidget);
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      );
      final png = await image!.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(
        () =>
            File('$out/native-run-screen.png')
                .writeAsBytes(png!.buffer.asUint8List()),
      );
      image.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => work!.delete(recursive: true));
    },
  );

  testWidgets('real pose cache honors content keys at an unchanged path', (
    tester,
  ) async {
    expect(clipDir, isNotEmpty);
    await tester.runAsync(() async {
      final path = '$clipDir/cleave.webm';
      final info = await probeClip(path);
      expect(info, isNotNull);
      final source = ClipSource(
        clipId: 'same-clip',
        path: path,
        durationMs: info!.durationMs < 2000 ? info.durationMs : 2000,
        fps: info.fps,
      );
      final service = PoseService(maxSamples: 12);
      var progress = 0;
      final first = await service.track(
        source,
        sourceKey: 'first-content',
        onProgress: (_) => progress++,
      );
      expect(progress, greaterThan(0));
      expect(first.frames, isNotEmpty);
      progress = 0;
      final cached = await service.track(
        source,
        sourceKey: 'first-content',
        onProgress: (_) => progress++,
      );
      expect(identical(first, cached), isTrue);
      expect(progress, 0);
      final changed = await service.track(
        source,
        sourceKey: 'changed-content',
        onProgress: (_) => progress++,
      );
      expect(progress, greaterThan(0));
      expect(identical(first, changed), isFalse);
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
