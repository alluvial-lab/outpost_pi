import 'package:app/domain/session_state.dart';

/// Preserve one app-owned prompt until its target session confirms acceptance.
final class PendingOwnerDelivery {
  const PendingOwnerDelivery({
    required this.id,
    required this.peerEpk,
    required this.roomId,
    required this.targetSessionId,
    required this.text,
    required this.createdAt,
    this.image,
    this.awaitingPickup = false,
  });

  final String id;
  final String peerEpk;
  final String roomId;
  final String? targetSessionId;
  final String text;
  final DateTime createdAt;
  final MessageImage? image;
  final bool awaitingPickup;

  /// Retarget this stable delivery id before sending it to a canonical session.
  PendingOwnerDelivery target(String sessionId) => PendingOwnerDelivery(
    id: id,
    peerEpk: peerEpk,
    roomId: roomId,
    targetSessionId: sessionId,
    text: text,
    createdAt: createdAt,
    image: image,
    awaitingPickup: awaitingPickup,
  );

  @override
  bool operator ==(Object other) =>
      other is PendingOwnerDelivery &&
      other.id == id &&
      other.peerEpk == peerEpk &&
      other.roomId == roomId &&
      other.targetSessionId == targetSessionId &&
      other.text == text &&
      other.createdAt == createdAt &&
      other.image == image &&
      other.awaitingPickup == awaitingPickup;

  @override
  int get hashCode => Object.hash(
    id,
    peerEpk,
    roomId,
    targetSessionId,
    text,
    createdAt,
    image,
    awaitingPickup,
  );
}
