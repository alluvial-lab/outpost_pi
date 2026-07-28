import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';

import 'lsp_diagnostic_decoder.dart';

/// Represent an LSP `TextEdit` returned by `textDocument/formatting`.
///
/// Replaces the text in [range] with [newText] when applied to a buffer.
class LspTextEdit {
  const LspTextEdit({required this.range, required this.newText});

  final LspRange range;
  final String newText;

  factory LspTextEdit.fromJson(Map<String, dynamic> json) {
    final range = const LspDiagnosticDecoder().decodeRange(json['range']);
    if (range == null) {
      throw const FormatException('LSP text edit has an invalid range.');
    }
    return LspTextEdit(range: range, newText: json['newText'] as String? ?? '');
  }
}

/// Parse a `textDocument/formatting` result into typed edits.
///
/// Returns an empty list for a null, empty, or non-list result.
List<LspTextEdit> parseTextEdits(Object? result) {
  if (result is! List) return const <LspTextEdit>[];
  return <LspTextEdit>[
    for (final e in result)
      if (e is Map<String, dynamic>) LspTextEdit.fromJson(e),
  ];
}

/// Apply [edits] to [text] and return the formatted text.
///
/// LSP positions use zero-based `line`/`character` coordinates in UTF-16.
/// Applies edits from the highest start offset to the lowest so later text
/// changes do not shift earlier offsets.
///
/// LSP UTF-16 code units map one-to-one to Dart [String] code units, so offset
/// arithmetic is used rather than `.runes` or `.characters`.
String applyTextEdits(String text, List<LspTextEdit> edits) {
  if (edits.isEmpty) return text;

  // Index each line start at the offset immediately after its preceding `\n`.
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }
  int offsetFor(LspPosition p) {
    if (p.line < 0) return 0;
    if (p.line >= lineStarts.length) return text.length;
    final base = lineStarts[p.line];
    final lineEnd = p.line + 1 < lineStarts.length
        ? lineStarts[p.line + 1] - 1
        : text.length;
    return (base + (p.character < 0 ? 0 : p.character)).clamp(base, lineEnd);
  }

  // Resolve edits to (start, end, newText) and sort by descending start.
  final resolved = <({int start, int end, String newText})>[
    for (final e in edits)
      (
        start: offsetFor(e.range.start),
        end: offsetFor(e.range.end),
        newText: e.newText,
      ),
  ]..sort((a, b) => b.start.compareTo(a.start));

  var result = text;
  for (final e in resolved) {
    final start = e.start.clamp(0, result.length);
    final end = e.end.clamp(start, result.length);
    result = result.replaceRange(start, end, e.newText);
  }
  return result;
}
