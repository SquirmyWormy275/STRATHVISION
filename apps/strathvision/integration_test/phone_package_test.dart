// Phase 7/9 on a phone: a laptop-built package (patch + adapters +
// carne_asada/) imports cleanly and drives on-device inference with no LLM.
//   scripts/run_android_player_test.sh "" integration_test/phone_package_test.dart
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/profiles/clip_probe.dart';
import 'package:strathvision/profiles/package_exchange.dart';
import 'package:strathvision/profiles/profile_package.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('laptop package imports and runs on the phone', (tester) async {
    final dir = (await tester.runAsync(getExternalStorageDirectory))!.path;
    // ignore: avoid_print
    print('CLIPS_DIR $dir');
    await tester.runAsync(() async {
      final end = DateTime.now().add(const Duration(seconds: 120));
      while (!File('$dir/coach_package.zip').existsSync() ||
          !File('$dir/clip25.mp4').existsSync() ||
          File('$dir/clip25.mp4').lengthSync() < 1000000) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    final pkg = '$dir/coach_package.zip';

    await tester.runAsync(() async {
      final packs = await loadPacks(rootBundle);
      final pack = activePack(packs, 'timber/underhand').analysisPack;

      // Import into the phone's Library.
      final db = AppDatabase(NativeDatabase.memory());
      final meta = await readProfilePackage(pkg);
      final msg = await applyImport(db, pkg, meta, null,
          () async => Directory('${(await getApplicationSupportDirectory()).path}/profiles'));
      expect(msg, 'Imported Laptop Coach · v1');
      final row = (await db.allProfiles()).single;

      // Phone reads profile, patch, adapters; ignores carne_asada/.
      final bundle = await readProfileBundle(row.sourcePath);
      expect(bundle.patchFiles.keys, ['slope_residual_v1.patch']);
      expect(bundle.adapterFiles.keys.toSet(), {'usable_footage.paw', 'priority_scorer.paw'});
      final patches = loadPatches(bundle.patchFiles, headsFor(pack));
      final adapters = loadAdapters(bundle.adapterFiles, pack, pack.adapters);
      expect(patches.rejected, isEmpty);
      expect(adapters.rejected, isEmpty);

      // On-device inference on a real clip, patched heads, local adapters.
      final info = await probeClip('$dir/clip25.mp4');
      expect(info!.fps, closeTo(25, 0.01));
      final d = await AnalysisEngine(pack: pack, heads: applyPatches(headsFor(pack), patches.applied))
          .analyzeDetailed(
              ClipSource(clipId: 'phone-clip', path: '$dir/clip25.mp4',
                  durationMs: info.durationMs, fps: info.fps),
              reference: {for (final e in bundle.profile.metrics.entries) e.key: e.value.center});
      final v = (d.outcome as AnalysisSuccess).vector;
      final r = (compare(
              vector: v,
              profile: bundle.profile,
              resultId: 'phone-r',
              appliedPatches: patches.appliedNames) as ComparisonSuccess)
          .result;
      expect(validateComparisonResult(r.toJson()), isEmpty);
      expect(r.appliedPatches, ['slope_residual_v1']);
      final x = adapterInputs(v, implementConfidence: d.implementConfidence, comparison: r);
      final usable = adapters.adapters['usable_footage']!.decide(x)['usable'];
      final focus = adapters.adapters['priority_scorer']!.top(x);
      // ignore: avoid_print
      print('phone: score=${r.overallScore} patches=${r.appliedPatches} usable=$usable focus=$focus');
      expect(['Slope', 'Hinge', 'Spacing', 'Path'], contains(focus));
      await db.close();
    });
  });
}
