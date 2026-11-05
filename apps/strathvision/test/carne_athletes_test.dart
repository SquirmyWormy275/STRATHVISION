import 'dart:io';
import 'dart:typed_data';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/vision/athlete.dart';
import 'package:strathvision/vision/pose_service.dart';
import 'package:strathvision/vision/person_detector.dart';
import 'package:strathvision/workbench/carne_athletes.dart';
import 'package:strathvision/workbench/carne_controller.dart';

import 'support/carne_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarneFixture fixture;
  setUpAll(() async => fixture = await CarneFixture.load());

  test(
    'desktop sample policy preserves swing timing on the longest Gurr source',
    () {
      final longestFrames = (1718.929 * 30).ceil();
      expect(carnePoseService.maxSampleRate, 30);
      expect(carnePoseService.maxSamples, greaterThan(longestFrames));
    },
  );

  Future<({CarneController controller, String path, CarneAthleteState state})>
  setup() async {
    final dir = await Directory.systemTemp.createTemp('carne_athlete_');
    addTearDown(() => dir.delete(recursive: true));
    final path = (File(
      '${dir.path}/clip.mov',
    )..writeAsStringSync('synthetic fixture bytes')).path;
    final state = CarneAthleteState();
    final c = fixture.controller(
      athletes: state,
      analyze: (clip) async {
        final target = state.targets[clip.clipId];
        final result = AthleteTrack(
          track: PoseTrack(fps: 30, frames: const []),
          target: target,
          ambiguous: target == null,
          orientationSure: true,
          candidatesFrame: 0,
          candidates: const [],
        );
        state.record(clip, result);
        if (target == null) throw CarneAthleteChoiceNeeded(clip, result);
        return fixture.strokes(clip);
      },
    );
    addTearDown(c.dispose);
    return (controller: c, path: path, state: state);
  }

  test('ambiguous source waits; correction replaces measurements and preserves aliases', () async {
    final f = await setup();
    final c = f.controller;
    await c.drop([f.path]);
    final id = (c.runReport()['inputs'] as List).first['clip_id'] as String;
    expect(c.stopReason, 'choose competitor');
    expect(c.session.pile, isEmpty);
    expect(c.canSaveRun, isTrue);
    expect(
      (c.runReport()['inputs'] as List).first['status'],
      'awaiting_competitor',
    );
    await c.chooseAthlete(
      id,
      const AthleteTarget(quarterTurns: 0, frame: 0, x: .4, y: .5),
    );
    expect(c.needsAthleteChoice(id), isFalse);
    final seconds = c.session.usableSeconds, count = c.session.pile.length;
    final copy = await File(f.path)
        .copy('${File(f.path).parent.path}/copy.mov');
    await c.drop([copy.path]);
    await c.chooseAthlete(
      id,
      const AthleteTarget(quarterTurns: 0, frame: 0, x: .6, y: .5),
    );
    expect(c.session.usableSeconds, seconds);
    expect(c.session.pile, hasLength(count));
    final source = (c.runReport()['sources'] as List).single;
    expect(source['paths'], containsAll([f.path, copy.path]));
    expect(source['athlete']['selection'], 'user');
    expect(source['athlete']['target']['x'], .6);
  });

  testWidgets('pending competitor has an enabled correction action on CARNE', (
    tester,
  ) async {
    final f = await tester.runAsync(setup);
    final c = f!.controller;
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CarneScreen(
          controller: c,
          title: 'Synthetic competitor fixture',
          loadPeople: (clip, frame, turns) async => PeopleFrame(
            rgba: Uint8List.fromList(List.filled(400 * 300 * 4, 220)),
            width: 400,
            height: 300,
            people: const [PersonBox(.2, .2, .6, .9, .95)],
          ),
        ),
      ),
    );
    await tester.runAsync(() => c.drop([f.path]));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose the competitor before this experiment can update.'),
      findsWidgets,
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Choose competitor'),
    );
    expect(button.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'Choose competitor'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final image = find.byKey(const Key('athlete-picker-image'));
    final rect = tester.getRect(image);
    await tester.tapAt(
      Offset(rect.left + rect.width * .4, rect.top + rect.height * .5),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('athlete-confirm')));
    for (
      var i = 0;
      i < 200 && (c.busy || c.stopReason == 'choose competitor');
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(c.stopReason, isNot('choose competitor'));
    expect(
      (c.runReport()['sources'] as List).single['athlete']['selection'],
      'user',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
