import 'package:analysis_engine/analysis_engine.dart';

/// The active pack and event, as the app reads it: attribute chips, labels,
/// and the analysis section. Packs are data; app code never hard-codes
/// domain terms.
class PackInfo {
  PackInfo(this.definition, this.event);

  final PackDefinition definition;
  final PackEvent event;

  String get packId => definition.packId;
  String get eventId => event.eventId;

  /// Setting key for this pack/event.
  String get key => '$packId/$eventId';

  /// "Pack · Event", for pickers.
  String get label => '${definition.name} · ${event.label}';

  /// Offered in the chip row on first use (pack's top 3–4).
  List<String> get topAttributes => definition.topAttributes;

  /// Short predefined list behind the chip row's "+".
  List<String> get moreAttributes => definition.moreAttributes;

  AnalysisPack get analysisPack => event.analysis;

  /// Display labels from the pack. Missing labels fall back to the id.
  String phaseLabel(String id) => definition.phaseLabels[id] ?? id;
  String metricLabel(String key) => definition.metricLabels[key] ?? key;

  /// Every event of every pack, in order.
  static List<PackInfo> all(List<PackDefinition> packs) => [
        for (final d in packs)
          for (final e in d.events) PackInfo(d, e),
      ];
}

/// Built-in neutral pack: used until a domain pack is chosen, and as the
/// fallback when no pack files are installed.
const placeholderPackJson = r'''
{
  "format_version": 1,
  "pack_id": "placeholder",
  "name": "General",
  "attributes": {
    "top": ["Timing", "Position", "Path", "Balance"],
    "more": ["Rhythm", "Posture", "Range"]
  },
  "phase_labels": {"phase_1": "Phase 1", "phase_2": "Phase 2", "phase_3": "Phase 3"},
  "metric_labels": {
    "lead_elbow_angle": "Lead elbow angle",
    "lead_knee_range": "Lead knee range",
    "implement_inclination": "Implement angle",
    "phase_3_duration": "Phase 3 length"
  },
  "events": [
    {
      "event_id": "placeholder",
      "label": "General movement",
      "metric_schema_version": "placeholder-1",
      "phases": ["phase_1", "phase_2", "phase_3"],
      "metrics": [
        {"key": "lead_elbow_angle", "kind": "joint_angle", "phase": "phase_1", "unit": "°",
         "joints": ["left_shoulder", "left_elbow", "left_wrist"]},
        {"key": "lead_knee_range", "kind": "joint_range", "phase": "phase_2", "unit": "°",
         "joints": ["left_hip", "left_knee", "left_ankle"]},
        {"key": "implement_inclination", "kind": "implement_inclination", "phase": "phase_2", "unit": "°"},
        {"key": "phase_3_duration", "kind": "phase_duration", "phase": "phase_3", "unit": "s"}
      ],
      "heads": [
        {"name": "slope_residual", "kind": "mlp_residual", "base": "slope_residual/placeholder/v1",
         "target_metric": "implement_inclination"}
      ],
      "probes": []
    }
  ]
}
''';

final PackDefinition placeholderDefinition =
    PackDefinition.parse(placeholderPackJson);

final PackInfo placeholderPack =
    PackInfo(placeholderDefinition, placeholderDefinition.events.first);
