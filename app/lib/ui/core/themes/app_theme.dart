import 'package:flutter/material.dart';

import 'package:app/ui/core/themes/app_colors.dart';
import 'package:app/ui/core/themes/app_typography.dart';

/// Builds the [ThemeData] for a given [AppColors] / [AppTypography] pair.
///
/// Wires the semantic tokens into both the standard Material [ColorScheme]
/// (so framework widgets — dialogs, switches, progress indicators, text
/// fields — render correctly per brightness) AND attaches [AppColors] /
/// [AppTypography] as theme extensions (so app widgets read
/// `context.colors.*` / `context.typo.*`).
ThemeData _buildTheme({
  required Brightness brightness,
  required AppColors colors,
  required AppTypography typo,
}) {
  final materialTextTheme = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: kMonoFamily,
    bodyColor: colors.text,
    displayColor: colors.text,
  );
  final textTheme = materialTextTheme.copyWith(
    bodyMedium: typo.sansBody,
    bodySmall: typo.monoSmall,
  );

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      surface: colors.bg,
      onSurface: colors.text,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.muted,
      onSecondary: colors.text,
      error: colors.error,
      onError: colors.onAccent,
      outline: colors.border,
    ),
    dividerColor: colors.border,
    extensions: <ThemeExtension<dynamic>>[colors, typo],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bg,
      foregroundColor: colors.text,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: kSansFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: colors.text,
        letterSpacing: -0.2,
      ),
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(textStyle: textTheme.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(textStyle: textTheme.labelLarge),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(textStyle: textTheme.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.accent, width: 1.2),
      ),
      hintStyle: TextStyle(
        color: colors.muted,
        fontFamily: kMonoFamily,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}

/// Dark-native Phosphor Beacon theme.
ThemeData buildDarkTheme() => _buildTheme(
  brightness: Brightness.dark,
  colors: AppColors.dark,
  typo: AppTypography.dark,
);

/// Light Phosphor Beacon theme.
ThemeData buildLightTheme() => _buildTheme(
  brightness: Brightness.light,
  colors: AppColors.light,
  typo: AppTypography.light,
);
