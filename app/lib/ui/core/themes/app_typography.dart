import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/ui/core/themes/app_colors.dart';

/// Google Fonts' registered family name for the product's mono-native voice.
///
/// [GoogleFonts.spaceMono] loads the files while this constant keeps direct
/// `TextStyle` call sites aligned with the same family.
const String kMonoFamily = 'SpaceMono_regular';

/// Body/system text uses the same Space Mono family as code and display text.
const String kSansFamily = kMonoFamily;

/// Build the Space Mono wordmark style for product-name lockups.
///
/// The locked identity uses one type voice everywhere, with the literal
/// `outpost_pi` wordmark at weight 700.
///
/// **To change the brand font, change this one call** (e.g. `GoogleFonts.x`).
///
/// Returns a runtime [TextStyle] (Google Fonts can't be `const`); pass the
/// brightness-appropriate [color] from `context.colors.text`.
TextStyle brandTextStyle({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w700,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.spaceMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Typographic styles for the app, themed per brightness (colors baked in so
/// the common case — `context.typo.mono` — is correct without a `.copyWith`).
///
/// This is the SINGLE source of truth for text styles. Widgets read
/// `context.typo.<style>` and `.copyWith(...)` only for one-off size/weight
/// tweaks — never re-declaring `fontFamily`.
///
/// Registered on [ThemeData.extensions]; resolve via
/// `Theme.of(context).extension<AppTypography>()`.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.mono,
    required this.monoSmall,
    required this.sansBody,
  });

  /// Primary monospace style (chat code, terminal chrome). Was `kMonoStyle`.
  final TextStyle mono;

  /// Small monospace style (captions, metadata). Was `kMonoSmall`.
  final TextStyle monoSmall;

  /// Sans body text. Was `kSansBody`.
  final TextStyle sansBody;

  /// Build the style set for a given color palette so text colors track the
  /// active theme. [monoColor] is the resting mono text color (was the
  /// hardcoded `0xFFE6E6E6` in dark).
  factory AppTypography.fromColors(AppColors c, {required Color monoColor}) {
    return AppTypography(
      mono: GoogleFonts.spaceMono(
        fontSize: 12.5,
        color: monoColor,
        height: 1.5,
        letterSpacing: 0,
      ),
      monoSmall: GoogleFonts.spaceMono(
        fontSize: 11.0,
        color: c.muted2,
        height: 1.4,
      ),
      sansBody: GoogleFonts.spaceMono(
        fontSize: 14.0,
        color: c.text,
        height: 1.35,
        letterSpacing: 0,
      ),
    );
  }

  /// Dark typography follows the primary Phosphor Beacon ink.
  static final AppTypography dark = AppTypography.fromColors(
    AppColors.dark,
    monoColor: AppColors.dark.text,
  );

  /// Light typography follows the primary Phosphor Beacon ink.
  static final AppTypography light = AppTypography.fromColors(
    AppColors.light,
    monoColor: AppColors.light.text,
  );

  @override
  AppTypography copyWith({
    TextStyle? mono,
    TextStyle? monoSmall,
    TextStyle? sansBody,
  }) {
    return AppTypography(
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
      sansBody: sansBody ?? this.sansBody,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
      sansBody: TextStyle.lerp(sansBody, other.sansBody, t)!,
    );
  }
}
