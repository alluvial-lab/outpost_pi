/// Represent a paired relay device read from `~/.pi/remote/peers.json`.
///
/// Cockpit only lists and revokes devices. Pairing and QR generation happen on
/// the app or agent side; no `outpost-pi pair` command exists.
class PairedDevice {
  const PairedDevice({required this.shortId, required this.label});

  /// Short identifier passed to `outpost-pi revoke <shortId>` as one argument.
  ///
  /// May contain base64 characters such as `+` and `/`.
  final String shortId;

  /// Human-readable device label reported by the relay.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is PairedDevice && other.shortId == shortId && other.label == label;

  @override
  int get hashCode => Object.hash(shortId, label);
}
