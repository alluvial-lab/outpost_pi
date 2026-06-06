import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografia do Cockpit — espelha o design: Space Grotesk (display/títulos),
/// Hanken Grotesk (UI/texto), JetBrains Mono (código). Servidas via
/// `google_fonts` (runtime + cache), sem bundle de .ttf.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.display,
    required this.title,
    required this.body,
    required this.label,
    required this.tab,
    required this.mono,
  });

  /// Space Grotesk — títulos grandes (heading do transcript).
  final TextStyle display;

  /// Space Grotesk — nomes de workspace/aba/seção.
  final TextStyle title;

  /// Hanken Grotesk — corpo do transcript e inputs.
  final TextStyle body;

  /// Hanken Grotesk — rótulos pequenos.
  final TextStyle label;

  /// Space Grotesk — texto das abas.
  final TextStyle tab;

  /// JetBrains Mono — código, args de tool, métricas.
  final TextStyle mono;

  factory AppTypography.build() {
    final display = GoogleFonts.spaceGrotesk();
    final ui = GoogleFonts.hankenGrotesk();
    final mono = GoogleFonts.jetBrainsMono();
    return AppTypography(
      display: display.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      title: display.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      body: ui.copyWith(fontSize: 14.5, height: 1.6),
      label: ui.copyWith(fontSize: 12, height: 1.3),
      tab: display.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      mono: mono.copyWith(fontSize: 12.5, height: 1.55),
    );
  }

  @override
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

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      display: TextStyle.lerp(display, other.display, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      tab: TextStyle.lerp(tab, other.tab, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}
