/// Carry a relay or device-connectivity failure translated into domain.
///
/// The `data/` layer converts outpost-pi process and configuration failures so
/// the UI never receives raw `Exception` or `ProcessResult` values.
class RelayError {
  const RelayError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'RelayError: $message';
}
