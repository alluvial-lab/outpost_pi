import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

/// Number of attempts used for transient Hive file-lock failures at boot.
const int defaultHiveOpenAttempts = 10;

/// Run a file-backed operation again when the OS reports a transient lock.
///
/// The final [FileSystemException] is rethrown after [attempts] attempts. Other
/// exceptions are not retryable and propagate immediately.
Future<T> withFileSystemRetry<T>(
  Future<T> Function() operation, {
  int attempts = defaultHiveOpenAttempts,
  Duration delay = const Duration(milliseconds: 300),
}) async {
  if (attempts < 1) {
    throw ArgumentError.value(attempts, 'attempts', 'Must be positive');
  }

  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await operation();
    } on FileSystemException {
      if (attempt == attempts) rethrow;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
  }

  throw StateError('Retry loop exhausted without a result');
}

/// Open a Hive box while tolerating a short-lived OS lock after shutdown.
Future<Box<T>> openHiveBoxWithRetry<T>(
  String name, {
  int attempts = defaultHiveOpenAttempts,
  Duration delay = const Duration(milliseconds: 300),
}) => withFileSystemRetry(
  () => Hive.openBox<T>(name),
  attempts: attempts,
  delay: delay,
);
