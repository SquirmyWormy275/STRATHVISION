import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/profile_export.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/screens/carne_screen.dart';
import 'package:strathvision/workbench/carne_controller.dart';
import 'package:strathvision/workspace/project.dart';

/// Phase 8 acceptance in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PackInfo info;
  late Profile coach;
  final now = DateTime.utc(2026, 11, 4);

  setUpAll(() async {
    final packs = await loadPacks(rootBundle);
    info = activePack(packs, 'timber/underhand');
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: info.analysisPack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    coach = (b.build(coachName: 'Coach', clips: q, newProfileId: 'prof-1', now: now)
            as BuildReady)
        .profile;
  });

  ({Profile profile, Map<String, String> research})? written;
  final notes = <String, String>{};
  CarneController controller({bool marked = true, double conf = 0.85}) {
    final c = CarneController(
      pack: info.analysisPack,
      attributes: [...info.topAttributes, ...info.moreAttributes],
      bundle: ProfileBundle(profile: coach, patchFiles: const {}),
      probe: (path) async => const ClipInfo(durationMs: 60000, fps: 30),
      analyze: (clip) => AnalysisEngine(
              pack: info.analysisPack,
              pose: StubPoseEstimator(styleSeed: 7, confidence: conf))
          .analyzeStrokes(clip),
      // A green Slope mark every half second: the athlete's own good swings.
      marks: (path) async => [
        if (marked)
          for (var t = 0; t < 60000; t += 500)
            Mark(
                markId: 'm$t',
                clipId: 'c',
                timeMs: t,
                attribute: 'Slope',
                label: MarkLabel.green,
                author: MarkAuthor.athlete,
                createdAt: now),
      ],
      phaseLabel: info.phaseLabel,
      clock: () => now,
      write: (profile, patches, adapters, research) async {
        written = (profile: profile, research: research);
        return '/store/v${profile.version}.zip';
      },
      fingerprint: (path) async => sha256.convert(utf8.encode(path)).toString(),
    );
    c.readText = (path) async => notes[path]!;
    return c;
  }

  Future<void> pump(WidgetTester tester, CarneController c, List<String> files) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CarneScreen(controller: c, title: 'Coach · v1', pickFiles: () async => files),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('dropping clips gives the exact status language; edits explain; '
      'undo restores; save writes carne_asada/', (tester) async {
    written = null;
    final c = controller();
    await pump(tester, c, ['/feed/a.mp4', '/feed/b.mp4', '/feed/c.mp4']);
    expect(find.text('Priority is slope. Only slope updates will be considered this session.'),
        findsOneWidget);
    final mixture0 = jsonEncode({for (final e in c.session.mixture.entries) e.key: e.value.toJson()});

    await tap(tester, 'choose-files');
    final texts = c.feed.map((l) => l.text).toList();
    expect(texts.where((t) => RegExp(r'^Found \d+ strokes\. \d+ are clean enough for slope\. Adding them\.$').hasMatch(t)),
        hasLength(3));
    expect(texts.where((t) => t.startsWith('CARNE ASADA accepted an update. ')), isNotEmpty);
    expect(texts.where((t) => RegExp(r'^Session tally: \d+ accepted edits?\. Undo is one click\.$').hasMatch(t)),
        isNotEmpty);
    expect(c.session.edits.length, inInclusiveRange(1, 5));
    for (final e in c.session.edits) {
      expect(find.text(e.explanation), findsWidgets); // "What did it just do?"
      expect(e.explanation, endsWith('.'));
      expect(e.explanation.substring(0, e.explanation.length - 1).contains('. '), isFalse,
          reason: 'one sentence: ${e.explanation}');
      final h = c.session.hull[e.metric]!;
      expect(e.after.center, inInclusiveRange(h.$1, h.$2));
    }
    expect(find.text('${c.session.edits.length} of 5 edits'), findsOneWidget);

    // One-click undo restores the previous mixture.
    while (c.session.edits.isNotEmpty) {
      await tap(tester, 'undo-edit');
    }
    expect(jsonEncode({for (final e in c.session.mixture.entries) e.key: e.value.toJson()}), mixture0);

    await tap(tester, 'try-update');
    expect(c.session.edits, isNotEmpty);
    await tap(tester, 'save-carne');
    final w = written!;
    expect(w.profile.version, 2);
    expect(w.research.keys, ['mixture_edits_v2.json']);
    final log = jsonDecode(w.research.values.single) as Map;
    expect(log['format'], 'carne_asada/1');
    expect((log['edits'] as List).length, c.session.edits.length);
    expect(jsonEncode(w.profile.toJson()['metrics']) != jsonEncode(coach.toJson()['metrics']) ||
            w.profile.referenceClips.any((r) => r.exemplar),
        isTrue, reason: 'the saved version carries the edited mixture');
    expect(w.profile.referenceClips.where((r) => r.exemplar).length, c.session.exemplars.length);
    expect(validateProfile(w.profile.toJson()), isEmpty);
    c.dispose();
  });

  testWidgets('below threshold → use anyway; notes and voice notes', (tester) async {
    final c = controller(marked: false, conf: 0.55);
    notes['/feed/n.txt'] = 'priority: hinge\nignore this clip\n';
    await pump(tester, c, ['/feed/dim.mp4']);
    await tap(tester, 'choose-files');
    expect(find.text(CarneCopy.belowThreshold), findsOneWidget);
    expect(c.session.usableSeconds, 0);
    final sourceId = c.session.pile.first.stroke.clipId;
    await tap(tester, 'use-anyway-$sourceId');
    expect(c.session.usableSeconds, greaterThan(50));

    await c.drop(['/feed/n.txt', '/feed/coach.m4a', '/feed/readme.pdf']);
    await tester.pumpAndSettle();
    final texts = c.feed.map((l) => l.text).toList();
    expect(texts, contains('Priority is hinge. Only hinge updates will be considered this session.'));
    expect(texts, contains('Ignoring dim.'));
    expect(c.session.usableSeconds, 0);
    expect(texts, contains('Received the voice note. Spoken labels need a transcriber on this computer.'));
    expect(texts, contains('Can’t use readme.pdf.'));

    // A coaching package for the same event widens the coach hull.
    final other = Directory.systemTemp.createTempSync('sv_pkg');
    addTearDown(() => other.deleteSync(recursive: true));
    final path = await tester.runAsync(() => storeProfilePackage(
        Profile.fromJson({
          ...coach.toJson(),
          'profile_id': 'other-coach',
          'coach_name': 'Other',
          'reference_clips': [
            {'clip_id': 'o1', 'metrics': {'entry_slope': -20.0}},
          ],
        }),
        other));
    await tester.runAsync(() => c.drop([path!]));
    await tester.pumpAndSettle();
    expect(c.feed.map((l) => l.text), contains('Added 1 coach strokes from Other · v1 to the coach hull.'));
    expect(c.session.hull['entry_slope']!.$2, -20.0);
    c.dispose();
  });

  test('phone inference ignores carne_asada/ completely', () async {
    final dir = Directory.systemTemp.createTempSync('sv_carne');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plain = await storeProfilePackage(coach, Directory('${dir.path}/a'));
    final withResearch = await storeProfilePackage(coach, Directory('${dir.path}/b'),
        research: {
          'mixture_edits_v1.json': '{"format": "carne_asada/1", "edits": []}',
          'garbage.bin': 'not json at all {{{',
        });
    final zip = ZipDecoder().decodeBytes(File(withResearch).readAsBytesSync());
    expect(zip.files.map((f) => f.name), contains('carne_asada/mixture_edits_v1.json'));

    final a = await readProfileBundle(plain);
    final b = await readProfileBundle(withResearch);
    expect(jsonEncode(b.profile.toJson()), jsonEncode(a.profile.toJson()));
    expect(b.patchFiles, isEmpty);
    expect(b.adapterFiles, isEmpty);
    expect((await readProfilePackage(withResearch)).version, 1);

    // Identical comparison either way.
    final v = (await AnalysisEngine(pack: info.analysisPack, pose: const StubPoseEstimator(styleSeed: 7))
            .analyze(const ClipSource(clipId: 'x', path: '/x', durationMs: 6000, fps: 30)))
        as AnalysisSuccess;
    String cmp(ProfileBundle bundle) => jsonEncode(
        {...(compare(vector: v.vector, profile: bundle.profile, resultId: 'r') as ComparisonSuccess)
            .result
            .toJson()});
    expect(cmp(b), cmp(a));
    // The placeholder event is untouched by research files too.
    expect(placeholderPack.analysisPack.adapters, isEmpty);
  });
}
