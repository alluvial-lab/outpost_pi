/// Represent typed events from an `/outpost-pi pair` session.
///
/// The `data/` adapter reads the token-bearing pair code from its private file
/// seam and translates the token-free pairing-complete RPC event. The UI never
/// receives an untyped `Map<String, dynamic>`.
sealed class PairEvent {
  const PairEvent();
}

/// Carry a newly generated pair code read from Cockpit's private file seam.
///
/// [uri] becomes the QR code; the remaining fields support copying pairing
/// details. Periodic renewal re-emits this event so callers can refresh the QR.
final class PairCodeReady extends PairEvent {
  const PairCodeReady({
    required this.uri,
    this.token,
    this.expiresAt,
    this.roomId,
    this.name,
  });

  final String uri;
  final String? token;
  final String? expiresAt;
  final String? roomId;
  final String? name;
}

/// Signal that a device scanned the QR code and completed pairing.
final class PairDevicePaired extends PairEvent {
  const PairDevicePaired({this.name});
  final String? name;
}

/// Report failure to start or conduct pairing, including timeout or missing extension.
final class PairFailed extends PairEvent {
  const PairFailed(this.message);
  final String message;
}
