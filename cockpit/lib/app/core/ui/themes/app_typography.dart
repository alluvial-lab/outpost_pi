import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Define Cockpit's mono-native Space Mono typography.
///
/// Display, body, labels, tabs, and code share one 400/700 family served and
/// cached by `google_fonts` without bundled `.ttf` files.
@immutable
class AppTypography {
  const AppTypography({
    required this.display,
    required this.title,
    required this.body,
    required this.label,
    required this.tab,
    required this.mono,
  });

  /// Space Mono for large transcript headings.
  final TextStyle display;

  /// Space Mono for workspace, tab, and section names.
  final TextStyle title;

  /// Space Mono for transcript body text and inputs.
  final TextStyle body;

  /// Space Mono for small labels.
  final TextStyle label;

  /// Space Mono for tab text.
  final TextStyle tab;

  /// Space Mono for code, tool arguments, and metrics.
  final TextStyle mono;

  /// Build typography from design defaults or configured font families.
  ///
  /// Empty [uiFont] and [monoFont] values retain Space Mono; non-empty values
  /// resolve through the operating system.
  /// [codeSize] controls monospace text. Interface scaling is applied globally
  /// through `MediaQuery.textScaler`, not here.
  factory AppTypography.build({
    String? uiFont,
    String? monoFont,
    double codeSize = 13,
  }) {
    final hasUi = uiFont != null && uiFont.trim().isNotEmpty;
    final hasMono = monoFont != null && monoFont.trim().isNotEmpty;
    // A configured interface font replaces Space Mono for UI roles; code keeps
    // its independently configurable family.
    final TextStyle displayBase = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.spaceMono(fontWeight: FontWeight.w700);
    final TextStyle ui = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.spaceMono();
    final TextStyle mono = hasMono
        ? TextStyle(fontFamily: monoFont)
        : GoogleFonts.spaceMono();

    return AppTypography(
      display: displayBase.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      title: displayBase.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      body: ui.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      label: ui.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
      ),
      tab: displayBase.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
      mono: mono.copyWith(
        fontSize: codeSize,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
    );
  }

  AppTypography copyWith({
    TextStyle? display,
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
    TextStyle? tab,
    TextStyle? mono,
  }) {
    return AppTypography(
      display: display ?? this.display,
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
      tab: tab ?? this.tab,
      mono: mono ?? this.mono,
    );
  }
}
