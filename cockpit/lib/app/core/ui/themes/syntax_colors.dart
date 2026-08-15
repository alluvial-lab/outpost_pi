import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:flutter/widgets.dart';

/// Define the code viewer's syntax-highlighting palette.
///
/// Maps highlight.js node class names to semantic colors exposed through
/// `context.syntax`. Each palette carries its own [background], keeping the
/// viewer internally consistent across light and dark app themes.
@immutable
class SyntaxColors {
  const SyntaxColors({
    required this.background,
    required this.base,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.klass,
    required this.builtin,
    required this.function,
    required this.variable,
    required this.meta,
    required this.deletion,
  });

  final Color background; // code-viewer background
  final Color base; // unscoped text
  final Color comment; // comments (italic)
  final Color keyword; // keywords
  final Color string; // strings / value regex / addition (diff +)
  final Color number; // numbers and literals (true/false/null)
  final Color klass; // types / classes (`type` would clash with ThemeExtension)
  final Color builtin; // built-ins
  final Color function; // titles / function names / sections
  final Color variable; // variables / attributes / tags / symbols
  final Color meta; // metadata / decorators / preprocessor
  final Color deletion; // diff -

  // --- One ------------------------------------------------------------------
  /// One Dark.
  static const SyntaxColors oneDark = SyntaxColors(
    background: Color(0xFF282C34),
    base: Color(0xFFABB2BF),
    comment: Color(0xFF7F848E),
    keyword: Color(0xFFC678DD),
    string: Color(0xFF7FD99A),
    number: Color(0xFFD19A66),
    klass: Color(0xFFE5C07B),
    builtin: Color(0xFF56B6C2),
    function: Color(0xFF61AFEF),
    variable: Color(0xFFE06C75),
    meta: Color(0xFF56B6C2),
    deletion: Color(0xFFE06C75),
  );

  /// One Light (Atom One Light).
  static const SyntaxColors oneLight = SyntaxColors(
    background: Color(0xFFFAFAFA),
    base: Color(0xFF383A42),
    comment: Color(0xFFA0A1A7),
    keyword: Color(0xFFA626A4),
    string: Color(0xFF3E7A4E),
    number: Color(0xFF986801),
    klass: Color(0xFFC18401),
    builtin: Color(0xFF0184BC),
    function: Color(0xFF4078F2),
    variable: Color(0xFFE45649),
    meta: Color(0xFF0184BC),
    deletion: Color(0xFFE45649),
  );

  // --- Dracula --------------------------------------------------------------
  /// Dracula (dark).
  static const SyntaxColors draculaDark = SyntaxColors(
    background: Color(0xFF282A36),
    base: Color(0xFFF8F8F2),
    comment: Color(0xFF6272A4),
    keyword: Color(0xFFFF79C6),
    string: Color(0xFFF1FA8C),
    number: Color(0xFFBD93F9),
    klass: Color(0xFF8BE9FD),
    builtin: Color(0xFF8BE9FD),
    function: Color(0xFF7FD99A),
    variable: Color(0xFFFFB86C),
    meta: Color(0xFFFF79C6),
    deletion: Color(0xFFFF5555),
  );

  /// Dracula light (Alucard-inspired), darkened for contrast on light surfaces.
  static const SyntaxColors draculaLight = SyntaxColors(
    background: Color(0xFFF6F2FF),
    base: Color(0xFF2A2A37),
    comment: Color(0xFF8C8AA8),
    keyword: Color(0xFFC2268E),
    string: Color(0xFF6B7A1F),
    number: Color(0xFF7C3AED),
    klass: Color(0xFF0E7490),
    builtin: Color(0xFF0E7490),
    function: Color(0xFF3E7A4E),
    variable: Color(0xFFB45309),
    meta: Color(0xFFC2268E),
    deletion: Color(0xFFDC2626),
  );

  // --- GitHub ---------------------------------------------------------------
  /// GitHub Dark.
  static const SyntaxColors githubDark = SyntaxColors(
    background: Color(0xFF0D1117),
    base: Color(0xFFC9D1D9),
    comment: Color(0xFF8B949E),
    keyword: Color(0xFFFF7B72),
    string: Color(0xFFA5D6FF),
    number: Color(0xFF79C0FF),
    klass: Color(0xFFFFA657),
    builtin: Color(0xFF79C0FF),
    function: Color(0xFFD2A8FF),
    variable: Color(0xFFFFA657),
    meta: Color(0xFF7FD99A),
    deletion: Color(0xFFFFA198),
  );

