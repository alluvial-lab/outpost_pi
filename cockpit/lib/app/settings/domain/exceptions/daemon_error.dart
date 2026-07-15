/// Carry a typed daemon-operation failure across the domain boundary.
///
/// Data adapters translate `pi-supervisord` UDS and `outpost-pi` process errors
/// into this type so raw exceptions never leak into the domain.
class DaemonError {
  const DaemonError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'DaemonError: $message';
}
