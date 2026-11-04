/// Neutral stand-in pack used until a real domain pack is installed (Phase 6).
/// Packs supply the attribute list; app code never hard-codes domain terms.
class PackInfo {
  const PackInfo({
    required this.packId,
    required this.topAttributes,
    required this.moreAttributes,
  });

  final String packId;

  /// Offered in the chip row on first use (pack's top 3–4).
  final List<String> topAttributes;

  /// Short predefined list behind the chip row's "+".
  final List<String> moreAttributes;
}

const placeholderPack = PackInfo(
  packId: 'placeholder',
  topAttributes: ['Timing', 'Position', 'Path', 'Balance'],
  moreAttributes: ['Rhythm', 'Posture', 'Range'],
);
