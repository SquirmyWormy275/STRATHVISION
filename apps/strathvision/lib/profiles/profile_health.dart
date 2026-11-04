import 'package:analysis_engine/analysis_engine.dart';

import '../packs/placeholder_pack.dart';
import 'profile_package.dart';

/// One health indicator for an installed profile.
class HealthItem {
  const HealthItem(this.label, {required this.ok});
  final String label;
  final bool ok;
}

/// Health of an installed profile against the packs on this device:
/// quality gates, clip count, measurement schema, patches, adapters, and
/// how much it has been used.
List<HealthItem> profileHealth({
  required ProfileBundle bundle,
  required List<PackInfo> events,
  required int comparisons,
}) {
  final p = bundle.profile;
  final event = events
      .where((e) => e.packId == p.packId && e.eventId == p.eventId)
      .firstOrNull;
  final items = <HealthItem>[
    HealthItem(p.ready ? 'Ready' : 'Not ready', ok: p.ready),
  ];
  if (event == null) {
    items.add(const HealthItem('Pack not installed', ok: false));
    return items;
  }
  final pack = event.analysisPack;
  items.add(HealthItem('${p.sourceClipCount} of ${pack.minClips} clips',
      ok: p.sourceClipCount >= pack.minClips));
  items.add(p.metricSchemaVersion == pack.metricSchemaVersion
      ? const HealthItem('Up to date', ok: true)
      : const HealthItem('Needs rebuild', ok: false));
  if (bundle.patchFiles.isNotEmpty) {
    final set = loadPatches(bundle.patchFiles, headsFor(pack));
    items.add(set.rejected.isEmpty
        ? HealthItem('Patch ${set.appliedNames.join(', ')}', ok: true)
        : HealthItem('${set.rejected.length} patch rejected', ok: false));
  }
  if (bundle.adapterFiles.isNotEmpty) {
    final set = loadAdapters(bundle.adapterFiles, pack, pack.adapters);
    items.add(set.rejected.isEmpty
        ? HealthItem('${set.adapters.length} adapters', ok: true)
        : const HealthItem('Adapters out of date', ok: false));
  }
  items.add(HealthItem(
      comparisons == 0 ? 'Not used yet' : '$comparisons comparisons', ok: true));
  return items;
}
