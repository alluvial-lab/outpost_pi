/// Carry an LSP operation failure translated from infrastructure into domain.
///
/// The `data/` layer converts process-spawn and JSON-RPC framing failures so
/// the UI never receives raw `Exception` or `ProcessResult` values.
class LspError {
  const LspError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'LspError: $message';
}
