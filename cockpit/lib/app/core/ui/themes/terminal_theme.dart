import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Dark `TerminalView` theme with Cockpit's background, cursor, and ANSI palette.
///
/// The emulator owns the background and 16-color palette; oh-my-zsh only emits
/// ANSI codes for the prompt and `ls`, which this theme renders.
const TerminalTheme cockpitTerminalThemeDark = TerminalTheme(
  cursor: Color(0xFF2F6FF0), // accent
  selection: Color(0x402F6FF0),
  foreground: Color(0xFFECECEF), // text
  background: Color(0xFF18181B), // panel (same as the agent body background)
  black: Color(0xFF26262A),
  red: Color(0xFFE5484D),
  green: Color(0xFF3FB868),
  yellow: Color(0xFFE0A33A),
  blue: Color(0xFF2F6FF0),
  magenta: Color(0xFFC792EA),
  cyan: Color(0xFF1AA5A0),
  white: Color(0xFFC9C9CF),
  brightBlack: Color(0xFF6A6A73),
  brightRed: Color(0xFFFF6B6F),
  brightGreen: Color(0xFF82E0A5),
  brightYellow: Color(0xFFFFCB6B),
  brightBlue: Color(0xFF82AAFF),
  brightMagenta: Color(0xFFD6A0FF),
  brightCyan: Color(0xFF89DDFF),
  brightWhite: Color(0xFFECECEF),
  searchHitBackground: Color(0xFFE0A33A),
  searchHitBackgroundCurrent: Color(0xFF2F6FF0),
  searchHitForeground: Color(0xFF0D0D0F),
);

/// Light terminal theme with a white background and darkened ANSI palette.
///
/// Uses GitHub Light-inspired colors; normally bright yellow and white become
/// darker shades so output and oh-my-zsh prompts remain legible.
const TerminalTheme cockpitTerminalThemeLight = TerminalTheme(
  cursor: Color(0xFF2F6FF0), // accent
  selection: Color(0x222F6FF0),
  foreground: Color(0xFF1A1A1F), // text (dark)
  background: Color(0xFFFFFFFF), // panel (same as the agent body background)
  black: Color(0xFF1A1A1F),
  red: Color(0xFFCF222E),
  green: Color(0xFF1A7F37),
  yellow: Color(0xFF9A6700),
  blue: Color(0xFF0969DA),
  magenta: Color(0xFF8250DF),
  cyan: Color(0xFF1B7C83),
  white: Color(0xFF6E7781),
  brightBlack: Color(0xFF57606A),
  brightRed: Color(0xFFA40E26),
  brightGreen: Color(0xFF116329),
  brightYellow: Color(0xFF7D4E00),
  brightBlue: Color(0xFF0550AE),
  brightMagenta: Color(0xFF6639BA),
  brightCyan: Color(0xFF3192AA),
  brightWhite: Color(0xFF24292F),
  searchHitBackground: Color(0xFFFFDF5D),
  searchHitBackgroundCurrent: Color(0xFF2F6FF0),
  searchHitForeground: Color(0xFFFFFFFF),
);

/// Resolve the terminal theme for the app brightness.
TerminalTheme cockpitTerminalThemeFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? cockpitTerminalThemeDark
    : cockpitTerminalThemeLight;
