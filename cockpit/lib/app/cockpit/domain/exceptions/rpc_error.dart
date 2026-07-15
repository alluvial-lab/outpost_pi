/// Represent an RPC process failure translated from the I/O adapter boundary.
///
/// This domain-safe form prevents raw `Exception` and `Map<String,dynamic>`
/// values from leaking out of `data/` into the domain or UI.
class RpcError {
  const RpcError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'RpcError: $message';
}
