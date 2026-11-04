import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/services.dart';

import 'placeholder_pack.dart';

/// Directory of bundled pack files. Any `*.json` here is loaded at startup;
/// adding or swapping a pack needs no code change.
const packAssetDir = 'assets/packs/';

/// The built-in placeholder plus every pack file bundled with the app.
/// Files that fail validation are skipped (and reported in debug output).
Future<List<PackDefinition>> loadPacks(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final files = manifest
      .listAssets()
      .where((a) => a.startsWith(packAssetDir) && a.endsWith('.json'))
      .toList()
    ..sort();
  final packs = <PackDefinition>[placeholderDefinition];
  for (final f in files) {
    try {
      final def = PackDefinition.parse(await bundle.loadString(f));
      if (packs.every((p) => p.packId != def.packId)) packs.add(def);
    } on AnalysisError catch (e) {
      // ignore: avoid_print
      print('Skipping pack $f: $e ${e.details}');
    }
  }
  return packs;
}

/// The active event: the saved choice if it still exists, else the first
/// event of the first domain pack, else the placeholder.
PackInfo activePack(List<PackDefinition> packs, String? savedKey) {
  final all = PackInfo.all(packs);
  return all.where((p) => p.key == savedKey).firstOrNull ??
      all.where((p) => p.packId != placeholderDefinition.packId).firstOrNull ??
      all.firstOrNull ??
      placeholderPack;
}
