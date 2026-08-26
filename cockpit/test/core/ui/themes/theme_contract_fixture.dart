import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/ui/themes/app_colors.dart';
import 'package:flutter/widgets.dart';

/// Load the cross-surface color contract for Cockpit theme tests.
final class ThemeContractFixture {
  ThemeContractFixture._(this._modes, this.wcagAaNormalText);

  final Map<String, Map<String, String>> _modes;
  final double wcagAaNormalText;

  /// Read and validate the checked-in contract from the test process cwd.
  static ThemeContractFixture load({
    String path = '../branding/theme-contract.json',
  }) {
    final file = File(path);
    final raw = _readJson(file);
    if (raw is! Map<String, dynamic>) {
      throw StateError('Theme contract at ${file.path} must be a JSON object');
    }
    if (raw['schemaVersion'] != 1) {
      throw StateError(
        'Theme contract at ${file.path} has unsupported schemaVersion '
        '${raw['schemaVersion']}',
      );
    }
    final threshold = raw['wcagAaNormalText'];
    if (threshold is! num || threshold <= 0) {
      throw StateError(
        'Theme contract at ${file.path} has invalid wcagAaNormalText',
      );
    }
    final modes = raw['modes'];
    if (modes is! Map<String, dynamic>) {
      throw StateError('Theme contract at ${file.path} is missing modes');
    }
    final dark = _parseMode(modes, 'dark', file.path);
    final light = _parseMode(modes, 'light', file.path);
    if (!dark.keys.toSet().containsAll(light.keys) ||
        !light.keys.toSet().containsAll(dark.keys)) {
      throw StateError(
        'Theme contract at ${file.path} has different dark/light role sets',
      );
    }
    return ThemeContractFixture._(<String, Map<String, String>>{
      'dark': dark,
      'light': light,
    }, threshold.toDouble());
  }

  /// Resolve a validated role for one Flutter brightness.
  Color color(Brightness brightness, String role) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';
    final value = _modes[mode]?[role];
    if (value == null) {
      throw StateError('Theme contract has no $mode role $role');
    }
    return _parseColor(value, role: role, mode: mode);
  }

  static dynamic _readJson(File file) {
    try {
      return jsonDecode(file.readAsStringSync());
    } on Object catch (error) {
      throw StateError('Unable to read theme contract at ${file.path}: $error');
    }
  }

  static Map<String, String> _parseMode(
    Map<String, dynamic> modes,
    String mode,
    String path,
  ) {
    final rawMode = modes[mode];
    if (rawMode is! Map<String, dynamic> || rawMode.isEmpty) {
      throw StateError('Theme contract at $path is missing $mode roles');
    }
    final parsed = <String, String>{};
    for (final entry in rawMode.entries) {
      if (entry.key.trim().isEmpty || entry.value is! String) {
        throw StateError(
          'Theme contract at $path has invalid $mode role ${entry.key}',
        );
      }
      final value = (entry.value as String).trim();
      _parseColor(value, role: entry.key, mode: mode);
      parsed[entry.key] = value;
    }
    return parsed;
  }

  static Color _parseColor(
    String value, {
    required String role,
    required String mode,
  }) {
    final hex = RegExp(r'^#[0-9a-fA-F]{6}$').firstMatch(value);
    if (hex != null) {
      return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
    }
    final rgba = RegExp(
      r'^rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*'
      r'(\d{1,3})\s*,\s*(0|1|0?\.\d+)\s*\)$',
    ).firstMatch(value);
    if (rgba == null) {
      throw StateError(
        'Theme contract has unsupported $mode role $role value $value; '
        'expected #RRGGBB or rgba(r, g, b, a)',
      );
    }
    final channels = <int>[
      int.parse(rgba.group(1)!),
      int.parse(rgba.group(2)!),
      int.parse(rgba.group(3)!),
    ];
    final alpha = double.parse(rgba.group(4)!);
    if (channels.any((channel) => channel > 255) || alpha > 1) {
      throw StateError(
        'Theme contract has invalid $mode role $role value $value',
      );
    }
    return Color.fromARGB(
      (alpha * 255).round(),
      channels[0],
      channels[1],
      channels[2],
    );
  }
}

/// Map the Cockpit's direct native palette ports to shared contract roles.
Map<String, Color> cockpitContractRoles(AppColors colors) => <String, Color>{
  'bgPrimary': colors.bg,
  'bgSecondary': colors.panel,
  'bgTertiary': colors.panel2,
  'border': colors.border,
  'borderStrong': colors.border2,
  'textPrimary': colors.text,
  'textSecondary': colors.text2,
  'accent': colors.accent,
  'accentHover': colors.accentText,
  'onAccent': colors.onAccent,
  'success': colors.ok,
  'warning': colors.warn,
  'error': colors.error,
  'info': colors.gitUntracked,
};

/// Compute the WCAG 2.1 contrast ratio for two resolved colors.
double wcagContrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
