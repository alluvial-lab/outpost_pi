/// Progress snapshot for one app debug-capture delivery attempt.
final class DebugCaptureUploadProgress {
  const DebugCaptureUploadProgress.reading()
    : bytesSent = 0,
      totalBytes = 0,
      reading = true;

  const DebugCaptureUploadProgress.sending({
    required this.bytesSent,
    required this.totalBytes,
  }) : reading = false;

  final int bytesSent;
  final int totalBytes;
  final bool reading;

  double get fraction => totalBytes == 0 ? 0 : bytesSent / totalBytes;
}

/// Successful Pi-side capture delivery acknowledgement.
final class DebugCaptureUploadResult {
  const DebugCaptureUploadResult({
    required this.path,
    required this.bytes,
    required this.events,
  });

  final String path;
  final int bytes;
  final int events;
}

/// Typed capture-delivery failure suitable for direct user recovery copy.
final class DebugCaptureUploadFailure implements Exception {
  const DebugCaptureUploadFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DebugCaptureUploadFailure($code): $message';
}

/// Deliver the latest debug capture through the active sealed owner channel.
abstract interface class DebugCaptureUploader {
  /// Start a fresh upload; retries never resume a prior upload id or sequence.
  Future<DebugCaptureUploadResult> uploadLatest({
    void Function(DebugCaptureUploadProgress progress)? onProgress,
  });
}
