import 'package:analysis_engine/analysis_engine.dart';

/// Neutral stand-in pack used until a real domain pack is installed (Phase 6).
/// Packs supply the attribute list, phases, and metric catalog; app code
/// never hard-codes domain terms.
class PackInfo {
  const PackInfo({
    required this.packId,
    required this.topAttributes,
    required this.moreAttributes,
    required this.analysis,
    this.phaseLabels = const {},
    this.metricLabels = const {},
  });

  final String packId;

  /// Offered in the chip row on first use (pack's top 3–4).
  final List<String> topAttributes;

  /// Short predefined list behind the chip row's "+".
  final List<String> moreAttributes;

  /// The pack's analysis section, read by `AnalysisPack.fromJson`.
  final Map<String, Object?> analysis;

  /// Display labels from the pack. Missing labels fall back to the id.
  final Map<String, String> phaseLabels;
  final Map<String, String> metricLabels;

  AnalysisPack get analysisPack => AnalysisPack.fromJson(analysis);

  String phaseLabel(String id) => phaseLabels[id] ?? id;
  String metricLabel(String key) => metricLabels[key] ?? key;
}

const placeholderPack = PackInfo(
  packId: 'placeholder',
  topAttributes: ['Timing', 'Position', 'Path', 'Balance'],
  moreAttributes: ['Rhythm', 'Posture', 'Range'],
  analysis: {
    'pack_id': 'placeholder',
    'event_id': 'placeholder',
    'metric_schema_version': 'placeholder-1',
    'phases': ['phase_1', 'phase_2', 'phase_3'],
    'metrics': [
      {
        'key': 'lead_elbow_angle',
        'kind': 'joint_angle',
        'phase': 'phase_1',
        'unit': '°',
        'joints': ['left_shoulder', 'left_elbow', 'left_wrist'],
      },
      {
        'key': 'lead_knee_range',
        'kind': 'joint_range',
        'phase': 'phase_2',
        'unit': '°',
        'joints': ['left_hip', 'left_knee', 'left_ankle'],
      },
      {
        'key': 'implement_inclination',
        'kind': 'implement_inclination',
        'phase': 'phase_2',
        'unit': '°',
      },
      {
        'key': 'phase_3_duration',
        'kind': 'phase_duration',
        'phase': 'phase_3',
        'unit': 's',
      },
    ],
  },
  phaseLabels: {'phase_1': 'Phase 1', 'phase_2': 'Phase 2', 'phase_3': 'Phase 3'},
  metricLabels: {
    'lead_elbow_angle': 'Lead elbow angle',
    'lead_knee_range': 'Lead knee range',
    'implement_inclination': 'Implement angle',
    'phase_3_duration': 'Phase 3 length',
  },
);
