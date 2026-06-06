import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Tema do `TerminalView` casando com a identidade do cockpit (fundo `#0D0D0F`,
/// cursor accent, paleta ANSI dark).
const TerminalTheme cockpitTerminalTheme = TerminalTheme(
  cursor: Color(0xFF2F6FF0), // accent
  selection: Color(0x402F6FF0),
  foreground: Color(0xFFECECEF), // text
  background: Color(0xFF18181B), // panel (mesmo fundo do corpo do agente)
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
