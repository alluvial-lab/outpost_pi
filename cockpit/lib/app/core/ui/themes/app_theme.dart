import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/themes/app_colors.dart';
import 'package:cockpit/app/core/ui/themes/app_typography.dart';
import 'package:cockpit/app/core/ui/themes/syntax_colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Bundle bespoke color, typography, and syntax tokens for effective settings.
///
/// The root computes these tokens for its `brightness` and `settings`, installs
/// them through `CockpitTheme`, and exposes them through `context.colors`,
/// `context.typo`, and `context.syntax`.
typedef CockpitTokens = ({
  AppColors colors,
  AppTypography typo,
  SyntaxColors syntax,
});

/// Build bespoke tokens for [brightness] and [settings].
CockpitTokens buildTokens({
  required Brightness brightness,
  AppSettings settings = const AppSettings(),
}) {
  final colors = brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
  final typo = AppTypography.build(
    uiFont: settings.interfaceFont,
    monoFont: settings.codeFont,
    codeSize: settings.codeSize,
  );
  final syntax = SyntaxColors.forId(settings.syntaxTheme, brightness);
  return (colors: colors, typo: typo, syntax: syntax);
}

/// Build shadcn `ThemeData` for [brightness].
///
/// Derives the palette from [AppColors], keeping shadcn components and custom
/// widgets consistent. Applies [settings] where shadcn has an equivalent slot;
/// fonts and syntax colors travel through `CockpitTheme`.
ThemeData buildTheme({
  required Brightness brightness,
  AppSettings settings = const AppSettings(),
}) {
  final colors = brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
  // Reuse AppTypography font resolution (Space Mono or configured fonts)
  // and pass only the family to shadcn Typography. Every shadcn component then
  // inherits Cockpit typography: ShadcnApp installs `typography.sans` in the
  // root DefaultTextStyle, while .h3/.base/etc. only adjust size and weight.
  final appTypo = AppTypography.build(
    uiFont: settings.interfaceFont,
    monoFont: settings.codeFont,
    codeSize: settings.codeSize,
  );
  return ThemeData(
    colorScheme: _schemeFrom(colors, brightness),
    // Match the design's softly rounded corners rather than pill shapes.
    radius: 0.5,
    typography: Typography.geist(
      sans: TextStyle(
        fontFamily: appTypo.body.fontFamily,
        fontFamilyFallback: appTypo.body.fontFamilyFallback,
      ),
      mono: TextStyle(
        fontFamily: appTypo.mono.fontFamily,
        fontFamilyFallback: appTypo.mono.fontFamilyFallback,
      ),
    ),
  );
}

/// Map Cockpit tokens into shadcn `ColorScheme` semantic slots.
///
/// Tokens without equivalent slots remain available through `context.colors`.
/// `chart1..5` inherit from the base zinc palette.
ColorScheme _schemeFrom(AppColors c, Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ColorSchemes.darkZinc
      : ColorSchemes.lightZinc;
  return ColorScheme(
    brightness: brightness,
    background: c.bg,
    foreground: c.text,
    card: c.panel,
    cardForeground: c.text,
    popover: c.panel,
    popoverForeground: c.text,
    // "primary" is the phosphor beacon; foreground follows the mode contract.
    primary: c.accent,
    primaryForeground: c.onAccent,
    // "secondary" is the neutral surface for secondary buttons.
    secondary: c.panel3,
    secondaryForeground: c.text2,
    muted: c.panel2,
    mutedForeground: c.text2,
    // In shadcn, "accent" is a neutral hover/selection surface, not the brand.
    accent: c.panel3,
    accentForeground: c.text,
    destructive: c.error,
    destructiveForeground: Colors.white,
    border: c.border,
    input: c.border,
    // Use the brand color for focus rings.
    ring: c.accent,
    chart1: base.chart1,
    chart2: base.chart2,
    chart3: base.chart3,
    chart4: base.chart4,
    chart5: base.chart5,
  );
}
