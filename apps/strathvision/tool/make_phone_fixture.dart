// Writes integration_test/assets/coach_package.zip: a laptop-built package
// with a specialist patch, two compiled adapters, and a CARNE ASADA record,
// for the on-phone import test. Run: flutter test tool/make_phone_fixture.dart
import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/profiles/profile_export.dart';

void main() {
  test('write fixture', () async {
    final def = PackDefinition.parse(File('assets/packs/timber.json').readAsStringSync());
    final pack = def.event('underhand')!.analysis;
    final b = ProfileBuilder(
        engine: AnalysisEngine(pack: pack, pose: const StubPoseEstimator(styleSeed: 42)));
    final q = await Future.wait([
      for (var i = 0; i < 15; i++)
        b.evaluate(ClipSource(clipId: 'ref-$i', path: '/r', durationMs: 6000, fps: 30),
            displayName: 'r$i'),
    ]);
    final profile = (b.build(
            coachName: 'Laptop Coach',
            clips: q,
            newProfileId: 'laptop-prof',
            now: DateTime.utc(2026, 11, 4)) as BuildReady)
        .profile;
    final patch = SpecialistPatch(
        head: 'slope_residual',
        version: 1,
        base: pack.heads.single.base,
        edits: const [PatchEdit('b2', [], 0.5)]);
    final usable = CompiledAdapter(
      name: 'usable_footage',
      packId: pack.packId,
      eventId: pack.eventId,
      specHash: pack.adapters[0].specHash,
      compiledBy: 'fixture',
      compiledAt: DateTime.utc(2026, 11, 4),
      threshold: 0.5,
      outputs: const {
        'usable': AdapterOutput(bias: -20, weights: {
          'pose_confidence': 10,
          'implement_confidence': 10,
          'phase_confidence.downswing': 6,
          'phase_confidence.entry': 6,
        }),
      },
    );
    final scorer = CompiledAdapter(
      name: 'priority_scorer',
      packId: pack.packId,
      eventId: pack.eventId,
      specHash: pack.adapters[1].specHash,
      compiledBy: 'fixture',
      compiledAt: DateTime.utc(2026, 11, 4),
      outputs: const {
        'Slope': AdapterOutput(bias: 0, weights: {'abs_delta.entry_slope': 0.25, 'abs_delta.downswing_slope': 0.25}),
        'Hinge': AdapterOutput(bias: 0, weights: {'abs_delta.hinge_at_entry': 0.5}),
        'Spacing': AdapterOutput(bias: 0, weights: {'abs_delta.lead_knee_at_entry': 0.25, 'abs_delta.trail_knee_at_entry': 0.25}),
        'Path': AdapterOutput(bias: 0, weights: {'abs_delta.trail_elbow_downswing': 0.25, 'abs_delta.shoulder_lift_backswing': 0.25}),
      },
    );
    final bytes = zipProfilePackage(profile,
        patches: {patch.fileName: jsonEncode(patch.toJson())},
        adapters: {
          usable.fileName: jsonEncode(usable.toJson()),
          scorer.fileName: jsonEncode(scorer.toJson()),
        },
        research: {'mixture_edits_v1.json': '{"format":"carne_asada/1","edits":[]}', 'junk.bin': '{{{'});
    File('integration_test/assets/coach_package.zip').writeAsBytesSync(bytes);
  });
}
