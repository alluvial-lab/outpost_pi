import 'package:flutter/widgets.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'cockpit_theme.dart';
import 'syntax_colors.dart';

// Construct the typography fallback once for widgets outside the theme tree.
final AppTypography _fallbackTypo = AppTypography.build();

/// Access shared Cockpit theme tokens from any widget context.
///
/// Reads tokens from the root-installed [CockpitTheme]. Outside that tree, such
/// as in a minimal widget test, falls back to the default dark color and syntax
/// palettes and a cached default typography rather than throwing.
extension AppThemeX on BuildContext {
  AppColors get colors => CockpitTheme.maybeOf(this)?.colors ?? AppColors.dark;

  AppTypography get typo => CockpitTheme.maybeOf(this)?.typo ?? _fallbackTypo;

  SyntaxColors get syntax =>
      CockpitTheme.maybeOf(this)?.syntax ?? SyntaxColors.dark;
}
