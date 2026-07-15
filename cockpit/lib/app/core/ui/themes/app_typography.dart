import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Define Cockpit typography to mirror the design.
///
/// Uses Space Grotesk for display and titles, Hanken Grotesk for UI text, and
/// JetBrains Mono for code. Fonts are served and cached by `google_fonts`
/// without bundled `.ttf` files.
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

  /// Space Grotesk for large transcript headings.
  final TextStyle display;

  /// Space Grotesk for workspace, tab, and section names.
  final TextStyle title;

  /// Hanken Grotesk for transcript body text and inputs.
  final TextStyle body;

  /// Hanken Grotesk for small labels.
  final TextStyle label;

  /// Space Grotesk for tab text.
  final TextStyle tab;

  /// JetBrains Mono for code, tool arguments, and metrics.
  final TextStyle mono;

  /// Build typography from design defaults or configured font families.
  ///
  /// Empty [uiFont] and [monoFont] values retain Space Grotesk/Hanken and
  /// JetBrains Mono; non-empty values resolve through the operating system.
  /// [codeSize] controls monospace text. Interface scaling is applied globally
  /// through `MediaQuery.textScaler`, not here.
  factory AppTypography.build({
    String? uiFont,
    String? monoFont,
    double codeSize = 13,
  }) {
    final hasUi = uiFont != null && uiFont.trim().isNotEmpty;
    final hasMono = monoFont != null && monoFont.trim().isNotEmpty;
    // Default display/title text to Space Grotesk and body/labels to Hanken.
    // A configured interface font replaces both families.
    final TextStyle displayBase = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.spaceGrotesk();
    final TextStyle ui = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.hankenGrotesk();
    final TextStyle mono = hasMono
        ? TextStyle(fontFamily: monoFont)
        : GoogleFonts.jetBrainsMono();

    return AppTypography(
      display: displayBase.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      title: displayBase.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      body: ui.copyWith(fontSize: 14.5, height: 1.6),
      label: ui.copyWith(fontSize: 12, height: 1.3),
      tab: displayBase.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      mono: mono.copyWith(fontSize: codeSize, height: 1.55),
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
