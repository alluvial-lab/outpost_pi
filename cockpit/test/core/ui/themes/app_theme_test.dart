import 'package:cockpit/app/core/ui/themes/terminal_theme.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'theme_contract_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native palettes match the shared Phosphor Beacon contract', () {
    final fixture = ThemeContractFixture.load();
    for (final mode in _themeModes) {
      final actual = cockpitContractRoles(mode.colors);
      for (final entry in actual.entries) {
        expect(
          entry.value,
          fixture.color(mode.brightness, entry.key),
          reason:
              '${mode.name} role ${entry.key} drifted from the shared fixture',
        );
      }
    }
  });

  test('public token and theme builders resolve the same semantic theme', () {
    for (final mode in _themeModes) {
      final tokens = buildTokens(brightness: mode.brightness);
      final theme = buildTheme(brightness: mode.brightness);
      expect(
        tokens.colors,
        same(mode.colors),
        reason: '${mode.name} token colors',
      );
      expect(theme.colorScheme.brightness, mode.brightness, reason: mode.name);

      final scheme = theme.colorScheme;
      expect(
        scheme.background,
        mode.colors.bg,
        reason: '${mode.name} background',
      );
      expect(
        scheme.foreground,
        mode.colors.text,
        reason: '${mode.name} foreground',
      );
      expect(scheme.card, mode.colors.panel, reason: '${mode.name} card');
      expect(
        scheme.cardForeground,
        mode.colors.text,
        reason: '${mode.name} card foreground',
      );
      expect(
        scheme.primary,
        mode.colors.accent,
        reason: '${mode.name} primary',
      );
      expect(
        scheme.primaryForeground,
        mode.colors.onAccent,
        reason: '${mode.name} primary foreground',
      );
      expect(
        scheme.secondary,
        mode.colors.panel3,
        reason: '${mode.name} secondary',
      );
      expect(
        scheme.secondaryForeground,
        mode.colors.text2,
        reason: '${mode.name} secondary foreground',
      );
      expect(scheme.muted, mode.colors.panel2, reason: '${mode.name} muted');
      expect(
        scheme.mutedForeground,
        mode.colors.text2,
        reason: '${mode.name} muted foreground',
      );
      // Shadcn's accent is a neutral hover surface; brand green is primary.
      expect(
        scheme.accent,
        mode.colors.panel3,
        reason: '${mode.name} neutral accent',
      );
      expect(
        scheme.accentForeground,
        mode.colors.text,
        reason: '${mode.name} accent foreground',
      );
      expect(
        scheme.destructive,
        mode.colors.error,
        reason: '${mode.name} destructive',
      );
      // shadcn_flutter marks this legacy slot deprecated but still exposes it.
      expect(
        // ignore: deprecated_member_use
        scheme.destructiveForeground,
        mode.colors.onAccent,
        reason: '${mode.name} destructive foreground',
      );
      expect(scheme.border, mode.colors.border, reason: '${mode.name} border');
      expect(scheme.input, mode.colors.border, reason: '${mode.name} input');
      expect(scheme.ring, mode.colors.accent, reason: '${mode.name} ring');
    }
  });

  test('built token colors meet the shared WCAG AA threshold', () {
    final fixture = ThemeContractFixture.load();
    for (final mode in _themeModes) {
      final colors = buildTokens(brightness: mode.brightness).colors;
      final pairs = <String, (Color foreground, Color background)>{
        'primary text/background': (colors.text, colors.bg),
        'muted text/background': (colors.text2, colors.bg),
        'accent/background': (colors.accent, colors.bg),
        'on-accent/accent': (colors.onAccent, colors.accent),
      };
      for (final pair in pairs.entries) {
        final ratio = wcagContrast(pair.value.$1, pair.value.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(fixture.wcagAaNormalText),
          reason: '${mode.name} ${pair.key} ratio was $ratio',
        );
      }
    }
  });

  test('display body mono terminal and syntax roles use the beacon family', () {
    final typography = AppTypography.build();
    expect(typography.display.fontFamily, startsWith('SpaceMono'));
    expect(typography.body.fontFamily, 'SpaceMono_regular');
    expect(typography.mono.fontFamily, 'SpaceMono_regular');
    expect(cockpitTerminalThemeDark.cursor, const Color(0xFF74CC9C));
    expect(cockpitTerminalThemeLight.cursor, const Color(0xFF256E47));
    expect(SyntaxColors.oneDark.string, const Color(0xFF7FD99A));
    expect(SyntaxColors.oneLight.string, const Color(0xFF3E7A4E));
  });
}

final _themeModes = <({String name, Brightness brightness, AppColors colors})>[
  (name: 'dark', brightness: Brightness.dark, colors: AppColors.dark),
  (name: 'light', brightness: Brightness.light, colors: AppColors.light),
];
