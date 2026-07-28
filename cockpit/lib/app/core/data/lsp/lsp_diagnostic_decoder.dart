import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';

/// Decode LSP diagnostic publications at the wire/data boundary.
///
/// Domain entities are intentionally constructed only from typed values. This
/// adapter owns all map/list narrowing while retaining the tolerant scalar
/// fallbacks used by the editor.
class LspDiagnosticDecoder {
  const LspDiagnosticDecoder();

  /// Decode a `textDocument/publishDiagnostics` params value.
  ///
  /// A non-map params value is ignored. A valid params map without a list of
  /// diagnostics produces an empty batch, matching LSP's clear-diagnostics
  /// behavior for a document.
  LspDiagnosticsBatch? decodePublishDiagnostics(Object? params) {
    if (params is! Map) return null;
    final uri = params['uri'] is String ? params['uri'] as String : '';
    final rawDiagnostics = params['diagnostics'];
    final diagnostics = <LspDiagnostic>[];
    if (rawDiagnostics is List) {
      for (final wire in rawDiagnostics) {
        final diagnostic = decodeDiagnostic(wire);
        if (diagnostic != null) diagnostics.add(diagnostic);
      }
    }
    return LspDiagnosticsBatch(uri: uri, diagnostics: diagnostics);
  }

  /// Decode one diagnostic, rejecting malformed required range structure.
  LspDiagnostic? decodeDiagnostic(Object? wire) {
    if (wire is! Map) return null;
    final range = decodeRange(wire['range']);
    if (range == null) return null;

    return LspDiagnostic(
      range: range,
      severity: LspSeverity.fromWire(wire['severity']),
      message: wire['message'] is String
          ? (wire['message'] as String).trim()
          : '',
      source: wire['source'] is String ? wire['source'] as String : null,
      code: wire['code'] is String ? wire['code'] as String : null,
    );
  }

  /// Decode a range for other LSP data adapters, such as text edits.
  LspRange? decodeRange(Object? wire) {
    if (wire is! Map) return null;
    final start = _decodePosition(wire['start']);
    final end = _decodePosition(wire['end']);
    if (start == null || end == null) return null;
    return LspRange(start, end);
  }

  LspPosition? _decodePosition(Object? wire) {
    if (wire is! Map) return null;
    final line = wire['line'];
    final character = wire['character'];
    return LspPosition(
      line is num ? line.toInt() : 0,
      character is num ? character.toInt() : 0,
    );
  }
}
