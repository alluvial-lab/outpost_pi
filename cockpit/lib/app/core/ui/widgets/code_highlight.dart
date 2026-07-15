import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' as hl;

/// Map extensions that differ from highlight.js IDs and declare no grammar alias.
///
/// Other extensions such as rs, yml, sh, toml, rb, py, c, and h resolve through
/// grammar aliases; unknown extensions fall back to plain text.
const Map<String, String> _extToLanguage = {
  'ts': 'typescript',
  'tsx': 'typescript',
  'mts': 'typescript',
  'cts': 'typescript',
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
};

/// Limit syntax highlighting to inputs where parsing and span trees are worthwhile.
///
/// Larger input falls back to plain text; the reader already truncates files at
/// 2 MB.
const int _kMaxHighlightChars = 200 * 1024;

/// Represent a diagnostic range as linear UTF-16 code-unit offsets.
///
/// Uses the half-open interval `[start, end)`.
class DiagnosticRange {
  const DiagnosticRange(this.start, this.end, this.severity);

  final int start;
  final int end;
  final LspSeverity severity;
}

/// Convert zero-based LSP UTF-16 positions into linear [DiagnosticRange]s.
///
/// LSP UTF-16 code units map directly to Dart [String] offsets, so conversion
/// uses offset arithmetic rather than `.runes` or `.characters`. Clamps stale
/// positions and expands zero-width ranges to one character when possible so
/// there is a glyph to underline. Shared by the editor and read-only viewer.
List<DiagnosticRange> diagnosticRangesFor(
  String text,
  List<LspDiagnostic> diagnostics,
) {
  if (diagnostics.isEmpty) return const <DiagnosticRange>[];

  // Index each line start at the offset immediately after its preceding `\n`.
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }

  int offsetFor(int line, int character) {
    if (line < 0) return 0;
    if (line >= lineStarts.length) return text.length;
    final base = lineStarts[line];
    final contentEnd = line + 1 < lineStarts.length
        ? lineStarts[line + 1] - 1
        : text.length;
    final offset = base + (character < 0 ? 0 : character);
    return offset.clamp(base, contentEnd);
  }

  final ranges = <DiagnosticRange>[];
  for (final d in diagnostics) {
    var start = offsetFor(d.range.start.line, d.range.start.character);
    var end = offsetFor(d.range.end.line, d.range.end.character);
    if (end < start) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    if (end == start) end = (start + 1).clamp(0, text.length);
    if (end > start) ranges.add(DiagnosticRange(start, end, d.severity));
  }
  return ranges;
}

/// Build highlighted spans for [source] and its file-extension [language].
///
/// Applies wavy underlines over covered [diagnostics]. Returns `null` only when
/// there is nothing special to paint: no language and no diagnostics, oversized
/// input without diagnostics, or an empty parse without diagnostics. The caller
/// then renders plain text.
TextSpan? buildCodeSpan(
  BuildContext context, {
  required String source,
  required String? language,
  required TextStyle baseStyle,
  List<DiagnosticRange> diagnostics = const <DiagnosticRange>[],
}) {
  final palette = context.syntax;
  final leaves = _leavesOf(source, language, palette);
  if (leaves == null) {
    // Without syntax highlighting, only build spans when diagnostics need
    // underlines; otherwise let the caller render plain text.
    if (diagnostics.isEmpty) return null;
    return TextSpan(
      style: baseStyle,
      children: _applyDiagnostics(<_Leaf>[_Leaf(source, null)], diagnostics),
    );
  }
  return TextSpan(
    style: baseStyle,
    children: _applyDiagnostics(leaves, diagnostics),
  );
}

/// Store one flattened highlight.js text leaf and its resolved syntax style.
///
/// Leaf order reconstructs the complete source text.
class _Leaf {
  _Leaf(this.text, this.style);
  final String text;
  final TextStyle? style;
}

/// Parse [source] and flatten the highlight.js tree into styled leaves.
///
/// Returns `null` when highlighting is unavailable because the language is
/// absent, the input is oversized, or parsing yields no nodes.
List<_Leaf>? _leavesOf(String source, String? language, SyntaxColors palette) {
  if (language == null || language.isEmpty) return null;
  if (source.length > _kMaxHighlightChars) return null;

  final lang = _extToLanguage[language.toLowerCase()] ?? language.toLowerCase();
  final nodes = hl.highlight.parse(source, language: lang).nodes;
  if (nodes == null || nodes.isEmpty) return null;

  final leaves = <_Leaf>[];
  for (final node in nodes) {
    _flatten(node, null, palette, leaves);
  }
  return leaves;
}

/// Flatten a highlight.js node while accumulating inherited styles.
///
/// Container class names style their descendants; each node value emits one leaf.
void _flatten(
  hl.Node node,
  TextStyle? inherited,
  SyntaxColors palette,
  List<_Leaf> out,
) {
  final own = node.className == null ? null : palette.styleFor(node.className!);
  final style = own == null
      ? inherited
      : (inherited ?? const TextStyle()).merge(own);
  if (node.value != null) {
    out.add(_Leaf(node.value!, style));
    return;
  }
  final children = node.children;
  if (children == null) return;
  for (final child in children) {
    _flatten(child, style, palette, out);
  }
}

/// Split leaves at diagnostic boundaries and merge wavy underlines into overlaps.
///
/// Preserves syntax colors and returns one span per leaf when diagnostics are
/// absent.
List<InlineSpan> _applyDiagnostics(
  List<_Leaf> leaves,
  List<DiagnosticRange> diagnostics,
) {
  if (diagnostics.isEmpty) {
    return <InlineSpan>[
      for (final leaf in leaves) TextSpan(text: leaf.text, style: leaf.style),
    ];
  }
  final out = <InlineSpan>[];
  var pos = 0;
  for (final leaf in leaves) {
    final start = pos;
    final end = pos + leaf.text.length;
    pos = end;
    if (leaf.text.isEmpty) continue;

    // Split at the leaf boundaries and any diagnostic boundaries within it.
    final cuts = <int>{start, end};
    for (final d in diagnostics) {
      if (d.end <= start || d.start >= end) continue;
      if (d.start > start && d.start < end) cuts.add(d.start);
      if (d.end > start && d.end < end) cuts.add(d.end);
    }
    final sorted = cuts.toList()..sort();
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final sub = leaf.text.substring(a - start, b - start);
      final severity = _coveringSeverity(diagnostics, a, b);
      var style = leaf.style;
      if (severity != null) {
        style = (style ?? const TextStyle()).merge(
          SyntaxColors.underlineStyleFor(severity),
        );
      }
      out.add(TextSpan(text: sub, style: style));
    }
  }
  return out;
}

/// Return the highest severity covering `[a, b)`.
///
/// Priority is error, warning, info, then hint; returns `null` when uncovered.
LspSeverity? _coveringSeverity(
  List<DiagnosticRange> diagnostics,
  int a,
  int b,
) {
  LspSeverity? result;
  for (final d in diagnostics) {
    if (d.start <= a && d.end >= b) {
      // A lower index is more severe (`error` is zero).
      if (result == null || d.severity.index < result.index) {
        result = d.severity;
      }
    }
  }
  return result;
}
