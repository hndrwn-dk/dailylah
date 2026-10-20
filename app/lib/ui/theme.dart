import 'package:flutter/material.dart';

/// DailyLah design tokens.
///
/// Concept: chunky "sticker" UI. Pale sky paper, near-black ink outlines (2.5 px) and
/// hard offset shadows, so every card and plate looks like a printed label you can
/// press. Bus numbers sit on solid plates like the stop poles; MRT lines keep their
/// official colours; amber is reserved for alerts.
class DL {
  // Base palette
  static const ink = Color(0xFF0F1618); // outlines and text
  static const paper = Color(0xFFE8F3F6); // page background
  static const card = Color(0xFFF4FBFE); // card surface
  static const teal = Color(0xFF0E9488); // primary ("go")
  static const amber = Color(0xFFEDAD2B); // alerts and highlights
  static const stop = Color(0xFFDC4A37); // disruptions
  static const mint = Color(0xFFCFEDEA); // quiet tinted surfaces
  static const mist = Color(0xFF798E95); // secondary text
  static const shield = Color(0xFFA4B9C0);

  // Dark counterparts
  static const night = Color(0xFF0B1214);
  static const nightSurface = Color(0xFF152024);
  static const tealLight = Color(0xFF3CC4B6);
  static const nightEdge = Color(0xFF5E7880);

  static const display = 'BarlowCondensed';
  static const body = 'PlusJakartaSans';

  static const stroke = 2.5;
  static const radius = 16.0;

  /// Outline colour for the current brightness.
  static Color edge(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightEdge : ink;

  /// Hard offset shadow, no blur.
  static List<BoxShadow> hard(BuildContext context, {double d = 4}) =>
      [BoxShadow(color: edge(context), offset: Offset(d, d))];

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
      displayLarge: _jakarta(44, 800, ink, height: 1.0).copyWith(letterSpacing: -1.4),
      displayMedium: _jakarta(32, 800, ink, height: 1.05).copyWith(letterSpacing: -1.0),
      displaySmall: TextStyle(
          fontFamily: DL.display, fontWeight: FontWeight.w600, fontSize: 30, height: 1.05, color: ink),
      headlineSmall: _jakarta(22, 800, ink, height: 1.2).copyWith(letterSpacing: -0.5),
      titleLarge: _jakarta(19, 800, ink, height: 1.25).copyWith(letterSpacing: -0.4),
      titleMedium: _jakarta(16, 800, ink, height: 1.3).copyWith(letterSpacing: -0.3),
      titleSmall: _jakarta(14.5, 750, ink),
      bodyLarge: _jakarta(16, 420, ink, height: 1.5),
      bodyMedium: _jakarta(14, 420, ink, height: 1.5),
      bodySmall: _jakarta(12.5, 420, muted, height: 1.45),
      labelLarge: _jakarta(14, 750, ink),
      labelMedium: _jakarta(12.5, 700, ink),
      labelSmall: _jakarta(11.5, 600, muted),
    );

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFE6F1F4) : DL.ink;
  final muted = dark ? const Color(0xFF8FA6AD) : DL.mist;
  final edge = dark ? DL.nightEdge : DL.ink;
  final card = dark ? DL.nightSurface : DL.card;
  final scheme = ColorScheme.fromSeed(
    seedColor: DL.teal,
    brightness: brightness,
    primary: dark ? DL.tealLight : DL.teal,
    onPrimary: dark ? DL.ink : DL.card,
    secondary: DL.amber,
    error: DL.stop,
    surface: dark ? DL.night : DL.paper,
    onSurface: ink,
  ).copyWith(
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: dark ? const Color(0xFF1B2A2F) : const Color(0xFFDCEBEF),
    surfaceContainerHighest: dark ? const Color(0xFF203338) : DL.mint,
    outline: edge,
    outlineVariant: dark ? const Color(0xFF2B3C41) : const Color(0xFFC9DCE1),
  );
  final text = _textTheme(ink, muted);
  final stroke = BorderSide(color: edge, width: DL.stroke);
  final r12 = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    fontFamily: DL.body,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    // Plain Material cards (dialogs, menus) get the same outline; app cards use Panel.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: card,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DL.radius), side: stroke),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DL.radius), side: stroke),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r12, side: stroke),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DL.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: DL.card),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r12),
    ),
    // Filter-tab look: selected tab is a solid ink block.
    tabBarTheme: TabBarThemeData(
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
      labelColor: dark ? DL.ink : DL.card,
      unselectedLabelColor: muted,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      splashBorderRadius: r12,
      indicator: BoxDecoration(
        color: dark ? DL.tealLight : DL.ink,
        borderRadius: r12,
        border: Border.all(color: edge, width: DL.stroke),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: DL.amber,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: r12,
        side: const BorderSide(color: DL.ink, width: 2),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? DL.ink : muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelSmall!.copyWith(
            color: states.contains(WidgetState.selected) ? ink : muted,
            fontVariations: const [FontVariation.weight(800)],
          )),
      height: 74,
    ),
    chipTheme: ChipThemeData(
      labelStyle: text.labelMedium,
      backgroundColor: card,
      selectedColor: DL.amber,
      checkmarkColor: DL.ink,
      side: BorderSide(color: edge, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1.5),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(edge),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DL.card : edge),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DL.teal : card),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: dark ? DL.tealLight : DL.ink,
        foregroundColor: dark ? DL.ink : DL.card,
        side: stroke,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: r12),
        textStyle: text.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: card,
        foregroundColor: ink,
        side: stroke,
        shape: RoundedRectangleBorder(borderRadius: r12),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: dark ? DL.tealLight : DL.teal, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: r12, borderSide: stroke),
      enabledBorder: OutlineInputBorder(borderRadius: r12, borderSide: stroke),
      focusedBorder: OutlineInputBorder(borderRadius: r12, borderSide: stroke.copyWith(color: scheme.primary)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
