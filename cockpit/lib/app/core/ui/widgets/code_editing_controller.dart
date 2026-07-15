import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/widgets.dart';

/// Render editable text with the read-only viewer's syntax highlighting.
///
/// Overlays LSP diagnostics as wavy underlines. Overriding [buildTextSpan] lets
/// Flutter render highlight.js and diagnostic spans live while preserving the
/// framework's text painting, selection, and cursor behavior.
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text, required this.language});

  /// File extension used for highlighting; null or unknown values use plain text.
  final String? language;

  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// Diagnostics published for this document; assigning them triggers repaint.
  List<LspDiagnostic> get diagnostics => _diagnostics;
  set diagnostics(List<LspDiagnostic> value) {
    _diagnostics = value;
    notifyListeners();
  }

  /// Return the highest severity touching a zero-based line for gutter display.
  LspSeverity? severityForLine(int line) {
    LspSeverity? result;
    for (final d in _diagnostics) {
      if (line >= d.range.start.line && line <= d.range.end.line) {
        if (result == null || d.severity.index < result.index) {
          result = d.severity;
        }
      }
    }
    return result;
  }

  /// Return diagnostic messages touching a zero-based line for its tooltip.
  List<String> messagesForLine(int line) {
    final out = <String>[];
    for (final d in _diagnostics) {
      if (line >= d.range.start.line && line <= d.range.end.line) {
        final src = d.source == null ? '' : '[${d.source}] ';
        out.add('$src${d.message}');
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = buildCodeSpan(
      context,
      source: text,
      language: language,
      baseStyle: style ?? const TextStyle(),
      diagnostics: diagnosticRangesFor(text, _diagnostics),
    );
    return span ?? TextSpan(text: text, style: style);
  }
}
