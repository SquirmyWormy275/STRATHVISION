import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/services.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/packs/placeholder_pack.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/profile_package.dart';
import 'package:strathvision/workbench/carne_controller.dart';
import 'package:strathvision/workbench/carne_run.dart';

/// Synthetic measurement fixtures for controller/UI tests, never research data.
class CarneFixture {
  CarneFixture(this.info, this.profile);
  final PackInfo info;
  final Profile profile;

  static Future<CarneFixture> load() async {
    final info = activePack(await loadPacks(rootBundle), 'timber/underhand');
    final builder = ProfileBuilder(
      engine: AnalysisEngine(
        pack: info.analysisPack,
        pose: const StubPoseEstimator(styleSeed: 42),
      ),
    );
    final clips = await Future.wait([
      for (var i = 0; i < 15; i++)
        builder.evaluate(
          ClipSource(
            clipId: 'ref-$i',
            path: '/fixture',
            durationMs: 6000,
            fps: 30,
          ),
          displayName: 'Fixture $i',
        ),
    ]);
    final profile = (builder.build(
      coachName: 'Synthetic fixture',
      clips: clips,
      newProfileId: 'fixture-profile',
      now: DateTime.utc(2026, 11, 4),
    ) as BuildReady).profile;
    return CarneFixture(info, profile);
  }

  Future<List<StrokeDetail>> strokes(
    ClipSource clip, {
    double confidence = .85,
  }) => AnalysisEngine(
    pack: info.analysisPack,
    pose: StubPoseEstimator(styleSeed: 7, confidence: confidence),
  ).analyzeStrokes(clip);

  CarneController controller({
    StrokeAnalyzer? analyze,
    ClipProber? probe,
    MarksLookup? marks,
    ResearchWriter? write,
    ClipFingerprinter? fingerprint,
    DateTime Function()? clock,
    double confidence = .85,
  }) => CarneController(
    pack: info.analysisPack,
    attributes: [...info.topAttributes, ...info.moreAttributes],
    bundle: ProfileBundle(profile: profile, patchFiles: const {}),
    analyze: analyze ?? (clip) => strokes(clip, confidence: confidence),
    probe: probe ?? (path) async => const ClipInfo(durationMs: 60000, fps: 30),
    marks: marks ?? (path) async => [],
    write:
        write ??
        (profile, patches, adapters, research) async =>
            throw StateError('Unexpected profile save'),
    fingerprint: fingerprint,
    clock: clock ?? () => DateTime.utc(2026, 11, 4),
    phaseLabel: info.phaseLabel,
    metricLabel: info.metricLabel,
    analysisMetadata: const {
      'provider': 'synthetic_test_fixture',
      'synthetic': true,
    },
  );
}
