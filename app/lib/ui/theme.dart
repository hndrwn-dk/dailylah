import 'package:flutter/material.dart';

/// DailyLah design tokens.
///
/// Concept: Singapore transit signage. Bus numbers sit on solid plates like the
/// stop poles, MRT lines use their official colours, and everything else stays
/// quiet so the plates and line chips carry the screen.
class DL {
  // Base palette
  static const ink = Color(0xFF1B2A41); // slate-blue text
  static const paper = Color(0xFFF5F8FA); // cool white background
  static const teal = Color(0xFF0F7C8C); // monsoon teal, primary
  static const amber = Color(0xFFF2A33A); // kopi amber, alerts only
  static const mint = Color(0xFFDDF2EC); // HDB mint, quiet surfaces
  static const mist = Color(0xFF8A97A8); // secondary text

  // Dark counterparts
  static const night = Color(0xFF0E1726);
  static const nightSurface = Color(0xFF172235);
  static const tealLight = Color(0xFF4FC1CF);

  static const display = 'BarlowCondensed';
  static const body = 'PlusJakartaSans';

  /// Official MRT/LRT line colours.
  static const lineColors = <String, Color>{
    'NSL': Color(0xFFD42E12),
    'EWL': Color(0xFF009645),
    'CCL': Color(0xFFFA9E0D),
    'DTL': Color(0xFF005EC4),
    'NEL': Color(0xFF9900AA),
    'TEL': Color(0xFF9D5B25),
    'BPL': Color(0xFF748477),
    'SLRT': Color(0xFF748477),
    'PLRT': Color(0xFF748477),
  };

  static Color lineColor(String code) => lineColors[code] ?? mist;
}

TextStyle _jakarta(double size, double weight, Color color, {double height = 1.4}) => TextStyle(
      fontFamily: DL.body,
      fontSize: size,
      height: height,
      color: color,
      fontVariations: [FontVariation.weight(weight)],
    );

TextTheme _textTheme(Color ink, Color muted) => TextTheme(
      // Display styles use the signage face.
      displayLarge: TextStyle(
          fontFamily: DL.display, fontWeight: FontWeight.w700, fontSize: 56, height: 1, color: ink),
      displayMedium: TextStyle(
          fontFamily: DL.display, fontWeight: FontWeight.w700, fontSize: 40, height: 1, color: ink),
      displaySmall: TextStyle(
          fontFamily: DL.display, fontWeight: FontWeight.w600, fontSize: 30, height: 1.05, color: ink),
      headlineSmall: _jakarta(22, 700, ink, height: 1.25),
      titleLarge: _jakarta(19, 700, ink, height: 1.3),
      titleMedium: _jakarta(16, 650, ink, height: 1.35),
      titleSmall: _jakarta(14, 650, ink),
      bodyLarge: _jakarta(16, 420, ink, height: 1.5),
      bodyMedium: _jakarta(14, 420, ink, height: 1.5),
      bodySmall: _jakarta(12.5, 420, muted, height: 1.45),
      labelLarge: _jakarta(14, 600, ink),
      labelMedium: _jakarta(12.5, 600, ink),
      labelSmall: _jakarta(11.5, 600, muted),
    );

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFE8EEF5) : DL.ink;
  final muted = dark ? const Color(0xFF93A1B4) : DL.mist;
  final scheme = ColorScheme.fromSeed(
    seedColor: DL.teal,
    brightness: brightness,
    primary: dark ? DL.tealLight : DL.teal,
    secondary: DL.amber,
    surface: dark ? DL.night : DL.paper,
    onSurface: ink,
  ).copyWith(
    surfaceContainerLowest: dark ? DL.nightSurface : Colors.white,
    surfaceContainerLow: dark ? DL.nightSurface : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1D2A40) : const Color(0xFFEDF2F5),
    surfaceContainerHighest: dark ? const Color(0xFF243350) : DL.mint,
    outlineVariant: dark ? const Color(0xFF2A3A55) : const Color(0xFFE1E8EE),
  );
  final text = _textTheme(ink, muted);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    fontFamily: DL.body,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall!.copyWith(color: ink)),
      height: 68,
    ),
    chipTheme: ChipThemeData(
      labelStyle: text.labelMedium,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
