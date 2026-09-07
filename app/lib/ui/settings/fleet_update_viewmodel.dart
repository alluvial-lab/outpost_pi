import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:flutter/foundation.dart';

/// One sibling's arm-restart acknowledgement, as reported by the coordinator.
class FleetPeerAck {
  final String peer;
  final String state; // armed | deferred | declined | no-ack
  final String? reason;

  const FleetPeerAck({required this.peer, required this.state, this.reason});

  /// Narrow one raw wire row; returns `null` when the row is malformed.
  static FleetPeerAck? fromWire(Map<String, dynamic> json) {
    final peer = json['peer'];
    final state = json['state'];
    if (peer is! String || peer.isEmpty || state is! String) return null;
    switch (state) {
      case 'armed':
      case 'deferred':
      case 'declined':
      case 'no-ack':
        break;
      default:
        return null;
    }
    final reason = json['reason'];
    return FleetPeerAck(
      peer: peer,
      state: state,
      reason: reason is String && reason.isNotEmpty ? reason : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FleetPeerAck &&
      other.peer == peer &&
      other.state == state &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(peer, state, reason);
}

/// Lifecycle of one fleet update run as shown in Settings.
///
/// `FleetUpdating`/`FleetArming` mirror the wire `fleet_update_status`
/// phases; `FleetRestarting`/`FleetVerified`/`FleetUpdateLost` are DERIVED
/// app-side from transport drop and room re-announce, because the
/// coordinator Pi cannot report its own restart. `FleetUpdateFailed` is
/// terminal for the run (a later run may start from it).
sealed class FleetUpdateState {
  const FleetUpdateState();
}

/// No run in progress (or ever observed).
class FleetIdle extends FleetUpdateState {
  const FleetIdle();

  @override
  bool operator ==(Object other) => other is FleetIdle;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// The coordinator Pi is running the package update (wire: `updating`).
class FleetUpdating extends FleetUpdateState {
  const FleetUpdating();

  @override
  bool operator ==(Object other) => other is FleetUpdating;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Siblings are arming; carries their acknowledgements (wire: `arming`).
class FleetArming extends FleetUpdateState {
  final List<FleetPeerAck> peers;
  const FleetArming(this.peers);

  @override
  bool operator ==(Object other) =>
      other is FleetArming && listEquals(other.peers, peers);
  @override
  int get hashCode => Object.hashAll(peers);
}

/// The run ended without arming (wire: `update_failed`/`already_running`,
/// or a request that never produced status).
class FleetUpdateFailed extends FleetUpdateState {
  final String detail;
  const FleetUpdateFailed(this.detail);

  @override
  bool operator ==(Object other) =>
      other is FleetUpdateFailed && other.detail == detail;
  @override
  int get hashCode => detail.hashCode;
}

/// Derived: the transport dropped mid-run — the fleet is expected to be
/// restarting behind the disconnect.
class FleetRestarting extends FleetUpdateState {
  const FleetRestarting();

  @override
  bool operator ==(Object other) => other is FleetRestarting;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Derived: the active room re-announced after the restart window.
class FleetVerified extends FleetUpdateState {
  const FleetVerified();

  @override
  bool operator ==(Object other) => other is FleetVerified;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Derived: no room recovery within the recovery window — normal
/// connection-error UX resumes.
class FleetUpdateLost extends FleetUpdateState {
  const FleetUpdateLost();

  @override
  bool operator ==(Object other) => other is FleetUpdateLost;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Drives the Settings fleet-update section: sends the `fleet_update`
/// client message, folds `fleet_update_status` events into
/// [FleetUpdateState], and derives `restarting`/`verified`/`lost` from
/// transport and room-recovery signals.
///
/// While a run is live (updating/arming/restarting),
/// [suppressConnectionErrors] is `true` — the expected mass disconnect of
/// a fleet restart must not trip the app's reconnect-error UX. The flag is
/// derived from the state, so every terminal transition (failed, verified,
/// lost, or a fresh idle run) clears it by construction.
///
/// Wire status events are not filtered by `update_id`: every owner of the
/// room sees the same broadcast events, and a second trigger while a run is
/// live answers `already_running` whose follow-up events then belong to the
/// in-flight run. A wire event arriving while the run is derived `restarting`
/// resumes wire-following — it proves the coordinator Pi never exited (a
/// transport flap, not the fleet restart).
class FleetUpdateViewModel extends ViewModel<FleetUpdateState> {
  final ConnectionManager _conn;
  final IActionsRepository _actions;
  final Duration _recoveryTimeout;
  final Duration _requestTimeout;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<ServerMessage>? _msgSub;
  Timer? _recoveryTimer;
  Timer? _requestTimer;
  String? _pendingRequestId;

  /// Session id the live run is tracking; the restart window verifies
  /// against it (a fresh Pi process announces a fresh session id).
  String? _runSessionId;

  /// Room the live run is watching, pinned at run start. The manager may
  /// retarget its active room when this one dies; the run must not follow.
  String? _runRoomId;
  bool _disposed = false;

  FleetUpdateViewModel(
    this._conn,
    this._actions, {
    Duration recoveryTimeout = const Duration(minutes: 5),
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _recoveryTimeout = recoveryTimeout,
       _requestTimeout = requestTimeout,
       super(const FleetIdle()) {
    _statusSub = _conn.statusStream.listen(_onStatus);
    _roomsSub = _conn.roomsStream.listen(_onRooms);
    _onStatus(_conn.status);
  }

  /// `true` while a fleet run is live and reconnect-error UX must stay quiet.
  bool get suppressConnectionErrors =>
      state is FleetUpdating ||
      state is FleetArming ||
      state is FleetRestarting;

  /// `true` when a new run may be started (idle or a terminal state).
  bool get canStart =>
      state is FleetIdle ||
      state is FleetUpdateFailed ||
      state is FleetVerified ||
      state is FleetUpdateLost;

  /// `true` when the active peer's owned room is connected.
  bool get roomConnected {
    if (_conn.status is! StatusOnline) return false;
    final epk = _conn.activePeer?.remoteEpk;
    if (epk == null) return false;
    return _conn.isRoomLive(epk, _conn.activeRoomId);
  }

  /// Human-readable reason a run cannot start now; `null` when it can.
  String? get startBlockedReason {
    if (_conn.activePeer == null) return 'No paired Pi selected';
    return switch (_conn.status) {
      StatusNoPeer() => 'No paired Pi selected',
      StatusConnecting() => 'Connecting to the Pi…',
      StatusOnline() when roomConnected => null,
      _ => 'Pi room not connected',
    };
  }

  /// Request a fleet update from the connected Pi after user confirmation.
  ///
  /// Returns `false` when a run is already live or no room is connected.
  /// Send failures land in [state] as [FleetUpdateFailed]; a request that
  /// never produces a status event (for example an old extension build)
  /// fails via the request timeout.
  Future<bool> start() async {
    if (_disposed || !canStart) return false;
    if (!roomConnected) return false;
    _cancelRequestWait();
    // Pin the target before sending. ConnectionManager may retarget
    // activeRoomId when the watched room disappears; recovery must still
    // verify the room/session that this run actually addressed.
    _runRoomId = _conn.activeRoomId;
    _runSessionId = _conn.activeSessionId;

    try {
      final id = await _actions.fleetUpdate();
      if (_disposed) return true;
      _pendingRequestId = id;
      _requestTimer = Timer(_requestTimeout, () {
        if (_disposed || !canStart) return;
        _pendingRequestId = null;
        emit(
          const FleetUpdateFailed(
            'No fleet-update response from the Pi — is its extension up to date?',
          ),
        );
      });
    } on ActionFailure catch (e) {
      if (!_disposed) emit(FleetUpdateFailed(e.message));
    } catch (e) {
      if (!_disposed) emit(FleetUpdateFailed(e.toString()));
    }
    return true;
  }

  void _onStatus(ConnectionStatus status) {
    if (_disposed) return;
    _msgSub?.cancel();
    _msgSub = null;
    if (status is StatusOnline) {
      _msgSub = status.channel.serverMessages.listen(
        _onServerMessage,
        onError: (Object _, StackTrace _) {},
      );
    } else if (state is FleetUpdating || state is FleetArming) {
      // Derivation rule: an active run + transport drop = the fleet is
      // restarting behind the disconnect.
      _cancelRequestWait();
      _pendingRequestId = null;
      _enterRestarting();
    }
    // Room connectivity is derived from live manager state; notify so the
    // section re-evaluates its disabled-with-reason copy.
    notifyListeners();
  }

  void _onRooms(Map<String, List<RoomInfo>> rooms) {
    if (_disposed) return;
    switch (state) {
      case FleetUpdating() || FleetArming():
        // Derive the restart window from ROOM loss, not only from an
        // app-transport drop: a fleet restart ends the Pi's relay room
        // while the app's own relay socket stays online.
        if (!_pinnedRoomLive()) _enterRestarting();
      case FleetRestarting():
        final epk = _conn.activePeer?.remoteEpk;
        final roomId = _runRoomId ?? _conn.activeRoomId;
        final room = epk == null
            ? null
            : (rooms[epk] ?? const <RoomInfo>[])
                  .where((r) => r.roomId == roomId)
                  .firstOrNull;
        // Verified = the run's pinned room is back in the live set under a
        // non-null FRESH session id. Cached-list replays after a reconnect
        // carry the old session id (or none) and must not verify; a
        // same-session return is a flap.
        final baselineSessionId = _runSessionId;
        final recovered =
            epk != null &&
            _conn.isRoomLive(epk, roomId) &&
            room != null &&
            baselineSessionId != null &&
            baselineSessionId.isNotEmpty &&
            room.sessionId?.isNotEmpty == true &&
            room.sessionId != baselineSessionId;
        if (recovered) {
          _recoveryTimer?.cancel();
          _recoveryTimer = null;
          emit(const FleetVerified());
        }
      default:
        break;
    }
    notifyListeners();
  }

  void _onServerMessage(ServerMessage msg) {
    if (_disposed) return;
    switch (msg) {
      case FleetUpdateStatus(:final phase, :final detail, :final peers):
        // A status event while restarting means the coordinator Pi is
        // alive and still reporting — the drop was a flap, not the fleet
        // restart. Resume wire-following (the recovery timer keeps
        // guarding the window).
        switch (phase) {
          case 'updating':
            _cancelRequestWait();
            _adoptRunSession();
            emit(const FleetUpdating());
          case 'arming':
            _cancelRequestWait();
            _adoptRunSession();
            emit(FleetArming(_parsePeers(peers)));
          case 'update_failed':
            _cancelRequestWait();
            _pendingRequestId = null;
            emit(
              FleetUpdateFailed(
                detail == null || detail.isEmpty ? 'update failed' : detail,
              ),
            );
          case 'already_running':
            _cancelRequestWait();
            _pendingRequestId = null;
            emit(
              const FleetUpdateFailed(
                'another fleet update is already running',
              ),
            );
          default:
            break; // unknown phase — forward compatibility
        }
      case ErrorMessage(:final inReplyTo, :final message):
        if (inReplyTo == null || inReplyTo != _pendingRequestId) return;
        _cancelRequestWait();
        _pendingRequestId = null;
        emit(FleetUpdateFailed('Pi rejected the fleet update: $message'));
      default:
        break;
    }
  }

  static List<FleetPeerAck> _parsePeers(dynamic wire) {
    if (wire is! List) return const <FleetPeerAck>[];
    return wire
        .map(
          (item) => switch (item) {
            Map() => FleetPeerAck.fromWire(item.cast<String, dynamic>()),
            _ => null,
          },
        )
        .whereType<FleetPeerAck>()
        .toList(growable: false);
  }

  void _cancelRequestWait() {
    _requestTimer?.cancel();
    _requestTimer = null;
  }

  /// Pin the room and session id for wire-observed runs that did not originate
  /// in [start]. User-triggered runs pin these values before sending.
  void _adoptRunSession() {
    if (_runRoomId != null) return;
    final epk = _conn.activePeer?.remoteEpk;
    if (epk == null) return;
    for (final room in _conn.roomsFor(epk)) {
      if (room.roomId == _conn.activeRoomId) {
        _runRoomId = room.roomId;
        _runSessionId = room.sessionId;
        return;
      }
    }
  }

  bool _pinnedRoomLive() {
    if (_conn.status is! StatusOnline) return false;
    final epk = _conn.activePeer?.remoteEpk;
    final roomId = _runRoomId ?? _conn.activeRoomId;
    return epk != null && _conn.isRoomLive(epk, roomId);
  }

  void _enterRestarting() {
    emit(const FleetRestarting());
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(_recoveryTimeout, () {
      if (_disposed || state is! FleetRestarting) return;
      emit(const FleetUpdateLost());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _statusSub?.cancel();
    _roomsSub?.cancel();
    _msgSub?.cancel();
    _recoveryTimer?.cancel();
    _requestTimer?.cancel();
    super.dispose();
  }
}
