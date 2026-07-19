import 'dart:async';

/// Poll a bounded predicate and retain only a phase-safe description on timeout.
Future<T> eventually<T>(
  Future<T?> Function() probe, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final result = await probe();
      if (result != null) return result;
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'timed out waiting for $description'
    '${lastError == null ? '' : ' (last=${lastError.runtimeType})'}',
    timeout,
  );
}
