import 'package:flutter/material.dart';

/// Visuelle Linie: hell, ruhig, viel Weißraum. Petrol als Bedienfarbe,
/// Bernstein als „Licht“-Akzent für aktive Zustände.
class AppTheme {
  static const seed = Color(0xFF0B7A75);
  static const glow = Color(0xFFFFB020);

  static ThemeData light() => _build(ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        surface: const Color(0xFFF7F8FA),
      ));

  static ThemeData dark() => _build(ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        surface: const Color(0xFF111416),
      ));

  static ThemeData _build(ColorScheme s) {
    final base = ThemeData(colorScheme: s, useMaterial3: true);
    final radius = BorderRadius.circular(20);
    return base.copyWith(
      scaffoldBackgroundColor: s.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: s.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: s.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surfaceContainerLowest,
        indicatorColor: s.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        inactiveTrackColor: s.surfaceContainerHighest,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
      dividerTheme: DividerThemeData(color: s.outlineVariant.withValues(alpha: 0.5)),
    );
  }
}
