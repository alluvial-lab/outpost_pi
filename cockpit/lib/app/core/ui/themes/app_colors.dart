import 'package:flutter/widgets.dart';

/// Define Cockpit color tokens that mirror Phosphor Beacon `tokens.css`.
///
/// The neutral, accent, and status ramps stay aligned with mobile while
/// Cockpit-specific git/file roles derive from those shared semantic values.
@immutable
class AppColors {
  const AppColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.panel3,
    required this.border,
    required this.border2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.accent,
    required this.accentSoft,
    required this.accentText,
    required this.onAccent,
    required this.online,
    required this.ok,
    required this.error,
    required this.warn,
    required this.edited,
    required this.editedBg,
    required this.gitStaged,
    required this.gitUntracked,
    required this.gitDeleted,
    required this.gitConflict,
  });

  final Color bg; // app backdrop, deepest
  final Color panel; // pane / rail surface
  final Color panel2; // raised: composer, cards
  final Color panel3; // hover / inset code
  final Color border; // hairlines
  final Color border2; // stronger divider
  final Color text; // primary
  final Color text2; // secondary
  final Color text3; // tertiary / placeholder
  final Color text4; // faint, icons-at-rest
  final Color accent;
  final Color accentSoft;
  final Color accentText;
  final Color onAccent;
  final Color online;
  final Color ok;
  final Color error;
  final Color warn;
  final Color edited; // recently-edited file accent
  final Color editedBg;

  // Git status (file tree). Modified reuses [warn] (amber, like the branch).
  final Color gitStaged; // staged in the index → green
  final Color gitUntracked; // new / untracked → blue
  final Color gitDeleted; // removed → red
  final Color gitConflict; // merge conflict → orange

  static const AppColors dark = AppColors(
    bg: Color(0xFF0D1210),
    panel: Color(0xFF131A16),
    panel2: Color(0xFF1E2620),
    panel3: Color(0xFF2A342C),
    border: Color(0xFF1E2620),
    border2: Color(0xFF2A342C),
    text: Color(0xFFE4EFE8),
    text2: Color(0xFF89978D),
    text3: Color(0xFF6F7D73),
    text4: Color(0xFF4D5A51),
    accent: Color(0xFF74CC9C),
    accentSoft: Color(0x2474CC9C),
    accentText: Color(0xFF8FD9A8),
    onAccent: Color(0xFF0A2418),
    online: Color(0xFF7FD99A),
    ok: Color(0xFF7FD99A),
    error: Color(0xFFFF8B7D),
    warn: Color(0xFFE6C86E),
    edited: Color(0xFFE6C86E),
    editedBg: Color(0x24E6C86E),
    gitStaged: Color(0xFF7FD99A),
    gitUntracked: Color(0xFF7DB8E8),
    gitDeleted: Color(0xFFFF8B7D),
    gitConflict: Color(0xFFE6C86E),
  );

  /// Light Phosphor Beacon variant.
  static const AppColors light = AppColors(
    bg: Color(0xFFF3F6F3),
    panel: Color(0xFFF8FAF8),
    panel2: Color(0xFFDFE6DF),
    panel3: Color(0xFFC2CEC3),
    border: Color(0xFFDFE6DF),
    border2: Color(0xFFC2CEC3),
    text: Color(0xFF182019),
    text2: Color(0xFF57635A),
    text3: Color(0xFF748078),
    text4: Color(0xFF9BA89D),
    accent: Color(0xFF256E47),
    accentSoft: Color(0x1F256E47),
    accentText: Color(0xFF1C5A39),
    onAccent: Color(0xFFFFFFFF),
    online: Color(0xFF3E7A4E),
    ok: Color(0xFF3E7A4E),
    error: Color(0xFFB34234),
    warn: Color(0xFF8A6A1F),
    edited: Color(0xFF8A6A1F),
    editedBg: Color(0x1F8A6A1F),
    gitStaged: Color(0xFF3E7A4E),
    gitUntracked: Color(0xFF33689B),
    gitDeleted: Color(0xFFB34234),
    gitConflict: Color(0xFF8A6A1F),
  );

  AppColors copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? panel3,
    Color? border,
    Color? border2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? text4,
    Color? accent,
    Color? accentSoft,
    Color? accentText,
    Color? onAccent,
    Color? online,
    Color? ok,
    Color? error,
    Color? warn,
    Color? edited,
    Color? editedBg,
    Color? gitStaged,
    Color? gitUntracked,
    Color? gitDeleted,
    Color? gitConflict,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panel2: panel2 ?? this.panel2,
      panel3: panel3 ?? this.panel3,
      border: border ?? this.border,
      border2: border2 ?? this.border2,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      text4: text4 ?? this.text4,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentText: accentText ?? this.accentText,
      onAccent: onAccent ?? this.onAccent,
      online: online ?? this.online,
      ok: ok ?? this.ok,
      error: error ?? this.error,
      warn: warn ?? this.warn,
      edited: edited ?? this.edited,
      editedBg: editedBg ?? this.editedBg,
      gitStaged: gitStaged ?? this.gitStaged,
      gitUntracked: gitUntracked ?? this.gitUntracked,
      gitDeleted: gitDeleted ?? this.gitDeleted,
      gitConflict: gitConflict ?? this.gitConflict,
    );
  }
}
