import 'package:flutter/material.dart';

enum AppThemeId {
  governmentBlue,
  gramGreen,
  saffronOrange,
  royalPurple,
  tealCyan,
  crimsonRed,
}

extension AppThemeIdLabel on AppThemeId {
  String get label => switch (this) {
    AppThemeId.governmentBlue => 'Government Blue',
    AppThemeId.gramGreen => 'Gram Green',
    AppThemeId.saffronOrange => 'Saffron Orange',
    AppThemeId.royalPurple => 'Royal Purple',
    AppThemeId.tealCyan => 'Teal Cyan',
    AppThemeId.crimsonRed => 'Crimson Red',
  };

  String get description => switch (this) {
    AppThemeId.governmentBlue => 'Official and dependable',
    AppThemeId.gramGreen => 'Growth and village development',
    AppThemeId.saffronOrange => 'Energy and progress',
    AppThemeId.royalPurple => 'Modern and creative',
    AppThemeId.tealCyan => 'Digital and inclusive',
    AppThemeId.crimsonRed => 'Leadership and impact',
  };
}

class BrandPalette {
  const BrandPalette({
    required this.seed,
    required this.secondary,
    required this.tertiary,
  });

  final Color seed;
  final Color secondary;
  final Color tertiary;
}

const brandPalettes = <AppThemeId, BrandPalette>{
  AppThemeId.governmentBlue: BrandPalette(
    seed: Color(0xFF1557A6),
    secondary: Color(0xFF0C376E),
    tertiary: Color(0xFFFFC928),
  ),
  AppThemeId.gramGreen: BrandPalette(
    seed: Color(0xFF187A45),
    secondary: Color(0xFF0C5634),
    tertiary: Color(0xFF9BCB45),
  ),
  AppThemeId.saffronOrange: BrandPalette(
    seed: Color(0xFFE87513),
    secondary: Color(0xFFB94A0B),
    tertiary: Color(0xFFFFC247),
  ),
  AppThemeId.royalPurple: BrandPalette(
    seed: Color(0xFF6530C9),
    secondary: Color(0xFF45208F),
    tertiary: Color(0xFFB88AF5),
  ),
  AppThemeId.tealCyan: BrandPalette(
    seed: Color(0xFF087F83),
    secondary: Color(0xFF075B68),
    tertiary: Color(0xFF38C5C8),
  ),
  AppThemeId.crimsonRed: BrandPalette(
    seed: Color(0xFFC62838),
    secondary: Color(0xFF8F1728),
    tertiary: Color(0xFFFF8A8A),
  ),
};

ThemeData buildAppTheme(AppThemeId themeId, Brightness brightness) {
  final palette = brandPalettes[themeId]!;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.seed,
    secondary: palette.secondary,
    tertiary: palette.tertiary,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}
