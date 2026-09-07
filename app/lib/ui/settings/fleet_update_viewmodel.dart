import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/epk_encoding.dart';
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

/// Siblings are ready to arm; carries their acknowledgements (wire: `arming`).
class FleetArming extends FleetUpdateState {
  final List<FleetPeerAck> peers;
  const FleetArming(this.peers);

  @override
  bool operator ==(Object other) =>
      other is FleetArming && listEquals(other.peers, peers);
  @override
  int get hashCode => Object.hashAll(peers);
}

/// The package update ended without a restart arm.
class FleetUpdateFailed extends FleetUpdateState {
  final String detail;
  const FleetUpdateFailed(this.detail);

  @override
  bool operator ==(Object other) =>
      other is FleetUpdateFailed && other.detail == detail;
  @override
  int get hashCode => detail.hashCode;
}

/// The coordinator explicitly declined or could not stage its own restart.
class FleetNoRestart extends FleetUpdateState {
  final String reason;
  const FleetNoRestart(this.reason);

  @override
  bool operator ==(Object other) =>
      other is FleetNoRestart && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
}

/// The transport or pinned room dropped mid-run; the fleet is expected to be
/// restarting behind the disconnect.
class FleetRestarting extends FleetUpdateState {
  final List<FleetPeerAck> peers;
  const FleetRestarting([this.peers = const <FleetPeerAck>[]]);

  @override
  bool operator ==(Object other) =>
      other is FleetRestarting && listEquals(other.peers, peers);
  @override
  int get hashCode => Object.hashAll(peers);
}

/// The pinned room re-announced with a new process-incarnation marker.
class FleetVerified extends FleetUpdateState {
  final List<FleetPeerAck> peers;
  const FleetVerified([this.peers = const <FleetPeerAck>[]]);

  @override
  bool operator ==(Object other) =>
      other is FleetVerified && listEquals(other.peers, peers);
  @override
  int get hashCode => Object.hashAll(peers);
}

/// No pinned-room recovery within the recovery window; normal connection-error
/// UX resumes.
class FleetUpdateLost extends FleetUpdateState {
  const FleetUpdateLost();

  @override
  bool operator ==(Object other) => other is FleetUpdateLost;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Drives the Settings fleet-update section: sends the `fleet_update` client
/// message, folds status events into [FleetUpdateState], and derives restart
/// recovery from pinned room metadata.
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

  /// The complete target identity for the observed run. These values never
  /// follow the app's currently selected peer/room while recovery is active.
  String? _runPeerEpk;
  String? _runRoomId;
  int? _runStartedAt;
  String? _runUpdateId;
  List<FleetPeerAck> _runPeers = const <FleetPeerAck>[];
  final Set<String> _completedUpdateIds = <String>{};
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
      state is FleetNoRestart ||
      state is FleetVerified ||
      state is FleetUpdateLost;

  /// `true` when the currently selected peer's owned room is connected.
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
  /// The peer, room, session, and request id are pinned before recovery starts.
  Future<bool> start() async {
    if (_disposed || !canStart) return false;
    if (!roomConnected) return false;
    _cancelRequestWait();
    _runUpdateId = null;
    _runPeers = const <FleetPeerAck>[];
    _resetRunTarget();

    try {
      final id = await _actions.fleetUpdate();
      if (_disposed) return true;
      _runUpdateId = id;
      _pendingRequestId = id;
      // A status can race the send completion. A terminal status may already
      // have completed this id before the action future resolved as well.
      if (_completedUpdateIds.contains(id)) {
        _pendingRequestId = null;
        return true;
      }
      // If it already moved this run into an active state, its status handler
      // cancelled the request wait.
      if (!_isActiveState) {
        _requestTimer = Timer(_requestTimeout, () {
          if (_disposed || !canStart || _pendingRequestId != id) return;
          _pendingRequestId = null;
          _markTerminal(
            const FleetUpdateFailed(
              'No fleet-update response from the Pi — is its extension up to date?',
            ),
          );
        });
      }
    } on ActionFailure catch (e) {
      if (!_disposed) _markTerminal(FleetUpdateFailed(e.message));
    } catch (e) {
      if (!_disposed) _markTerminal(FleetUpdateFailed(e.toString()));
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
    } else if (_isActiveState) {
      // A selected-peer switch may also emit Connecting. Recovery remains
      // pinned and can only verify after that pinned peer is selected again.
      _cancelRequestWait();
      _pendingRequestId = null;
      _enterRestarting();
    }
    notifyListeners();
  }

  void _onRooms(Map<String, List<RoomInfo>> rooms) {
    if (_disposed) return;
    switch (state) {
      case FleetUpdating() || FleetArming():
        if (_runStartedAt == null && _pinnedRoomLive()) {
          _captureRunRoomBaseline();
        }
        // Room loss is a restart signal even when the relay socket remains up.
        if (!_pinnedRoomLive()) _enterRestarting();
      case FleetRestarting():
        final room = _pinnedRoomFromSnapshot(rooms);
        final recovered =
            _runPeerEpk != null &&
            _runRoomId != null &&
            _conn.activePeer?.remoteEpk == _runPeerEpk &&
            _conn.isRoomLive(_runPeerEpk!, _runRoomId!) &&
            room != null &&
            _runStartedAt != null &&
            room.startedAt != _runStartedAt;
        if (recovered) {
          _markTerminal(FleetVerified(_runPeers));
        }
      default:
        break;
    }
    notifyListeners();
  }

