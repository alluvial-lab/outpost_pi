import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Dark `TerminalView` theme with Cockpit's background, cursor, and ANSI palette.
///
/// The emulator owns the background and 16-color palette; oh-my-zsh only emits
/// ANSI codes for the prompt and `ls`, which this theme renders.
const TerminalTheme cockpitTerminalThemeDark = TerminalTheme(
  cursor: Color(0xFF74CC9C),
  selection: Color(0x4074CC9C),
  foreground: Color(0xFFE4EFE8),
  background: Color(0xFF131A16),
  black: Color(0xFF1E2620),
  red: Color(0xFFFF8B7D),
  green: Color(0xFF7FD99A),
  yellow: Color(0xFFE6C86E),
  blue: Color(0xFF7DB8E8),
  magenta: Color(0xFFC792EA),
  cyan: Color(0xFF65C7C0),
  white: Color(0xFFC2CEC3),
  brightBlack: Color(0xFF89978D),
  brightRed: Color(0xFFFFA89D),
  brightGreen: Color(0xFF8FD9A8),
  brightYellow: Color(0xFFF2D989),
  brightBlue: Color(0xFF9CCBF0),
  brightMagenta: Color(0xFFD6A0FF),
  brightCyan: Color(0xFF8EDDD7),
  brightWhite: Color(0xFFE4EFE8),
  searchHitBackground: Color(0xFFE6C86E),
  searchHitBackgroundCurrent: Color(0xFF74CC9C),
  searchHitForeground: Color(0xFF0A2418),
);

/// Light terminal theme with the sage-paper background and darkened ANSI palette.
///
/// Uses GitHub Light-inspired colors; normally bright yellow and white become
/// darker shades so output and oh-my-zsh prompts remain legible.
const TerminalTheme cockpitTerminalThemeLight = TerminalTheme(
  cursor: Color(0xFF256E47),
  selection: Color(0x22256E47),
  foreground: Color(0xFF182019),
  background: Color(0xFFF8FAF8),
  black: Color(0xFF182019),
  red: Color(0xFFB34234),
  green: Color(0xFF3E7A4E),
  yellow: Color(0xFF8A6A1F),
  blue: Color(0xFF33689B),
  magenta: Color(0xFF8250DF),
  cyan: Color(0xFF1B7478),
  white: Color(0xFF748078),
  brightBlack: Color(0xFF57635A),
  brightRed: Color(0xFF8F3026),
  brightGreen: Color(0xFF256E47),
  brightYellow: Color(0xFF6E5318),
  brightBlue: Color(0xFF28567F),
  brightMagenta: Color(0xFF6639BA),
  brightCyan: Color(0xFF276A70),
  brightWhite: Color(0xFF182019),
  searchHitBackground: Color(0xFFE6C86E),
  searchHitBackgroundCurrent: Color(0xFF256E47),
  searchHitForeground: Color(0xFFFFFFFF),
);

/// Resolve the terminal theme for the app brightness.
TerminalTheme cockpitTerminalThemeFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? cockpitTerminalThemeDark
    : cockpitTerminalThemeLight;
