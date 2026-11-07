import 'package:flutter/material.dart';

/// Product colors. Red and green belong to explicit human feedback.
abstract final class SvColors {
  static const chalk = Color(0xFFF4F3EF);
  static const graphite = Color(0xFF111416);
  static const slate = Color(0xFF20262B);
  static const ink = Color(0xFF182025);
  static const white = Color(0xFFF5F4F0);
  static const cobalt = Color(0xFF315DDF);
  static const paleCobalt = Color(0xFF91AEFF);
  static const good = Color(0xFF247A46);
  static const needsWork = Color(0xFFB83A36);
}

abstract final class SvTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? SvColors.graphite : SvColors.chalk;
    final surface = dark ? SvColors.slate : Colors.white;
    final ink = dark ? SvColors.white : SvColors.ink;
    final secondary = dark ? const Color(0xFFAFB8BF) : const Color(0xFF58656F);
    final accent = dark ? SvColors.paleCobalt : SvColors.cobalt;
    final outline = dark ? const Color(0xFF84919C) : const Color(0xFF6C7883);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: SvColors.cobalt,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: dark ? SvColors.graphite : SvColors.white,
          primaryContainer: SvColors.cobalt,
          onPrimaryContainer: SvColors.white,
          secondary: accent,
          onSecondary: dark ? SvColors.graphite : SvColors.white,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: secondary,
          surfaceContainerLowest: canvas,
          surfaceContainerLow: canvas,
          surfaceContainer: surface,
          surfaceContainerHigh: dark
              ? const Color(0xFF293139)
              : const Color(0xFFECEEEB),
          surfaceContainerHighest: dark
              ? const Color(0xFF293139)
              : const Color(0xFFECEEEB),
          outline: outline,
          outlineVariant: dark
              ? const Color(0xFF3A454E)
              : const Color(0xFFD5DADF),
          error: dark ? const Color(0xFFFFB4AB) : SvColors.needsWork,
        );
    TextStyle body(double size, [FontWeight weight = FontWeight.w400]) =>
        TextStyle(
          fontFamily: 'Source Sans 3',
          fontSize: size,
          height: 1.3,
          fontWeight: weight,
          color: ink,
        );
    TextStyle heading(double size) => TextStyle(
      fontFamily: 'Barlow Semi Condensed',
      fontSize: size,
      height: 1.12,
      fontWeight: FontWeight.w700,
      color: ink,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Source Sans 3',
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: TextTheme(
        displayLarge: heading(48),
        displayMedium: heading(40),
        displaySmall: heading(32),
        headlineLarge: heading(40),
        headlineMedium: heading(30),
        headlineSmall: heading(24),
        titleLarge: heading(24),
        titleMedium: body(18, FontWeight.w600),
        titleSmall: body(16, FontWeight.w600),
        bodyLarge: body(16),
        bodyMedium: body(16),
        bodySmall: body(14).copyWith(color: secondary),
        labelLarge: body(16, FontWeight.w600),
        labelMedium: body(14, FontWeight.w600),
        labelSmall: body(14),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: heading(24),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SvColors.cobalt,
          foregroundColor: SvColors.white,
          minimumSize: const Size(48, 48),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: outline),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 48),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: outline,
        trackHeight: 3,
      ),
    );
  }
}

class SvWordmark extends StatelessWidget {
  const SvWordmark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Strathvision',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'STRATHVISION',
          style: TextStyle(
            fontFamily: 'Barlow Semi Condensed',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: 32,
          height: 3,
          child: ColoredBox(color: SvColors.cobalt),
        ),
      ],
    ),
  );
}
