import 'package:app/domain/entities/pending_owner_delivery.dart';

/// Persist app-owned prompts until their exact target session confirms them.
abstract interface class OwnerDeliveryOutbox {
  /// Insert or durably retarget one stable owner delivery.
  Future<void> upsert(PendingOwnerDelivery delivery);

  /// List every unconfirmed delivery owned by one peer room.
  ///
  /// Malformed durable records surface as storage failures; implementations
  /// must not silently omit corrupt entries and create untracked delivery.
  Future<List<PendingOwnerDelivery>> listForRoom({
    required String peerEpk,
    required String roomId,
  });

  /// Remove [id] only when its durable target equals [confirmedSessionId].
  ///
  /// A late old-session echo therefore cannot erase a successor-targeted retry.
  Future<void> removeConfirmed({
    required String id,
    required String confirmedSessionId,
  });
}
