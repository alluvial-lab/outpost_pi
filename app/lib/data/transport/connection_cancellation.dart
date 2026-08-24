import 'dart:async';

/// Run teardown when an in-flight connection attempt is superseded.
typedef ConnectionCancellationListener = FutureOr<void> Function();

/// Expose synchronous cancellation state plus awaitable resource teardown.
abstract interface class ConnectionCancellation {
  /// Whether cancellation has already been requested.
  bool get isCancelled;

  /// Run [listener] when cancellation is requested.
  void addCancellationListener(ConnectionCancellationListener listener);

  /// Stop retaining [listener] when the owning operation has settled.
  void removeCancellationListener(ConnectionCancellationListener listener);
}
