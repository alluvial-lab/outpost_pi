import 'package:flutter/material.dart';

/// Semantic color tokens for the whole app.
///
/// This is the SINGLE source of truth for every color used in the UI. Widgets
/// must never hardcode `Color(0x…)` or `Colors.*` — they read from here via
/// `context.colors.<token>` (see `theme_extensions.dart`).
///
/// Registered on [ThemeData.extensions] by `buildDarkTheme()` /
/// `buildLightTheme()` so `Theme.of(context).extension<AppColors>()` resolves
/// the right palette for the active brightness.
///
/// Values mirror the locked Phosphor Beacon contract in
/// `.mockups/design-system/tokens.css`; surface-specific semantic roles derive
/// from that neutral, accent, and status ramp here in one place.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.muted2,
    required this.accent,
    required this.onAccent,
    required this.highlight,
    required this.success,
    required this.error,
    required this.warning,
    required this.working,
    required this.codeBg,
    required this.userBubble,
    required this.modelBadgeBg,
    required this.modelBadgeBorder,
    required this.denyBorder,
    required this.inputFill,
  });

  /// App background (scaffold). Was `kBg`.
  final Color bg;

  /// Slightly raised surface (cards, sheets). Was `kSurface`.
  final Color surface;

  /// Hairline borders / dividers. Was `kBorder`.
  final Color border;

  /// Strong separators that need more contrast than a hairline border.
  final Color borderStrong;

  /// Primary foreground text. Was `kText`.
  final Color text;

  /// Secondary / de-emphasized text. Was `kMuted`.
  final Color muted;

  /// Tertiary text — slightly more prominent than [muted]. Was `kMuted2`.
  final Color muted2;

  /// Brand accent (links, active states, primary buttons). Was `kAccent`.
  final Color accent;

  /// Foreground painted on top of [accent] (e.g. filled-button label). Was the
  /// hardcoded `Colors.black` / `onPrimary`.
  final Color onAccent;

  /// Code / file paths inside agent messages. Was `kHighlight`.
  final Color highlight;

  /// Success state (✓ tool results). Was `kSuccess`.
  final Color success;

  /// Error / destructive state (✗ tool results, failed sends, delete). Was
  /// `kError` and the scattered `Colors.redAccent`.
  final Color error;

  /// Warning state (relay offline). Was the scattered `Colors.amber`.
  final Color warning;

  /// "Working" / in-progress accent (session running a turn). Was the local
  /// `kWorking = Color(0xFF3FA9F5)` duplicated in session_tile and chat_page.
  final Color working;

  /// Background of inline/he block code. Was `kCodeBg`.
  final Color codeBg;

  /// User chat bubble background. Was `kUserBubble`.
  final Color userBubble;

  /// Model badge background. Was `kModelBadgeBg`.
  final Color modelBadgeBg;

  /// Model badge border. Was `kModelBadgeBorder`.
  final Color modelBadgeBorder;

  /// Border for a denied tool-call card. Was `kDenyBorder`.
  final Color denyBorder;

  /// Text-field fill. Was the hardcoded `Color(0xFF0E0E0E)`.
  final Color inputFill;

  /// Dark-native Phosphor Beacon palette.
  static const AppColors dark = AppColors(
    bg: Color(0xFF0D1210),
    surface: Color(0xFF131A16),
    border: Color(0xFF1E2620),
    borderStrong: Color(0xFF2A342C),
    text: Color(0xFFE4EFE8),
    muted: Color(0xFF89978D),
    muted2: Color(0xFFAAB6AD),
    accent: Color(0xFF74CC9C),
    onAccent: Color(0xFF0A2418),
    highlight: Color(0xFF8FD9A8),
    success: Color(0xFF7FD99A),
    error: Color(0xFFFF8B7D),
    warning: Color(0xFFE6C86E),
    working: Color(0xFF7DB8E8),
    codeBg: Color(0xFF0D1210),
    userBubble: Color(0xFF1E2620),
    modelBadgeBg: Color(0xFF131A16),
    modelBadgeBorder: Color(0xFF2A342C),
    denyBorder: Color(0xFF2A342C),
    inputFill: Color(0xFF1E2620),
  );

  /// Light Phosphor Beacon palette with AA-verified contract values.
  static const AppColors light = AppColors(
    bg: Color(0xFFF3F6F3),
    surface: Color(0xFFF8FAF8),
    border: Color(0xFFDFE6DF),
    borderStrong: Color(0xFFC2CEC3),
    text: Color(0xFF182019),
    muted: Color(0xFF57635A),
    muted2: Color(0xFF3D4940),
    accent: Color(0xFF256E47),
    onAccent: Color(0xFFFFFFFF),
    highlight: Color(0xFF1C5A39),
    success: Color(0xFF3E7A4E),
    error: Color(0xFFB34234),
    warning: Color(0xFF8A6A1F),
    working: Color(0xFF33689B),
    codeBg: Color(0xFFF8FAF8),
    userBubble: Color(0xFFDFE6DF),
    modelBadgeBg: Color(0xFFF8FAF8),
    modelBadgeBorder: Color(0xFFC2CEC3),
    denyBorder: Color(0xFFC2CEC3),
    inputFill: Color(0xFFF8FAF8),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? muted,
    Color? muted2,
    Color? accent,
    Color? onAccent,
    Color? highlight,
    Color? success,
    Color? error,
    Color? warning,
    Color? working,
    Color? codeBg,
    Color? userBubble,
    Color? modelBadgeBg,
    Color? modelBadgeBorder,
    Color? denyBorder,
    Color? inputFill,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      muted2: muted2 ?? this.muted2,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      highlight: highlight ?? this.highlight,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      working: working ?? this.working,
      codeBg: codeBg ?? this.codeBg,
      userBubble: userBubble ?? this.userBubble,
      modelBadgeBg: modelBadgeBg ?? this.modelBadgeBg,
      modelBadgeBorder: modelBadgeBorder ?? this.modelBadgeBorder,
      denyBorder: denyBorder ?? this.denyBorder,
      inputFill: inputFill ?? this.inputFill,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      muted2: Color.lerp(muted2, other.muted2, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      working: Color.lerp(working, other.working, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      modelBadgeBg: Color.lerp(modelBadgeBg, other.modelBadgeBg, t)!,
      modelBadgeBorder: Color.lerp(
        modelBadgeBorder,
        other.modelBadgeBorder,
        t,
      )!,
      denyBorder: Color.lerp(denyBorder, other.denyBorder, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
    );
  }
}
