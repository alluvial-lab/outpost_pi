import 'package:cockpit/ui/core/themes/app_colors.dart';
import 'package:cockpit/ui/core/themes/app_typography.dart';
import 'package:flutter/material.dart';

/// Monta o `ThemeData` dark do Cockpit com os tokens [AppColors]/[AppTypography]
/// instalados como extensions (consumidos via `context.colors`/`context.typo`).
ThemeData buildDarkTheme() {
  const colors = AppColors.dark;
  final typo = AppTypography.build();

  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.panel,
    colorScheme: base.colorScheme.copyWith(
      surface: colors.panel,
      primary: colors.accent,
      // Texto/ícone sobre o preenchimento accent (FilledButton etc.). Sem isto,
      // o `onPrimary` do M3-dark é escuro → texto preto sobre o azul.
      onPrimary: Colors.white,
      error: colors.error,
      onError: Colors.white,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSoft,
      selectionHandleColor: colors.accent,
    ),
    // Botões secundários ("Cancelar" etc.) — fosco/neutro, **não** com a cor
    // primária (que faria parecer a ação principal). Pareiam com o FilledButton.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.text2,
        backgroundColor: colors.panel3,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    // Scrollbar fina (espelha o design: thumb escuro, fino). A visibilidade
    // permanente é aplicada por widget (transcript/rail) com controller — forçar
    // global quebra scrollviews sem controller (ex.: a tab strip horizontal).
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(6),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      interactive: true,
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? const Color(0xFF3A3A41)
            : const Color(0xFF2C2C31),
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    extensions: <ThemeExtension<dynamic>>[colors, typo],
  );
}