  void _onServerMessage(ServerMessage msg) {
    if (_disposed) return;
    if (msg case FleetUpdateStatus(:final updateId, :final phase)) {
      // Server messages have no peer field; the channel carrying them is the
      // current selected peer. Never let a switched-to peer mutate this run.
      if (_runPeerEpk != null && _conn.activePeer?.remoteEpk != _runPeerEpk) {
        return;
      }
      if (!_acceptUpdateId(updateId, phase)) return;
      switch (msg) {
        case FleetUpdateStatus(:final phase, :final detail, :final peers):
          switch (phase) {
            case 'updating':
              _cancelRequestWait();
              _pendingRequestId = null;
              emit(const FleetUpdating());
              _armRecoveryTimer();
            case 'arming':
              _cancelRequestWait();
              _pendingRequestId = null;
              _runPeers = _parsePeers(peers);
              emit(FleetArming(_runPeers));
              _armRecoveryTimer();
            case 'update_failed':
              _pendingRequestId = null;
              final text = detail == null || detail.isEmpty
                  ? 'update failed'
                  : detail;
              if (text.startsWith('fleet restart not armed:')) {
                _markTerminal(
                  FleetNoRestart(
                    text.substring('fleet restart not armed:'.length).trim(),
                  ),
                );
              } else {
                _markTerminal(FleetUpdateFailed(text));
              }
            case 'already_running':
              // A different owner's rejection is not a result for this run;
              // _acceptUpdateId filters it before this branch.
              _markTerminal(
                const FleetUpdateFailed(
                  'another fleet update is already running',
                ),
              );
            default:
              break;
          }
      }
    } else if (msg case ErrorMessage(:final inReplyTo, :final message)) {
      if (inReplyTo == null || inReplyTo != _pendingRequestId) return;
      _cancelRequestWait();
      _pendingRequestId = null;
      _markTerminal(
        FleetUpdateFailed('Pi rejected the fleet update: $message'),
      );
    }
  }

  bool _acceptUpdateId(String updateId, String phase) {
    if (_completedUpdateIds.contains(updateId)) return false;
    final current = _runUpdateId;
    if (current == null) {
      if (phase == 'already_running') return false;
      _runUpdateId = updateId;
      _resetRunTarget();
      return true;
    }
    if (current == updateId) return true;
    // A live run is authoritative for this ViewModel. In particular, another
    // owner's `already_running` must not terminate the observed run.
    if (_isActiveState) return false;
    _completedUpdateIds.add(current);
    if (phase == 'already_running') return false;
    _runUpdateId = updateId;
    _resetRunTarget();
    return true;
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

  bool get _isActiveState =>
      state is FleetUpdating ||
      state is FleetArming ||
      state is FleetRestarting;

  void _resetRunTarget() {
    final epk = _conn.activePeer?.remoteEpk;
    _runPeerEpk = epk;
    _runRoomId = epk == null ? null : _conn.activeRoomId;
    _runStartedAt = null;
    if (epk != null) {
      for (final room in _conn.roomsFor(epk)) {
        if (room.roomId == _runRoomId) {
          _runStartedAt = room.startedAt;
          break;
        }
      }
    }
  }

  void _captureRunRoomBaseline() {
    final epk = _runPeerEpk;
    final roomId = _runRoomId;
    if (epk == null || roomId == null) return;
    for (final room in _conn.roomsFor(epk)) {
      if (room.roomId == roomId) {
        _runStartedAt = room.startedAt;
        return;
      }
    }
  }

  bool _pinnedRoomLive() {
    final epk = _runPeerEpk;
    final roomId = _runRoomId;
    if (_conn.status is! StatusOnline || epk == null || roomId == null) {
      return false;
    }
    if (_conn.activePeer?.remoteEpk != epk) return false;
    return _conn.isRoomLive(epk, roomId);
  }

  List<RoomInfo> _pinnedRoomsFromSnapshot(Map<String, List<RoomInfo>> rooms) =>
      _runPeerEpk == null
      ? const <RoomInfo>[]
      : rooms.entries
            .where(
              (entry) =>
                  toStandardB64(entry.key) == toStandardB64(_runPeerEpk!),
            )
            .expand((entry) => entry.value)
            .toList(growable: false);

  RoomInfo? _pinnedRoomFromSnapshot(Map<String, List<RoomInfo>> rooms) {
    final roomId = _runRoomId;
    if (roomId == null) return null;
    for (final room in _pinnedRoomsFromSnapshot(rooms)) {
      if (room.roomId == roomId) return room;
    }
    return null;
  }

  void _armRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(_recoveryTimeout, () {
      if (_disposed || !_isActiveState) return;
      _markTerminal(const FleetUpdateLost());
    });
  }

  void _enterRestarting() {
    if (!_isActiveState && state is! FleetRestarting) return;
    emit(FleetRestarting(_runPeers));
    _armRecoveryTimer();
  }

  void _markTerminal(FleetUpdateState terminal) {
    _cancelRequestWait();
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    if (_runUpdateId != null) _completedUpdateIds.add(_runUpdateId!);
    emit(terminal);
  }

  void _cancelRequestWait() {
    _requestTimer?.cancel();
    _requestTimer = null;
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
