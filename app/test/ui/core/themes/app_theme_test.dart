import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark palette mirrors the Phosphor Beacon contract', () {
    expect(AppColors.dark.bg, const Color(0xFF0D1210));
    expect(AppColors.dark.surface, const Color(0xFF131A16));
    expect(AppColors.dark.border, const Color(0xFF1E2620));
    expect(AppColors.dark.borderStrong, const Color(0xFF2A342C));
    expect(AppColors.dark.text, const Color(0xFFE4EFE8));
    expect(AppColors.dark.muted, const Color(0xFF89978D));
    expect(AppColors.dark.accent, const Color(0xFF74CC9C));
    expect(AppColors.dark.onAccent, const Color(0xFF0A2418));
    expect(AppColors.dark.success, const Color(0xFF7FD99A));
    expect(AppColors.dark.warning, const Color(0xFFE6C86E));
    expect(AppColors.dark.error, const Color(0xFFFF8B7D));
    expect(AppColors.dark.working, const Color(0xFF7DB8E8));
  });

  test('light palette mirrors the Phosphor Beacon contract', () {
    expect(AppColors.light.bg, const Color(0xFFF3F6F3));
    expect(AppColors.light.surface, const Color(0xFFF8FAF8));
    expect(AppColors.light.border, const Color(0xFFDFE6DF));
    expect(AppColors.light.borderStrong, const Color(0xFFC2CEC3));
    expect(AppColors.light.text, const Color(0xFF182019));
    expect(AppColors.light.muted, const Color(0xFF57635A));
    expect(AppColors.light.accent, const Color(0xFF256E47));
    expect(AppColors.light.onAccent, const Color(0xFFFFFFFF));
    expect(AppColors.light.success, const Color(0xFF3E7A4E));
    expect(AppColors.light.warning, const Color(0xFF8A6A1F));
    expect(AppColors.light.error, const Color(0xFFB34234));
    expect(AppColors.light.working, const Color(0xFF33689B));
  });

  test('strong divider token improves contrast over the hairline border', () {
    for (final colors in <AppColors>[AppColors.dark, AppColors.light]) {
      expect(
        _contrast(colors.borderStrong, colors.bg),
        greaterThan(_contrast(colors.border, colors.bg)),
      );
    }
  });

  test('display body and mono roles resolve to Space Mono', () {
    expect(kMonoFamily, 'SpaceMono_regular');
    expect(kSansFamily, kMonoFamily);
    expect(AppTypography.dark.mono.fontFamily, kMonoFamily);
    expect(AppTypography.dark.sansBody.fontFamily, kMonoFamily);
    expect(brandTextStyle(fontSize: 24).fontFamily, startsWith('SpaceMono'));
  });
}

double _contrast(Color foreground, Color background) {
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