  /// GitHub Light.
  static const SyntaxColors githubLight = SyntaxColors(
    background: Color(0xFFFFFFFF),
    base: Color(0xFF24292F),
    comment: Color(0xFF6E7781),
    keyword: Color(0xFFCF222E),
    string: Color(0xFF0A3069),
    number: Color(0xFF0550AE),
    klass: Color(0xFF953800),
    builtin: Color(0xFF0550AE),
    function: Color(0xFF8250DF),
    variable: Color(0xFF953800),
    meta: Color(0xFF256E47),
    deletion: Color(0xFF82071E),
  );

  /// Fallback used by `context.syntax` outside the themed tree.
  static const SyntaxColors dark = oneDark;

  // --- Diagnostics (LSP) ----------------------------------------------------
  // Palette-independent semantic colors remain legible on dark and light
  // backgrounds and color diagnostic squiggles and gutter severity icons.
  static const Color diagnosticError = Color(0xFFE5484D);
  static const Color diagnosticWarning = Color(0xFFF5A623);
  static const Color diagnosticInfo = Color(0xFF4C9AFF);
  static const Color diagnosticHint = Color(0xFF8B949E);

  /// Resolve the underline and icon color for a diagnostic severity.
  static Color diagnosticColor(LspSeverity severity) => switch (severity) {
    LspSeverity.error => diagnosticError,
    LspSeverity.warning => diagnosticWarning,
    LspSeverity.info => diagnosticInfo,
    LspSeverity.hint => diagnosticHint,
  };

  /// Build a wavy underline for a diagnostic range with [severity].
  ///
  /// Designed to merge over a syntax span so its foreground color is preserved.
  static TextStyle underlineStyleFor(LspSeverity severity) => TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: diagnosticColor(severity),
  );

  /// Resolve a palette from its selected ID and the app brightness.
  ///
  /// Each family has light and dark variants so highlighting follows the app
  /// theme.
  static SyntaxColors forId(SyntaxThemeId id, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (id) {
      SyntaxThemeId.one => isDark ? oneDark : oneLight,
      SyntaxThemeId.dracula => isDark ? draculaDark : draculaLight,
      SyntaxThemeId.github => isDark ? githubDark : githubLight,
    };
  }

  /// Resolve a highlight.js scope style.
  ///
  /// Returns `null` to inherit the base unhighlighted style; comments are
  /// italicized.
  TextStyle? styleFor(String scope) {
    final color = _colorFor(scope);
    if (color == null) return null;
    if (scope == 'comment' || scope == 'quote') {
      return TextStyle(color: color, fontStyle: FontStyle.italic);
    }
    return TextStyle(color: color);
  }

  Color? _colorFor(String scope) {
    switch (scope) {
      case 'comment':
      case 'quote':
        return comment;
      case 'keyword':
      case 'selector-tag':
        return keyword;
      case 'string':
      case 'regexp':
      case 'meta-string':
      case 'selector-attr':
      case 'selector-pseudo':
      case 'addition':
        return string;
      case 'number':
      case 'literal':
        return number;
      case 'type':
      case 'class':
      case 'title.class':
        return klass;
      case 'built_in':
      case 'builtin-name':
        return builtin;
      case 'title':
      case 'title.function':
      case 'function':
      case 'section':
        return function;
      case 'attr':
      case 'attribute':
      case 'variable':
      case 'template-variable':
      case 'symbol':
      case 'bullet':
      case 'name':
      case 'selector-id':
      case 'selector-class':
        return variable;
      case 'meta':
      case 'meta-keyword':
      case 'doctag':
      case 'tag':
        return meta;
      case 'deletion':
        return deletion;
      default:
        return null;
    }
  }

  SyntaxColors copyWith({
    Color? background,
    Color? base,
    Color? comment,
    Color? keyword,
    Color? string,
    Color? number,
    Color? klass,
    Color? builtin,
    Color? function,
    Color? variable,
    Color? meta,
    Color? deletion,
  }) {
    return SyntaxColors(
      background: background ?? this.background,
      base: base ?? this.base,
      comment: comment ?? this.comment,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      klass: klass ?? this.klass,
      builtin: builtin ?? this.builtin,
      function: function ?? this.function,
      variable: variable ?? this.variable,
      meta: meta ?? this.meta,
      deletion: deletion ?? this.deletion,
    );
  }
}
