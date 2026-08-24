import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/protocol/protocol.dart';

/// Describe one semantic transition of the canonical room snapshot.
///
/// Consumers use the typed edge to avoid repeating storage, binding, or UI
/// work when a full snapshot does not change the value they own. [snapshot]
/// remains the authoritative room map; this object is only a dispatch contract.
sealed class RoomSnapshotChange {
  const RoomSnapshotChange({
    required this.snapshot,
    required this.activePeerEpk,
    required this.activeRoomId,
    required this.activeRoomPresentationChanged,
    required this.homePresentationChanged,
    required this.activeRoomLivenessChanged,
    required this.transportGenerationChanged,
  });

  /// Canonical full room map at this transition.
  final Map<String, List<RoomInfo>> snapshot;

  /// Canonical EPK for the room active when the transition was derived.
  final String? activePeerEpk;

  /// Room active when the transition was derived.
  final String activeRoomId;

  /// Whether Chat's active-room projection can visibly change.
  final bool activeRoomPresentationChanged;

  /// Whether Home's room tiles, working state, or liveness can change.
  final bool homePresentationChanged;

  /// Whether the active room crossed its fresh/stale liveness boundary.
  final bool activeRoomLivenessChanged;

  /// Whether the transport owner changed since the previous room emission.
  final bool transportGenerationChanged;

  /// Whether this edge belongs to the supplied active room.
  bool affectsRoom(String epk, String roomId) =>
      activePeerEpk == toStandardB64(epk) && activeRoomId == roomId;

  /// Whether the active session binding must be refreshed.
  bool get requiresBinding;

  /// Whether held messages may be replayed after current-lifecycle checks.
  bool get requiresHeldReplay;

  /// Whether no consumer-visible semantic value changed.
  bool get isNoop => false;
}

/// Represent a canonical emission with no semantic change.
final class RoomSnapshotNoop extends RoomSnapshotChange {
  const RoomSnapshotNoop({
    required super.snapshot,
    required super.activePeerEpk,
    required super.activeRoomId,
  }) : super(
         activeRoomPresentationChanged: false,
         homePresentationChanged: false,
         activeRoomLivenessChanged: false,
         transportGenerationChanged: false,
       );

  @override
  bool get requiresBinding => false;

  @override
  bool get requiresHeldReplay => false;

  @override
  bool get isNoop => true;
}

/// Represent room metadata, selection, or liveness presentation changes.
final class RoomSnapshotPresentationChanged extends RoomSnapshotChange {
  const RoomSnapshotPresentationChanged({
    required super.snapshot,
    required super.activePeerEpk,
    required super.activeRoomId,
    required super.activeRoomPresentationChanged,
    required super.homePresentationChanged,
    required super.activeRoomLivenessChanged,
    required super.transportGenerationChanged,
  });

  @override
  bool get requiresBinding => false;

  @override
  bool get requiresHeldReplay => false;
}

/// Represent a changed active-session identity.
final class RoomSnapshotSessionRotated extends RoomSnapshotChange {
  const RoomSnapshotSessionRotated({
    required super.snapshot,
    required super.activePeerEpk,
    required super.activeRoomId,
    required super.activeRoomPresentationChanged,
    required super.homePresentationChanged,
    required super.activeRoomLivenessChanged,
    required super.transportGenerationChanged,
  });

  @override
  bool get requiresBinding => true;

  @override
  bool get requiresHeldReplay => true;
}

/// Represent authoritative confirmation that the active room is fresh again.
final class RoomSnapshotFreshLive extends RoomSnapshotChange {
  const RoomSnapshotFreshLive({
    required super.snapshot,
    required super.activePeerEpk,
    required super.activeRoomId,
    required super.activeRoomPresentationChanged,
    required super.homePresentationChanged,
    required super.activeRoomLivenessChanged,
    required super.transportGenerationChanged,
  });

  @override
  bool get requiresBinding => true;

  @override
  bool get requiresHeldReplay => true;
}
