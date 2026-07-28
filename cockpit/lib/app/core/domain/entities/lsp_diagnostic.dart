/// Define LSP entities shared by the UI and gateway, independent of JSON-RPC.
///
/// Positions are zero-based. `character` counts UTF-16 code units, matching
/// Dart strings and Flutter offsets; see `CodeEditingController.offsetFor`.
library;

/// Represent a zero-based LSP position within a document.
class LspPosition {
  const LspPosition(this.line, this.character);

  final int line;
  final int character;
}

/// Represent a half-open `[start, end)` document range.
class LspRange {
  const LspRange(this.start, this.end);

  final LspPosition start;
  final LspPosition end;
}

/// Represent the one-based LSP `DiagnosticSeverity` values.
enum LspSeverity {
  error,
  warning,
  info,
  hint;

  /// Map the wire integer from 1 (error) through 4 (hint).
  ///
  /// Missing or invalid severity defaults defensively to [error].
  static LspSeverity fromWire(Object? value) {
    return switch ((value as num?)?.toInt()) {
      2 => LspSeverity.warning,
      3 => LspSeverity.info,
      4 => LspSeverity.hint,
      _ => LspSeverity.error,
    };
  }
}

/// Represent one diagnostic from `textDocument/publishDiagnostics`.
class LspDiagnostic {
  const LspDiagnostic({
    required this.range,
    required this.severity,
    required this.message,
    this.source,
    this.code,
  });

  final LspRange range;
  final LspSeverity severity;
  final String message;

  /// Optional source, such as `dart` or `eslint`, shown beside the message.
  final String? source;

  /// Optional diagnostic code supplied by the language server.
  final String? code;
}

/// Group one publication's diagnostics for a document URI.
class LspDiagnosticsBatch {
  const LspDiagnosticsBatch({required this.uri, required this.diagnostics});

  /// Document URI, such as `file:///...`.
  final String uri;
  final List<LspDiagnostic> diagnostics;
}
