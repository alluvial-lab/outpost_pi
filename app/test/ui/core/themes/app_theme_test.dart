import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_contract_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native palettes match the shared Phosphor Beacon contract', () {
    final fixture = ThemeContractFixture.load();
    for (final mode in _themeModes) {
      final actual = appContractRoles(mode.colors);
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

  test('public theme builders install the requested semantic theme', () {
    for (final mode in _themeModes) {
      final theme = mode.build();
      final colors = theme.extension<AppColors>();
      final typography = theme.extension<AppTypography>();
      expect(theme.brightness, mode.brightness, reason: mode.name);
      expect(
        colors,
        same(mode.colors),
        reason: '${mode.name} colors extension',
      );
      expect(
        typography,
        same(mode.typography),
        reason: '${mode.name} typography extension',
      );
      expect(theme.scaffoldBackgroundColor, mode.colors.bg, reason: mode.name);

      final scheme = theme.colorScheme;
      expect(scheme.brightness, mode.brightness, reason: '${mode.name} scheme');
      expect(scheme.surface, mode.colors.bg, reason: '${mode.name} surface');
      expect(
        scheme.onSurface,
        mode.colors.text,
        reason: '${mode.name} onSurface',
      );
      expect(
        scheme.primary,
        mode.colors.accent,
        reason: '${mode.name} primary',
      );
      expect(
        scheme.onPrimary,
        mode.colors.onAccent,
        reason: '${mode.name} onPrimary',
      );
      expect(
        scheme.secondary,
        mode.colors.muted,
        reason: '${mode.name} secondary',
      );
      expect(
        scheme.onSecondary,
        mode.colors.text,
        reason: '${mode.name} onSecondary',
      );
      expect(scheme.error, mode.colors.error, reason: '${mode.name} error');
      expect(
        scheme.onError,
        mode.colors.onAccent,
        reason: '${mode.name} onError',
      );
      expect(
        scheme.outline,
        mode.colors.border,
        reason: '${mode.name} outline',
      );
    }
  });

  test('built theme colors meet the shared WCAG AA threshold', () {
    final fixture = ThemeContractFixture.load();
    for (final mode in _themeModes) {
      final colors = mode.build().extension<AppColors>()!;
      final pairs = <String, (Color foreground, Color background)>{
        'primary text/background': (colors.text, colors.bg),
        'muted text/background': (colors.muted, colors.bg),
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

  test('strong divider token improves contrast over the hairline border', () {
    for (final colors in <AppColors>[AppColors.dark, AppColors.light]) {
      expect(
        wcagContrast(colors.borderStrong, colors.bg),
        greaterThan(wcagContrast(colors.border, colors.bg)),
      );
    }
  });

  test('all Material text and control roles resolve to Space Mono', () {
    expect(kMonoFamily, 'SpaceMono_regular');
    expect(kSansFamily, kMonoFamily);
    expect(AppTypography.dark.mono.fontFamily, kMonoFamily);
    expect(AppTypography.dark.sansBody.fontFamily, kMonoFamily);
    expect(brandTextStyle(fontSize: 24).fontFamily, startsWith('SpaceMono'));

    for (final theme in <ThemeData>[buildDarkTheme(), buildLightTheme()]) {
      for (final style in <TextStyle?>[
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
        theme.textButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
        theme.elevatedButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
        theme.outlinedButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
        theme.filledButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
      ]) {
        expect(style?.fontFamily, kMonoFamily);
      }
      expect(theme.inputDecorationTheme.hintStyle?.fontFamily, kMonoFamily);
    }
  });
}

final _themeModes =
    <
      ({
        String name,
        Brightness brightness,
        ThemeData Function() build,
        AppColors colors,
        AppTypography typography,
      })
    >[
      (
        name: 'dark',
        brightness: Brightness.dark,
        build: buildDarkTheme,
        colors: AppColors.dark,
        typography: AppTypography.dark,
      ),
      (
        name: 'light',
        brightness: Brightness.light,
        build: buildLightTheme,
        colors: AppColors.light,
        typography: AppTypography.light,
      ),
    ];
