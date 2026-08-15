import 'package:cockpit/app/core/ui/themes/terminal_theme.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark palette mirrors the Phosphor Beacon contract', () {
    expect(AppColors.dark.bg, const Color(0xFF0D1210));
    expect(AppColors.dark.panel, const Color(0xFF131A16));
    expect(AppColors.dark.border, const Color(0xFF1E2620));
    expect(AppColors.dark.text, const Color(0xFFE4EFE8));
    expect(AppColors.dark.text2, const Color(0xFF89978D));
    expect(AppColors.dark.accent, const Color(0xFF74CC9C));
    expect(AppColors.dark.onAccent, const Color(0xFF0A2418));
    expect(AppColors.dark.ok, const Color(0xFF7FD99A));
    expect(AppColors.dark.warn, const Color(0xFFE6C86E));
    expect(AppColors.dark.error, const Color(0xFFFF8B7D));
  });

  test('light palette mirrors the Phosphor Beacon contract', () {
    expect(AppColors.light.bg, const Color(0xFFF3F6F3));
    expect(AppColors.light.panel, const Color(0xFFF8FAF8));
    expect(AppColors.light.border, const Color(0xFFDFE6DF));
    expect(AppColors.light.text, const Color(0xFF182019));
    expect(AppColors.light.text2, const Color(0xFF57635A));
    expect(AppColors.light.accent, const Color(0xFF256E47));
    expect(AppColors.light.onAccent, const Color(0xFFFFFFFF));
    expect(AppColors.light.ok, const Color(0xFF3E7A4E));
    expect(AppColors.light.warn, const Color(0xFF8A6A1F));
    expect(AppColors.light.error, const Color(0xFFB34234));
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
