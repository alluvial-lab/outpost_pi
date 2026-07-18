import 'dart:async';

import 'package:flutter/widgets.dart';

/// Own a detached UI future and forward failures to the originating zone.
///
/// Use at synchronous Flutter lifecycle and callback boundaries that cannot
/// await their asynchronous work. The caller's zone remains responsible for
/// uncaught-error reporting.
void ownAsync(Future<void> future) {
  final zone = Zone.current;
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      zone.handleUncaughtError(error, stackTrace);
    }),
  );
}

/// Adapt an asynchronous action to a synchronous Flutter callback.
///
/// The action is invoked once when the callback runs. Synchronous exceptions
/// still escape to the caller; failures from the returned future are forwarded
/// through [ownAsync].
VoidCallback ownedAsyncAction(Future<void> Function() action) {
  return () => ownAsync(action());
}
