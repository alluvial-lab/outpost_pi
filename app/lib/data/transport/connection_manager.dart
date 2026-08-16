// ConnectionManager — lifecycle of the relay connection.
//
// State machine:
//
//   [noPeer] → connect() → [connecting] → success → [online]
//                              ↓                         ↓
//                           failure               (WS close or 2 ping misses)
//                              ↓                         ↓
//                          [offline] ←── canRetry=false
//                          [retrying] ←── backoff 1→2→5→10→30s
//                              ↓
//                          connect() → [connecting] → …
//
// Ping: every 25 s. The reachability adapter increments missed pings per
// tick BEFORE sending the next ping; inbound traffic (handled by the channel
// listener) resets the counter back to 0. Repeated silence marks the active
// room offline while the relay socket remains up.
//
// Post plan offline-loop (4 patches):
//
//  A) `_channelSub` is stored and cancelled on every transition. The old
//     channel's `onDone` (triggered by the relay killing it on duplicate
//     auth) can no longer leak into a retry storm.
//  B) Retry attempt state is no longer reset on factory success — only when
//     the channel listener receives real inbound traffic. With the Pi down
//     the WS keeps re-authenticating against the relay; without this fix
//     the backoff stayed pinned at 1s.
//  C) `_startPing` delegates missed-ping counting to the reachability adapter
//     before sending the ping. Inbound (`_watchChannel` listener) is the only
//     path that zeroes it; with the Pi offline the active room is marked
//     offline without a leaky-bucket race.

import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/data/transport/reachability_adapter.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:flutter/foundation.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';

// ---------------------------------------------------------------------------
// Status model
// ---------------------------------------------------------------------------

/// Represent the relay connection lifecycle consumed by UI and services.
sealed class ConnectionStatus {
  const ConnectionStatus();
}

/// No paired peer is currently selected for connection.
class StatusNoPeer extends ConnectionStatus {
  const StatusNoPeer();
}

/// A connection attempt is in flight; no channel may be used yet.
class StatusConnecting extends ConnectionStatus {
  const StatusConnecting();
}

/// A live relay channel is available for the active peer and room.
class StatusOnline extends ConnectionStatus {
  final IChannel channel;
  const StatusOnline(this.channel);
}

/// A retryable connection failure is waiting for its backoff deadline.
class StatusRetrying extends ConnectionStatus {
  final Duration nextRetry;
  final int attempt; // 0-based
  const StatusRetrying({required this.nextRetry, required this.attempt});
}

/// Connection is unavailable, optionally requiring user recovery before retry.
class StatusOffline extends ConnectionStatus {
  final String reason;
  final bool canRetry;
  const StatusOffline({required this.reason, this.canRetry = true});
}

// ---------------------------------------------------------------------------
// Factory typedef — injectable for tests
// ---------------------------------------------------------------------------

/// Called to establish a new connection for a given peer.
/// Returns an [IChannel] on success, throws on failure.
typedef ConnectionFactory =
    Future<IChannel> Function(PeerRecord peer, CancelToken cancel);

/// Let connection factories abandon work after their lifecycle is superseded.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

// ---------------------------------------------------------------------------
// ConnectionManager
// ---------------------------------------------------------------------------

/// Own relay connection state, retry timers, room snapshots, and teardown.
///
/// This service is the authority for connection liveness. It rehydrates relay
/// snapshots after reconnect and disposes channels, subscriptions, and timers
/// together so stale transports cannot update a replacement session.
class ConnectionManager extends Service {
  final ConnectionFactory _factory;
  final PairingStorage _storage;
  final DebugLog? _debugLog;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  // Presence (plan 12): map per remote_epk + a broadcast stream the UI
  // listens to. The map is emitted whole on every change for simple
  // diffing on the consumer side.
  final Map<String, PresenceState> _presence = <String, PresenceState>{};
  final _presenceController =
      StreamController<Map<String, PresenceState>>.broadcast();
  // Plan 17 — rooms tracking. Keys are STANDARD base64 epks (matches
  // presence map). Each value is the canonical room list for that peer.
  // Plan-17 follow-up — `_roomsByPeer` is the CANONICAL set (cached +
  // currently announced). `_liveRoomIds` tracks which roomIds are
  // alive RIGHT NOW (in the relay snapshot). Rooms in `_roomsByPeer`
  // but not in `_liveRoomIds` are "offline" (last-seen state).
  final Map<String, List<RoomInfo>> _roomsByPeer = <String, List<RoomInfo>>{};
  final Map<String, Set<String>> _liveRoomIds = <String, Set<String>>{};
  final _roomsController =
      StreamController<Map<String, List<RoomInfo>>>.broadcast();
  bool _roomsRestored = false;
  ConnectionStatus _status = const StatusNoPeer();
  PeerRecord? _activePeer;
  // Plan 17 — active room on the destination Pi. 'main' is the implicit
  // default and matches the per-cwd room a Pi opens.
  String _activeRoomId = 'main';
  // Set when the user explicitly switches rooms during the current app
  // lifetime. Prevents legacy discovery hooks from clobbering that
  // explicit choice when room announcements/snapshots arrive later.
  bool _activeRoomExplicitlySet = false;

  Timer? _retryTimer;
  Timer? _pingTimer;
  // Plan-18 follow-up — watchdog timer that periodically checks for
  // "stuck offline" state (active peer set but status not online and
  // no retry / connect in flight). When detected, forces a fresh
  // _scheduleRetry. Belt-and-suspenders against any code path that
  // accidentally drops the retry chain.
  Timer? _watchdogTimer;
  CancelToken? _connectCancel;
  StreamSubscription<ServerMessage>? _channelSub;
  StreamSubscription<ControlInbound>? _controlSub;
  bool _disposed = false;
  final Map<String, int> _roomPersistenceRevision = <String, int>{};
  final Set<String> _roomPersistenceDraining = <String>{};
  Timer? _legacyRoomRetryTimer;
  final Duration _legacyRoomRetryDelay;
  // List currently subscribed for presence (so reconnect can replay it).
  List<String> _subscribedEpks = const [];
  final ReachabilityAdapter _reachability = ReachabilityAdapter();

  // Debounce timers — relay's control-frame firehose (peer_online +
  // presence + rooms snapshots, often dozens per second when multiple
  // devices reconnect) is filtered upstream by the dedup in
  // [_onControl], but legitimate changes still arrive in tight bursts
  // (e.g. cwd switch publishes a new RoomAnnounced + RoomsSnapshot
  // back-to-back). Coalesce those into a single emit per window so
  // downstream listeners (HomeViewModel → Flutter widget rebuilds)
  // see one update instead of three.
  Timer? _presenceEmitTimer;
  Timer? _roomsEmitTimer;
  final Duration _emitDebounce;

  ConnectionManager({
    required ConnectionFactory factory,
    required PairingStorage storage,
    DebugLog? debugLog,
    Duration emitDebounce = const Duration(milliseconds: 50),
    Duration legacyRoomRetryDelay = const Duration(milliseconds: 250),
    this.pingInterval = const Duration(seconds: 25),
  }) : _factory = factory,
       _storage = storage,
       _debugLog = debugLog,
       _emitDebounce = emitDebounce,
       _legacyRoomRetryDelay = legacyRoomRetryDelay {
    _startWatchdog();
  }

  /// Interval between Pi-liveness pings. Defaults to 25s in production;
  /// tests inject a short interval so the missed-ping →
  /// `_markActiveRoomOffline` path is exercisable without real-time waits.
  final Duration pingInterval;

  /// Plan-18 follow-up — periodically checks for stuck offline state
  /// and forces a reconnect attempt. Runs every 15s. Cheap; only
  /// fires the actual `_scheduleRetry` when the conditions match.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _runWatchdog();
    });
  }

  void _runWatchdog() {
    if (_disposed) return;
    final peer = _activePeer;
    if (peer == null) return;
    if (_status is StatusOnline) return;
    final status = _status;
    if (status is StatusOffline && !status.canRetry) return;
    if (_reachability.connectInFlight) return;
    if (_retryTimer != null) return;
    // We SHOULD be reconnecting but nothing's scheduled and no
    // attempt is in flight. Kick the retry chain.
    _scheduleRetry(peer);
  }

  @visibleForTesting
  void debugRunWatchdog() => _runWatchdog();

  /// Return the current connection lifecycle snapshot.
  ConnectionStatus get status => _status;

  /// Emit each connection lifecycle transition for reactive consumers.
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  /// Return the active peer channel only while the manager is online.
  IChannel? get channel =>
      _status is StatusOnline ? (_status as StatusOnline).channel : null;

  /// The peer this manager is currently driving (online, connecting, or
  /// retrying). Null when there is no active peer (NoPeer / Offline-noRetry
  /// / fresh after disconnect()).
  PeerRecord? get activePeer => _activePeer;

  // ---- Presence (plan 12) --------------------------------------------------

  /// Stream of full presence-map snapshots. Subscribers should treat each
  /// event as the canonical state for all keys present in the map.
  Stream<Map<String, PresenceState>> get presenceStream =>
      _presenceController.stream;

  /// Current presence for an epk (or [PresenceUnknown] if never observed).
  /// Accepts either url-safe (PairingStorage) or standard base64; the map
  /// itself is keyed in standard form (see [_onControl]).
  PresenceState presenceFor(String epk) =>
      _presence[toStandardB64(epk)] ?? const PresenceUnknown();

  /// Full snapshot copy of the current presence map. Keys are standard
  /// base64 — UI code that compares against `PeerRecord.remoteEpk`
  /// (url-safe) should also call [toStandardB64] before lookup. The Home
  /// tile / chat resolver do this via [presenceFor].
  Map<String, PresenceState> get presenceSnapshot =>
      Map.unmodifiable(_presence);

  // ---- Rooms (plan 17) -----------------------------------------------------

  /// Stream of full room-map snapshots. Each event is the canonical
  /// list of rooms per peer (standard-base64 keys).
  Stream<Map<String, List<RoomInfo>>> get roomsStream =>
      _roomsController.stream;

  /// Return an immutable snapshot of cached rooms keyed by standard-base64 EPK.
  Map<String, List<RoomInfo>> get roomsSnapshot => _roomsSnapshot();

  /// Rooms for a single peer (or empty list if none known yet). Accepts
  /// url-safe or standard base64.
  List<RoomInfo> roomsFor(String epk) =>
      List.unmodifiable(_roomsByPeer[toStandardB64(epk)] ?? const []);

  /// Active destination room (the Pi-side room id). 'main' = default.
  String get activeRoomId => _activeRoomId;

  /// Opaque Pi SDK session discriminator for the active `(peer, room)`.
  String? get activeSessionId {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return null;
    for (final room in roomsFor(epk)) {
      if (room.roomId == _activeRoomId) return room.sessionId;
    }
    return null;
  }

  /// Switch the destination room WITHOUT closing the current WS. The
  /// outer envelope's `room` field on subsequent sends will carry this
  /// value. Use when the user taps a different Pi cwd on Home.
  void switchRoom(String roomId) {
    if (roomId == _activeRoomId) {
      return;
    }
    _activeRoomId = roomId;
    _activeRoomExplicitlySet = true;
    // Push down to the underlying WS transport so outbound envelopes
    // get the right `room` value.
    final cur = _status;
    if (cur is StatusOnline) {
      _propagateActiveRoom(roomId, cur.channel);
    }
    // Re-emit the rooms snapshot so derived per-active-room state
    // (ActionsRepository.activeRoomMeta → the Quick Actions sheet's current
    // model/thinking) recomputes for the NEW room. Switching cwd-rooms on the
    // same Mac doesn't change status/rooms otherwise, so without this the
    // sheet kept showing the previous chat's model.
    if (!_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  void _propagateActiveRoom(String roomId, IChannel link) {
    if (link case IActiveRoomTarget target) {
      target.setActiveRoom(roomId);
    }
  }

  /// Subscribe (or re-subscribe) the relay to push presence AND room
  /// updates for [epks] (`peer_online` / `peer_offline` and
  /// `room_announced` / `room_ended` / `rooms` snapshot). Idempotent.
  /// Stored so the subscription is replayed automatically on
  /// reconnect via [_replaySubscriptions].
  ///
  /// Both subscriptions are sent together — historically this method
  /// only emitted `subscribe_presence`, which left a hole after the
  /// first pairing: `adopt()` runs before [_BootState] has had a
  /// chance to call this with the new peer, so `_subscribedEpks` is
  /// empty and `_replaySubscriptions` short-circuits. Home then
  /// subscribed (here) for presence only — never asking the relay to
  /// push rooms — and the first session tile only appeared after the
  /// next cold start (when boot() runs the full subscribe + connect
  /// path). Keeping presence/rooms in lockstep here closes that hole.
  ///
  /// IMPORTANT: every epk on the wire is base64 STANDARD — the relay's
  /// registry is keyed by what comes in `hello.pubkey` (always standard).
  /// Callers may pass url-safe (PairingStorage default) and we normalise
  /// once here. The internal cache (`_subscribedEpks`, `_presence` keys)
  /// is also kept in standard form so lookups don't have to coerce again.
  /// See `epk_encoding.dart` for the recurring-bug history.
  void subscribeToPeers(List<String> epks) {
    final standard = epks.map(toStandardB64).toList();
    _subscribedEpks = standard;
    final link = _controlLink;
    if (link == null) {
      return;
    }
    link.sendControl(subscribePresenceFrame(standard));
    link.sendControl(subscribeRoomsFrame(standard));
    if (standard.isNotEmpty) {
      link.sendControl(presenceCheckFrame(standard));
      link.sendControl(roomsCheckFrame(standard));
    }
  }

  /// One-shot snapshot request without changing the subscription.
  void refreshPresence([List<String>? epks]) {
    final link = _controlLink;
    if (link == null) return;
    final list = (epks ?? _subscribedEpks).map(toStandardB64).toList();
    if (list.isEmpty) return;
    link.sendControl(presenceCheckFrame(list));
  }

  /// Reconnect-time and resume-time hydration entrypoint for visible state.
  ///
  /// Replays subscriptions and requests both presence and room snapshots for
  /// every known peer currently bound in storage (or the existing
  /// `_subscribedEpks` cache when already available). This keeps the app
  /// converged after resume when status remained `StatusOnline` in cache.
  Future<void> requestResumeHydration() async {
    if (_status is! StatusOnline) return;
    if (_subscribedEpks.isEmpty) {
      final peers = await _storage.listPeers();
      if (peers.isEmpty) return;
      subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
      return;
    }
    _replaySubscriptions();
  }

  /// Current online channel cast to its control side, when supported.
  IControlLink? get _controlLink {
    final s = _status;
    if (s is! StatusOnline) return null;
    final ch = s.channel;
    return ch is IControlLink ? ch as IControlLink : null;
  }

  /// Open the WS and start driving a peer. Accepts an optional
  /// [preferredEpk] (plan 13) so the caller can express the user's
  /// authoritative choice — typically `Preferences.selectedPeerEpk`.
  /// When the preferred epk is not in storage (or omitted), falls back
  /// to `peers.first`.
  ///
  /// No-op when there is already an active peer (online, connecting, or
  /// retrying). In that case we still re-subscribe presence with the
  /// full peer list, since the storage may have changed.
  Future<void> boot({String? preferredEpk}) async {
    // Plan-17 follow-up — restore cached rooms from disk FIRST so
    // Home tiles render with last-known state even before the relay
    // pushes a fresh snapshot. Idempotent so reentrant boots are
    // harmless.
    await _restoreCachedRooms();
    if (_activePeer != null) {
      final peers = await _storage.listPeers();
      subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
      return;
    }
    if (_status is StatusOnline) return;
    final peers = await _storage.listPeers();
    if (peers.isEmpty) {
      _emit(const StatusNoPeer());
      return;
    }
    // IMPORTANT: route through `subscribeToPeers` so the epks land in
    // `_subscribedEpks` already normalised to standard base64. Direct
    // assignment used to leave url-safe values here, and the
    // `_replaySubscriptions` call inside `_connect` would then send
    // `subscribe_presence` with the wrong encoding — relay indexes its
    // PresenceManager by standard (from `hello.pubkey`), would not
    // match, and Home dots stayed cinza intermittently (race with
    // `HomeViewModel._load` which DOES normalise). The WS isn't online
    // yet here, so subscribeToPeers will just store + defer; the actual
    // frames go out via `_replaySubscriptions` once `_connect` succeeds.
    subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
    PeerRecord target;
    if (preferredEpk != null) {
      target = peers.firstWhere(
        (p) => p.remoteEpk == preferredEpk,
        orElse: () => peers.first,
      );
    } else {
      target = peers.first;
    }
    await _connect(target);
  }

  /// Connect to a specific paired peer, replacing any pending retry path.
  Future<void> connectTo(PeerRecord peer) => _connect(peer);

  /// Idempotent switch to another paired peer. If `peer` already matches
  /// [activePeer] AND we are Online, no-op. Otherwise tears down the
  /// current channel WITHOUT emitting a transient `StatusNoPeer` (plan
  /// 13) and starts a fresh connection — the visible transition becomes
  /// `Online → Connecting → Online`, never landing on NoPeer.
  Future<void> switchTo(PeerRecord peer) async {
    final fromEpk = _activePeer?.remoteEpk;
    if (fromEpk == peer.remoteEpk && _status is StatusOnline) {
      return;
    }
    await _teardownActive(emitNoPeer: false);
    await _connect(peer);
  }

  /// Adopt a channel created by an external flow such as pairing.
  ///
  /// Skips the factory because the channel is ready, binds its room before
  /// consuming frames, and takes over all retry, ping, and teardown ownership.
  //
  // Mirrors `_connect`'s room binding: `_activeRoomId` is set from
  // `peer.roomId` (which pairing always populates) and pushed down to the
  // channel before any inbound frame can be demuxed. Previously `adopt`
  // skipped both, so a post-pair envelope targeting the real room could be
  // dropped as `room-mismatch` by the transport's default `'main'` room —
  // see `story-fix-transport-active-room-reestablishment-on-reconnect`.
  void adopt(IChannel channel, PeerRecord peer) {
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _controlSub?.cancel();
    _controlSub = null;
    if (_status is StatusOnline) {
      _closeBestEffort((_status as StatusOnline).channel);
    }
    _reachability.onRelayConnectionEstablished();
    _activePeer = peer;
    _activeRoomExplicitlySet = false;
    final boundRoom = peer.roomId ?? 'main';
    if (boundRoom != _activeRoomId) {
      _activeRoomId = boundRoom;
    }
    // Push down to the underlying WS transport. Production transports are
    // constructed with the right room from `connect`, so this is a no-op
    // there; for channels adopted from external flows (pairing) it ensures
    // the room is correct even if the transport defaulted to `'main'`.
    _propagateActiveRoom(_activeRoomId, channel);
    _emit(StatusOnline(channel));
    _startPing(peer, channel);
    _watchChannel(peer, channel);
    _watchControl(channel);
    _replaySubscriptions();
  }

  /// Permanently close the active channel and return to the no-peer state.
  Future<void> disconnect() => _teardownActive(emitNoPeer: true);

  /// Shared implementation between [disconnect] and [switchTo]. When
  /// [emitNoPeer] is false (switch path), the `_status` is left as-is so
  /// a subsequent `_connect` can emit `StatusConnecting` directly,
  /// avoiding the visible Online → NoPeer → Connecting flicker that used
  /// to trip up `ChatViewModel._bootstrap`.
  Future<void> _teardownActive({required bool emitNoPeer}) async {
    _clearActiveRoomWorking();
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _controlSub?.cancel();
    _controlSub = null;
    if (_status is StatusOnline) {
      await (_status as StatusOnline).channel.close();
    }
    _reachability.onStopRequested();
    if (emitNoPeer) {
      _reachability.reset();
      _activePeer = null;
      _emit(const StatusNoPeer());
    }
    // When emitNoPeer is false, `_connect` will immediately overwrite
    // `_activePeer` and emit `StatusConnecting`, so we deliberately leave
    // the state alone here.
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearActiveRoomWorking();
    _cancelRetry();
    _cancelPing();
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _legacyRoomRetryTimer?.cancel();
    _legacyRoomRetryTimer = null;
    _presenceEmitTimer?.cancel();
    _presenceEmitTimer = null;
    _roomsEmitTimer?.cancel();
    _roomsEmitTimer = null;
    // Dispose must tear down the active connection too — without this the live
    // WebSocket channel and any in-flight connect attempt leak past disposal.
    // `_teardownActive` is async (awaits channel.close); dispose is sync, so we
    // mirror its cancellation paths and fire-and-forget the channel close.
    _connectCancel?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _controlSub?.cancel();
    _controlSub = null;
    final active = _status;
    if (active is StatusOnline) {
      _closeBestEffort(active.channel);
    }
    _reachability.onStopRequested();
    _statusController.close();
    _presenceController.close();
    if (!_roomsController.isClosed) {
      _roomsController.close();
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _connect(PeerRecord peer) async {
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _controlSub?.cancel();
    _controlSub = null;

    final token = CancelToken();
    _connectCancel = token;
    _reachability.onConnectRequested();
    final samePeer = _activePeer?.remoteEpk == peer.remoteEpk;
    if (samePeer) {
      // A retry captures the PeerRecord that originally opened the socket. It
      // may lag behind a later explicit room switch, so retain the live room
      // and its explicit-selection latch across same-peer reconnects.
      _activePeer = peer.copyWith(roomId: _activeRoomId);
    } else {
      _activePeer = peer;
      _activeRoomExplicitlySet = false;
      // Set the destination room from the persisted PeerRecord before emitting
      // StatusOnline so the first send targets the intended relay room.
      final boundRoom = peer.roomId ?? 'main';
      if (boundRoom != _activeRoomId) {
        _activeRoomId = boundRoom;
      }
    }
    _emit(const StatusConnecting());

    try {
      final ch = await _factory(peer, token);
      if (token.isCancelled) {
        await ch.close();
        return;
      }
      _reachability.onRelayConnectionEstablished();
      // Push down the active room to the channel. Production WsTransport is
      // now constructed with the correct room from `connect` (see
      // story-fix-transport-active-room-reestablishment-on-reconnect), so
      // this is a no-op there; it remains a safety path for channels adopted
      // from external flows and for runtime room switches (switchRoom /
      // _maybeAdoptLegacyRoom).
      _propagateActiveRoom(_activeRoomId, ch);
      _emit(StatusOnline(ch));
      _startPing(peer, ch);
      _watchChannel(peer, ch);
      _watchControl(ch);
      _replaySubscriptions();
    } on RelayNotConfiguredException {
      if (token.isCancelled) return;
      // Configuration cannot be healed by a network retry. Clear the
      // reachability in-flight flag so the watchdog cannot resurrect this
      // connection attempt, then expose the Settings recovery action.
      _reachability.onStopRequested();
      _cancelRetry();
      _emit(
        const StatusOffline(
          reason: kRelayNotConfiguredMessage,
          canRetry: false,
        ),
      );
    } catch (e) {
      if (!token.isCancelled) {
        _logLifecycleFailure(
          LifecycleOperation.retryConnect,
          e,
          peerTail: _peerTail(peer.remoteEpk),
          room: _activeRoomId,
          retryScheduled: true,
        );
        _scheduleRetry(peer);
      }
    }
  }

  void _watchControl(IChannel ch) {
    _controlSub?.cancel();
    if (ch is! IControlLink) {
      _controlSub = null;
      return;
    }
    _controlSub = (ch as IControlLink).controlFrames.listen(_onControl);
  }

  void _onControl(ControlInbound c) {
    // Relay-reported epks are base64 STANDARD (they came in from the
    // remote peer's `hello.pubkey`). Normalise once on insert so the map
    // is always keyed in the same canonical form regardless of what we
    // received on the wire — and so consumer-side lookups via
    // `presenceFor` (which coerces) round-trip.
    //
    // Dedup contract: relay re-pushes `peer_online`, `presence`, and
    // `rooms` aggressively (every reconnect of every device, every
    // pi-extension restart, periodically as keep-alive). Without
    // de-duplication every push fires `_presenceController` /
    // `_roomsController`, which propagates to `HomeViewModel`, which
    // rebuilds the whole list, which keeps the CPU busy and the
    // device hot. Each case below only flips its `*Dirty` flag if
    // the incoming payload actually changes our cached view.
    var presenceDirty = false;
    var roomsDirty = false;
    switch (c) {
      case PeerOnline(:final peer):
        final key = toStandardB64(peer);
        final prev = _presence[key];
        const next = PresenceOnline();
        if (!_presenceEquals(prev, next)) {
          _presence[key] = next;
          presenceDirty = true;
        }
      case PeerOffline(:final peer, :final sinceTs):
        final key = toStandardB64(peer);
        final prev = _presence[key];
        final next = PresenceOffline(sinceTs: sinceTs);
        if (!_presenceEquals(prev, next)) {
          _presence[key] = next;
          presenceDirty = true;
        }
      case PresenceSnapshot(:final states):
        for (final s in states) {
          final key = toStandardB64(s.peer);
          final prev = _presence[key];
          final next = s.online
              ? PresenceOnline(sinceTs: s.sinceTs)
              : PresenceOffline(sinceTs: s.sinceTs);
          if (!_presenceEquals(prev, next)) {
            _presence[key] = next;
            presenceDirty = true;
          }
        }
      case RoomAnnounced(
        :final peer,
        :final roomId,
        :final sessionId,
        :final name,
        :final cwd,
        :final startedAt,
        :final model,
        :final thinking,
        :final working,
      ):
        final key = toStandardB64(peer);
        final list = _roomsByPeer[key] ?? <RoomInfo>[];
        // Preserve any localName the user already set for this room
        // (long-press rename) — only the live metadata comes from the
        // wire, the rename is local-only.
        String? preservedName;
        // Plan/28 Wave D — also preserve a previously-learned thinking
        // level when the announce frame omits it. Relays that don't
        // flatten `meta.thinking` will keep `thinking == null` here;
        // the previously cached value (if any) survives until the
        // next genuine `room_meta_updated`.
        ThinkingLevel? preservedThinking;
        // Plan/32 — same preserve convention for `working`: a legacy
        // relay that omits it (null) keeps the cached value instead of
        // forcing the room back to idle.
        var preservedWorking = false;
        String? preservedSessionId;
        final existingIdx = list.indexWhere((r) => r.roomId == roomId);
        if (existingIdx >= 0) {
          preservedName = list[existingIdx].name;
          preservedSessionId = list[existingIdx].sessionId;
          preservedThinking = list[existingIdx].thinking;
          preservedWorking = list[existingIdx].working;
        }
        final next = RoomInfo(
          roomId: roomId,
          sessionId: sessionId ?? preservedSessionId,
          name: preservedName ?? name,
          cwd: cwd,
          startedAt: startedAt,
          model: model,
          thinking: thinking ?? preservedThinking,
          working: working ?? preservedWorking,
        );
        final liveAlready = _liveRoomIds[key]?.contains(roomId) ?? false;
        final identicalEntry = existingIdx >= 0 && list[existingIdx] == next;
        if (identicalEntry && liveAlready) {
          // No-op announce — relay re-broadcast. Skip to keep the UI
          // quiet.
          break;
        }
        list.removeWhere((r) => r.roomId == roomId);
        list.add(next);
        _roomsByPeer[key] = list;
        (_liveRoomIds[key] ??= <String>{}).add(roomId);
        _logRoomSnapshot(room: roomId, working: next.working);
        roomsDirty = true;
        // Persist the new view so cold restart shows the same tiles.
        _scheduleRoomPersistence(key);
        // Plan 17 fix — legacy discovery: if the active peer has no
        // persisted roomId yet (PeerRecord saved before this fix or
        // QR without `rm`), adopt the first room we learn about as
        // the canonical one. Persists the choice on the PeerRecord
        // so future reconnects address it directly.
        _maybeAdoptLegacyRoom(key, roomId);
      case RoomEnded(:final peer, :final roomId):
        final key = toStandardB64(peer);
        // Mark the room offline but KEEP it in the cached set so the
        // tile stays in Home (now grey). A room end is also terminal for
        // the room projection, so clear any cached working=true.
        final removed = _liveRoomIds[key]?.remove(roomId) ?? false;
        final list = _roomsByPeer[key];
        var clearedWorking = false;
        if (list != null) {
          final idx = list.indexWhere((r) => r.roomId == roomId);
          if (idx >= 0 && list[idx].working) {
            list[idx] = list[idx].copyWith(working: false);
            clearedWorking = true;
          }
        }
        if (_liveRoomIds[key]?.isEmpty ?? false) {
          _liveRoomIds.remove(key);
        }
        if (removed || clearedWorking) roomsDirty = true;
      case RoomMetaUpdated(
        :final peer,
        :final roomId,
        :final sessionId,
        :final model,
        :final thinking,
        :final working,
        :final hasModel,
        :final hasThinking,
        :final hasSessionId,
      ):
        final key = toStandardB64(peer);
        final list = _roomsByPeer[key];
        if (list == null) break;
        final idx = list.indexWhere((r) => r.roomId == roomId);
        if (idx < 0) break;
        final current = list[idx];
        // Plan/28 Wave D — meta is open-ended; only update the fields
        // the broadcast actually carried. `hasModel` / `hasThinking`
        // distinguishes "field was absent from the meta envelope"
        // (preserve previous value) from "field was explicitly null"
        // (overwrite with null). Without this, a thinking-only update
        // would clobber the previously cached model with null.
        final nextSessionId = hasSessionId ? sessionId : current.sessionId;
        final nextModel = hasModel ? model : current.model;
        final nextThinking = hasThinking ? thinking : current.thinking;
        // Plan/32 — `working` is nullable-as-absent: null preserves the
        // cached value (e.g. a model-only update must not flip the dot),
        // non-null sets it. This is what carries the relay's
        // turn_start/turn_end broadcast to the Home dot for EVERY room.
        final nextWorking = working ?? current.working;
        if (current.sessionId == nextSessionId &&
            current.model == nextModel &&
            current.thinking == nextThinking &&
            current.working == nextWorking) {
          break; // dedup: nothing actually changed
        }
        list[idx] = current.copyWith(
          sessionId: nextSessionId,
          model: nextModel,
          thinking: nextThinking,
          working: nextWorking,
        );
        _logRoomSnapshot(room: roomId, working: nextWorking);
        roomsDirty = true;
        _scheduleRoomPersistence(key);
      case RoomsSnapshot(:final peer, :final rooms):
        final key = toStandardB64(peer);
        // Merge snapshot into cache: add unknown rooms, refresh
        // metadata (preserving local rename + previous model when
        // the snapshot omits it), update live set.
        final existing = _roomsByPeer[key] ?? <RoomInfo>[];
        final byId = {for (final r in existing) r.roomId: r};
        for (final r in rooms) {
          final preservedName = byId[r.roomId]?.name ?? r.name;
          final preservedSessionId = r.sessionId ?? byId[r.roomId]?.sessionId;
          final preservedModel = r.model ?? byId[r.roomId]?.model;
          // Plan/28 Wave D — same convention as model: keep the
          // previously-known thinking when the snapshot omits it.
          final preservedThinking = r.thinking ?? byId[r.roomId]?.thinking;
          byId[r.roomId] = RoomInfo(
            roomId: r.roomId,
            sessionId: preservedSessionId,
            name: preservedName,
            cwd: r.cwd,
            startedAt: r.startedAt,
            model: preservedModel,
            thinking: preservedThinking,
            // Plan/32 — the snapshot is authoritative for live state:
            // `rooms_of` reads the current registry meta, so its
            // `working` reflects the latest turn_start/turn_end.
            working: r.working,
          );
        }
        final newLive = rooms.map((r) => r.roomId).toSet();
        for (final entry in byId.entries.toList()) {
          if (!newLive.contains(entry.key) && entry.value.working) {
            byId[entry.key] = entry.value.copyWith(working: false);
          }
        }
        final newList = byId.values.toList();
        final liveChanged = !_setEquals(
          newLive,
          _liveRoomIds[key] ?? const <String>{},
        );
        final listChanged = !_roomListEquals(newList, existing);
        if (!liveChanged && !listChanged) {
          // Relay re-emitted a snapshot identical to what we already
          // have. Skip — no listeners need to know.
          break;
        }
        _roomsByPeer[key] = newList;
        _liveRoomIds[key] = newLive;
        for (final room in rooms) {
          _logRoomSnapshot(
            room: room.roomId,
            presenceCount: rooms.length,
            working: room.working,
          );
        }
        roomsDirty = true;
        _scheduleRoomPersistence(key);
        // Same legacy-discovery hook as RoomAnnounced.
        if (rooms.isNotEmpty) {
          _maybeAdoptLegacyRoom(key, rooms.first.roomId);
        }
    }
    if (presenceDirty) _schedulePresenceEmit();
    if (roomsDirty) _scheduleRoomsEmit();
  }

  /// Coalesce presence emits within `_emitDebounce`. Each call resets
  /// the timer; the snapshot sent at fire time is whatever `_presence`
  /// looks like then (always the latest view).
  void _schedulePresenceEmit() {
    _presenceEmitTimer?.cancel();
    _presenceEmitTimer = Timer(_emitDebounce, () {
      _presenceEmitTimer = null;
      if (_presenceController.isClosed) return;
      _presenceController.add(Map.unmodifiable(_presence));
    });
  }

  /// Same shape as [_schedulePresenceEmit] but for the rooms stream.
  void _scheduleRoomsEmit() {
    _roomsEmitTimer?.cancel();
    _roomsEmitTimer = Timer(_emitDebounce, () {
      _roomsEmitTimer = null;
      if (_roomsController.isClosed) return;
      _roomsController.add(_roomsSnapshot());
    });
  }

  /// Value-equality helper for [PresenceState] — the sealed classes
  /// don't define their own `==`, and identity equality misfires
  /// because we construct fresh `PresenceOnline(...)` / `PresenceOffline(...)`
  /// objects on each control frame.
  bool _presenceEquals(PresenceState? a, PresenceState? b) {
    if (a == null) return b == null;
    if (b == null) return false;
    if (a.runtimeType != b.runtimeType) return false;
    if (a is PresenceOnline && b is PresenceOnline) {
      return a.sinceTs == b.sinceTs;
    }
    if (a is PresenceOffline && b is PresenceOffline) {
      return a.sinceTs == b.sinceTs;
    }
    // PresenceUnknown has no fields — same type ⇒ equal.
    return true;
  }

  /// `Set<String>` deep-equality (Dart sets don't have value-equality
  /// by default).
  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  /// `List<RoomInfo>` order-insensitive equality keyed by `roomId`.
  /// `RoomInfo` already defines value `==`.
  bool _roomListEquals(List<RoomInfo> a, List<RoomInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    final byIdB = {for (final r in b) r.roomId: r};
    for (final r in a) {
      if (byIdB[r.roomId] != r) return false;
    }
    return true;
  }

  Map<String, List<RoomInfo>> _roomsSnapshot() => Map.unmodifiable(
    _roomsByPeer.map((k, v) => MapEntry(k, List<RoomInfo>.unmodifiable(v))),
  );

  /// Returns `true` if `roomId` is currently announced live for the
  /// peer (the relay's last `room_announced` / `rooms` push included
  /// it). Cached rooms not in the live set return `false`. Used by
  /// the chat AppBar to render the online dot.
  ///
  /// Plan-18 follow-up: gated by `_status is StatusOnline`. When the
  /// WS to the relay drops (retrying / offline), we have no fresh
  /// signal that any room is reachable, so EVERY room is reported
  /// offline. The live set is invalidated at that transport boundary,
  /// keeping cached rooms stale after reconnect until a fresh relay
  /// snapshot confirms them. Home tiles + chat AppBar stay grey until
  /// that confirmation arrives.
  bool isRoomLive(String epk, String roomId) {
    if (_status is! StatusOnline) return false;
    final live = _liveRoomIds[toStandardB64(epk)];
    return live != null && live.contains(roomId);
  }

  /// Room-level turn projection. Cached room metadata is only trusted while
  /// the relay connection is online AND the room is present in the current live
  /// set. Unknown, ended, offline, or not-yet-hydrated rooms project stale and
  /// therefore `working:false`.
  RoomTurnProjection roomTurnProjection(String epk, String roomId) {
    if (_status is! StatusOnline) return RoomTurnProjection.stale;
    if (!isRoomLive(epk, roomId)) return RoomTurnProjection.stale;
    final list = _roomsByPeer[toStandardB64(epk)];
    if (list == null) return RoomTurnProjection.stale;
    for (final r in list) {
      if (r.roomId == roomId) {
        return r.working ? RoomTurnProjection.active : RoomTurnProjection.idle;
      }
    }
    return RoomTurnProjection.stale;
  }

  /// Compatibility getter for Home and staged callers.
  bool isRoomWorking(String epk, String roomId) =>
      roomTurnProjection(epk, roomId).working;

  /// App-side correction for the connected room's working projection.
  ///
  /// The relay remains the source for non-active rooms. This compatibility
  /// backstop is deliberately narrowed to the active, live room so local chat
  /// observations can clear a missed `meta.working=false` without mutating a
  /// different room's projection.
  void markRoomWorking(String epk, String roomId, bool working) {
    final active = _activePeer;
    if (active == null ||
        toStandardB64(active.remoteEpk) != toStandardB64(epk)) {
      return;
    }
    if (roomId != _activeRoomId) return;
    if (_status is! StatusOnline || !isRoomLive(epk, roomId)) {
      if (!working) {
        _logDebug(
          WorkingConvEvent(
            ts: DateTime.now(),
            room: roomId,
            working: false,
            reason: 'inactive_or_not_live',
          ),
        );
        _clearRoomWorking(epk, roomId);
      }
      return;
    }
    final key = toStandardB64(epk);
    final list = _roomsByPeer[key];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.roomId == roomId);
    if (idx < 0 || list[idx].working == working) return;
    list[idx] = list[idx].copyWith(working: working);
    _logDebug(
      WorkingConvEvent(
        ts: DateTime.now(),
        room: roomId,
        working: working,
        reason: 'mark_room_working',
      ),
    );
    _scheduleRoomsEmit();
    _scheduleRoomPersistence(key);
  }

  void _clearRoomWorking(String epk, String roomId) {
    final key = toStandardB64(epk);
    final list = _roomsByPeer[key];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.roomId == roomId);
    if (idx < 0 || !list[idx].working) return;
    list[idx] = list[idx].copyWith(working: false);
    _scheduleRoomsEmit();
    _scheduleRoomPersistence(key);
  }

  void _clearActiveRoomWorking() {
    final active = _activePeer;
    if (active == null) return;
    _clearRoomWorking(active.remoteEpk, _activeRoomId);
  }

  void _learnSessionFromPairOk(PeerRecord peer, PairOk msg) {
    final key = toStandardB64(peer.remoteEpk);
    final list = _roomsByPeer[key] ?? <RoomInfo>[];
    final idx = list.indexWhere((r) => r.roomId == msg.roomId);
    final current = idx >= 0 ? list[idx] : null;
    final next = RoomInfo(
      roomId: msg.roomId,
      sessionId: msg.sessionId.isEmpty ? current?.sessionId : msg.sessionId,
      name: current?.name ?? msg.sessionName,
      cwd: current?.cwd,
      startedAt: msg.sessionStartedAt == 0
          ? (current?.startedAt ?? DateTime.now().millisecondsSinceEpoch)
          : msg.sessionStartedAt,
      model: current?.model,
      thinking: current?.thinking,
      working: current?.working ?? false,
    );
    final liveAlready = _liveRoomIds[key]?.contains(msg.roomId) ?? false;
    if (current == next && liveAlready) return;
    if (idx >= 0) {
      list[idx] = next;
    } else {
      list.add(next);
    }
    _roomsByPeer[key] = list;
    (_liveRoomIds[key] ??= <String>{}).add(msg.roomId);
    _scheduleRoomPersistence(key);
    _maybeAdoptLegacyRoom(key, msg.roomId);
    _scheduleRoomsEmit();
  }

  /// Plan-17 follow-up — hydrate `_roomsByPeer` from disk on boot so
  /// Home tiles persist across cold starts even before the relay
  /// pushes a fresh snapshot. Idempotent.
  Future<void> _restoreCachedRooms() async {
    if (_roomsRestored) return;
    _roomsRestored = true;
    final peers = await _storage.listPeers();
    for (final p in peers) {
      final cached = await _storage.loadRooms(p.remoteEpk);
      if (cached.isEmpty) continue;
      final key = toStandardB64(p.remoteEpk);
      _roomsByPeer[key] = cached
          .map(
            (c) => RoomInfo(
              roomId: c.roomId,
              name: c.localName ?? c.name,
              cwd: c.cwd,
              startedAt: c.startedAt,
              model: c.model,
            ),
          )
          .toList();
      // Note: nothing in _liveRoomIds yet — those rooms are "offline"
      // until the relay announces them again.
    }
    if (!_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  void _scheduleRoomPersistence(String peerKey) {
    if (_disposed) return;
    _roomPersistenceRevision[peerKey] =
        (_roomPersistenceRevision[peerKey] ?? 0) + 1;
    _startRoomPersistenceDrain(peerKey);
  }

  void _startRoomPersistenceDrain(String peerKey) {
    if (_disposed || !_roomPersistenceDraining.add(peerKey)) return;
    unawaited(_drainRoomPersistence(peerKey));
  }

  Future<void> _drainRoomPersistence(String peerKey) async {
    var observedRevision = _roomPersistenceRevision[peerKey] ?? 0;
    try {
      while (!_disposed) {
        observedRevision = _roomPersistenceRevision[peerKey] ?? 0;
        try {
          await _persistLatestRoomSnapshot(peerKey, observedRevision);
        } on Object catch (error) {
          _logLifecycleFailure(
            LifecycleOperation.roomCachePersist,
            error,
            peerTail: _peerTail(peerKey),
          );
          break;
        }
        if (_disposed ||
            _roomPersistenceRevision[peerKey] == observedRevision) {
          break;
        }
      }
    } finally {
      _roomPersistenceDraining.remove(peerKey);
      // A mutation that arrived while the worker was failing/removing itself
      // is a new retry opportunity. Without this check that mutation could see
      // the old worker and be stranded until a third update.
      if (!_disposed &&
          (_roomPersistenceRevision[peerKey] ?? 0) != observedRevision) {
        _startRoomPersistenceDrain(peerKey);
      }
    }
  }

  Future<void> _persistLatestRoomSnapshot(String peerKey, int revision) async {
    final peers = await _storage.listPeers();
    if (_disposed || _roomPersistenceRevision[peerKey] != revision) return;

    PeerRecord? match;
    for (final peer in peers) {
      if (toStandardB64(peer.remoteEpk) == peerKey) {
        match = peer;
        break;
      }
    }
    if (match == null) return;

    // Read the current on-disk localNames so metadata refreshes do not drop a
    // user's local rename.
    final existing = await _storage.loadRooms(match.remoteEpk);
    if (_disposed || _roomPersistenceRevision[peerKey] != revision) return;
    final localById = {
      for (final room in existing)
        if (room.localName != null && room.localName!.isNotEmpty)
          room.roomId: room.localName!,
    };
    final rooms = _roomsByPeer[peerKey] ?? const <RoomInfo>[];
    final persisted = rooms
        .map(
          (room) => PersistedRoom(
            roomId: room.roomId,
            name: room.name,
            cwd: room.cwd,
            startedAt: room.startedAt,
            localName: localById[room.roomId],
            model: room.model,
          ),
        )
        .toList();
    if (_disposed || _roomPersistenceRevision[peerKey] != revision) return;
    await _storage.saveRooms(match.remoteEpk, persisted);
  }

  /// Plan-17 follow-up — long-press menu support. Override the
  /// display name of a single room locally (Pi never sees this).
  /// Reflects immediately in the rooms snapshot.
  Future<void> setRoomLocalName(String epk, String roomId, String? name) async {
    final key = toStandardB64(epk);
    final list = _roomsByPeer[key];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.roomId == roomId);
    if (idx < 0) return;
    final old = list[idx];
    // Use copyWith so EVERY field (model, cwd, startedAt, …) is
    // preserved. The previous explicit constructor call dropped
    // `model`, which made the tile subtitle fall back to
    // "Last Paired: …" right after a rename — bug.
    list[idx] = old.copyWith(
      name: (name != null && name.isNotEmpty) ? name : old.name,
    );
    // Persist with localName so it survives cold start.
    final cached = await _storage.loadRooms(epk);
    final updated = cached
        .map((c) => c.roomId == roomId ? c.copyWith(localName: name) : c)
        .toList();
    await _storage.saveRooms(epk, updated);
    if (!_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  /// Plan-17 follow-up — delete a cached room locally. Only safe when
  /// the room is offline (not live); UI gates this.
  Future<void> deleteCachedRoom(String epk, String roomId) async {
    final key = toStandardB64(epk);
    final list = _roomsByPeer[key];
    if (list != null) {
      list.removeWhere((r) => r.roomId == roomId);
      if (list.isEmpty) _roomsByPeer.remove(key);
    }
    final cached = await _storage.loadRooms(epk);
    final pruned = cached.where((c) => c.roomId != roomId).toList();
    await _storage.saveRooms(epk, pruned);
    if (!_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  /// Plan 17 fix — legacy migration hook for peers paired before
  /// `PeerRecord.roomId` existed. When the relay tells us about rooms
  /// for the active peer, and that peer has no persisted roomId yet,
  /// we adopt the announced room as canonical:
  ///   1. Update `_activeRoomId` so outbound envelopes are routed.
  ///   2. Push the change down to the WS transport.
  ///   3. Persist the choice on the PeerRecord via storage so
  ///      subsequent app launches address (peer, room) from the start
  ///      and don't re-trigger discovery.
  void _maybeAdoptLegacyRoom(String peerKey, String discoveredRoom) {
    final active = _activePeer;
    if (active == null) return;
    if (toStandardB64(active.remoteEpk) != peerKey) return;
    // If this peer already has a persisted/explicitly chosen room,
    // legacy-discovery must not override it.
    if (active.roomId != null || _activeRoomExplicitlySet) {
      return;
    }
    _activeRoomId = discoveredRoom;
    final cur = _status;
    if (cur is StatusOnline) {
      _propagateActiveRoom(discoveredRoom, cur.channel);
    }
    final updated = active.copyWith(roomId: discoveredRoom);
    _activePeer = updated;
    unawaited(_persistLegacyRoomWithRetry(updated));
  }

  Future<void> _persistLegacyRoomWithRetry(PeerRecord updated) async {
    try {
      await _storage.savePeer(updated);
    } on Object catch (error) {
      if (_disposed || !_isCurrentLegacyRoom(updated)) return;
      _logLifecycleFailure(
        LifecycleOperation.legacyRoomPersist,
        error,
        peerTail: _peerTail(updated.remoteEpk),
        room: updated.roomId,
        retryScheduled: true,
      );
      _legacyRoomRetryTimer?.cancel();
      _legacyRoomRetryTimer = Timer(_legacyRoomRetryDelay, () {
        _legacyRoomRetryTimer = null;
        if (_disposed || !_isCurrentLegacyRoom(updated)) return;
        unawaited(_retryLegacyRoomPersistence(updated));
      });
    }
  }

  Future<void> _retryLegacyRoomPersistence(PeerRecord updated) async {
    try {
      await _storage.savePeer(updated);
    } on Object catch (error) {
      if (_disposed || !_isCurrentLegacyRoom(updated)) return;
      _logLifecycleFailure(
        LifecycleOperation.legacyRoomPersist,
        error,
        peerTail: _peerTail(updated.remoteEpk),
        room: updated.roomId,
      );
    }
  }

  bool _isCurrentLegacyRoom(PeerRecord expected) {
    final current = _activePeer;
    return current != null &&
        current.remoteEpk == expected.remoteEpk &&
        current.roomId == expected.roomId;
  }

  /// On (re)connect, re-send the last subscribe_presence so the relay
  /// pushes updates again for our current peer list. Plan 17: also
  /// subscribe to rooms for the same peer set — the relay pushes
  /// `room_announced` / `room_ended` / `rooms` (snapshot) the same way
  /// presence does. Single subscription covers all per-cwd sessions on
  /// every paired Mac.
  void _replaySubscriptions() {
    if (_subscribedEpks.isEmpty) return;
    final link = _controlLink;
    if (link == null) return;
    _logDebug(
      ConnHydrateEvent(
        ts: DateTime.now(),
        action: 'replay_subscriptions',
        room: _activeRoomId,
        snapshotCount: _subscribedEpks.length,
      ),
    );
    link.sendControl(subscribePresenceFrame(_subscribedEpks));
    link.sendControl(presenceCheckFrame(_subscribedEpks));
    link.sendControl(subscribeRoomsFrame(_subscribedEpks));
    link.sendControl(roomsCheckFrame(_subscribedEpks));
  }

  void _watchChannel(PeerRecord peer, IChannel ch) {
    _channelSub?.cancel();
    _channelSub = ch.serverMessages.listen(
      (msg) {
        // Real inbound — the Pi is alive and reachable. Safe to reset
        // both the ping miss counter and the retry backoff.
        _reachability.onAppFrameObserved();
        if (msg is PairOk) {
          _learnSessionFromPairOk(peer, msg);
        }
      },
      onError: (_) => _onChannelLost(peer, ch),
      onDone: () => _onChannelLost(peer, ch),
    );
  }

  void _onChannelLost(PeerRecord peer, IChannel ch) {
    if (_status is! StatusOnline) return;
    final cur = (_status as StatusOnline).channel;
    if (!identical(cur, ch)) {
      // Stale: this onDone came from a channel we already replaced. The
      // relay typically kicks the previous WS when our retry authenticates
      // again — that close would otherwise trigger an immediate
      // self-sustaining retry loop.
      _logDebug(
        ConnChannelLostEvent(
          ts: DateTime.now(),
          peerTail: _peerTail(peer.remoteEpk),
          room: _activeRoomId,
          stale: true,
        ),
      );
      return;
    }
    _logDebug(
      ConnChannelLostEvent(
        ts: DateTime.now(),
        peerTail: _peerTail(peer.remoteEpk),
        room: _activeRoomId,
        stale: false,
      ),
    );
    _cancelPing();
    _reachability.onTransportClosed();
    _scheduleRetry(peer);
  }

  @visibleForTesting
  void debugSimulateChannelLost(IChannel ch) {
    final peer = _activePeer;
    if (peer == null) return;
    _onChannelLost(peer, ch);
  }

  void _scheduleRetry(PeerRecord peer) {
    if (_disposed) return;
    if (!_reachability.waitingForRetry) {
      _reachability.onConnectFailedRetryable();
    }
    final delay = _reachability.nextRetryDelay;
    final attempt = _reachability.retryAttempt;
    _emit(StatusRetrying(nextRetry: delay, attempt: attempt));
    // Cancel any previous timer before scheduling — prevents the
    // "two timers firing back-to-back" footgun.
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_disposed || _activePeer?.remoteEpk != peer.remoteEpk) return;
      _reachability.onRetryTimerFired();
      unawaited(_connectRetryOwned(peer));
    });
  }

  Future<void> _connectRetryOwned(PeerRecord peer) async {
    try {
      await _connect(peer);
    } on Object catch (error) {
      if (_disposed || _activePeer?.remoteEpk != peer.remoteEpk) return;
      _logLifecycleFailure(
        LifecycleOperation.retryConnect,
        error,
        peerTail: _peerTail(peer.remoteEpk),
        room: peer.roomId,
      );
    }
  }

  void _closeBestEffort(IChannel channel) {
    final peerTail = _peerTail(_activePeer?.remoteEpk);
    final room = _activeRoomId;
    unawaited(_closeOwned(channel, peerTail: peerTail, room: room));
  }

  Future<void> _closeOwned(
    IChannel channel, {
    String? peerTail,
    String? room,
  }) async {
    try {
      await channel.close();
    } on Object catch (error) {
      _logLifecycleFailure(
        LifecycleOperation.channelClose,
        error,
        peerTail: peerTail,
        room: room,
      );
    }
  }

  void _startPing(PeerRecord peer, IChannel ch) {
    _pingTimer = Timer.periodic(pingInterval, (_) async {
      if (_status is! StatusOnline) return;
      // Plan-18 follow-up — DECOUPLED Pi-liveness from WS-liveness.
      //
      // Before: 3 missed Pongs from the Pi triggered `_onChannelLost`,
      // which tore down the WS to the relay. The relay only frees
      // the slot when its own `sink.send` returns an error (which
      // can take MINUTES on certain network failures — half-open
      // TCP), so every reconnect attempt during that window hit
      // `room_already_open` and the app sat permanently offline.
      // [ORCH:19-heartbeat-investigate] reported this.
      //
      // After: the WS↔relay keep-alive is now exclusively handled
      // by RFC 6455 Ping/Pong (IOWebSocketChannel.pingInterval).
      // Protocol Ping/Pong here is a Pi-LIVENESS probe — when it
      // fails, we mark the active room as offline locally so Home /
      // chat reflect it; the WS stays online for presence updates
      // and other rooms. A real WS failure surfaces via the catch
      // below (ping SEND fails) or via the channel listener's
      // onError / onDone, both of which still trigger
      // `_onChannelLost`.
      _reachability.onPingMissed();
      if (_reachability.missedPings == 3) {
        _markActiveRoomOffline();
        // No `return` — keep firing pings. When Pi comes back, the
        // inbound Pong (or any other frame) resets missed pings via
        // _watchChannel, and `room_announced` repopulates
        // _liveRoomIds → tile + AppBar flip back to green
        // automatically.
      }
      try {
        final id = _newId();
        await ch.send(Ping(id: id));
      } catch (e) {
        _cancelPing();
        _onChannelLost(peer, ch);
      }
    });
  }

  /// Plan-18 follow-up — when the Pi stops responding to protocol
  /// Pings, mark its current cwd-room as offline locally so the UI
  /// reflects the degraded state. The WS↔relay stays up.
  void _markActiveRoomOffline() {
    final activeEpk = _activePeer?.remoteEpk;
    if (activeEpk == null) return;
    final key = toStandardB64(activeEpk);
    final live = _liveRoomIds[key];
    if (live == null || !live.contains(_activeRoomId)) return;
    live.remove(_activeRoomId);
    if (live.isEmpty) _liveRoomIds.remove(key);
    _logDebug(
      WorkingConvEvent(
        ts: DateTime.now(),
        room: _activeRoomId,
        working: false,
        reason: 'ping_missed_room_offline',
      ),
    );
    _clearRoomWorking(activeEpk, _activeRoomId);
    if (!_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _cancelPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _emit(ConnectionStatus s) {
    _logStatusTransition(s);
    // Plan-18 follow-up — when the connection-status flips ON or OFF
    // StatusOnline, every room's "live" answer changes too (see
    // `isRoomLive` gate). Re-emit the rooms snapshot so subscribers
    // (Home, Chat AppBar) re-evaluate dot color immediately, without
    // waiting for the relay's next push.
    final wasOnline = _status is StatusOnline;
    final nowOnline = s is StatusOnline;
    _status = s;
    if (wasOnline && !nowOnline) {
      // Room reachability belongs to the transport generation that observed
      // it. Retaining this set across reconnect would make the new relay
      // channel look like proof that the Pi room is online before its first
      // authoritative rooms snapshot arrives.
      _liveRoomIds.clear();
      _clearActiveRoomWorking();
    }
    if (!_statusController.isClosed) _statusController.add(s);
    if (wasOnline != nowOnline && !_roomsController.isClosed) {
      _roomsController.add(_roomsSnapshot());
    }
  }

  void _logStatusTransition(ConnectionStatus s) {
    switch (s) {
      case StatusConnecting():
        _logDebug(
          ConnStatusEvent(
            ts: DateTime.now(),
            status: 'connecting',
            peerTail: _peerTail(_activePeer?.remoteEpk),
            room: _activeRoomId,
          ),
        );
      case StatusOnline():
        _logDebug(
          ConnStatusEvent(
            ts: DateTime.now(),
            status: 'online',
            peerTail: _peerTail(_activePeer?.remoteEpk),
            room: _activeRoomId,
          ),
        );
      case StatusRetrying(:final nextRetry, :final attempt):
        _logDebug(
          ConnStatusEvent(
            ts: DateTime.now(),
            status: 'retrying',
            attempt: attempt,
            delayMs: nextRetry.inMilliseconds,
            peerTail: _peerTail(_activePeer?.remoteEpk),
            room: _activeRoomId,
          ),
        );
      case StatusNoPeer():
      case StatusOffline():
        break;
    }
  }

  void _logRoomSnapshot({
    required String room,
    int? presenceCount,
    bool? working,
  }) {
    _logDebug(
      RoomSnapshotEvent(
        ts: DateTime.now(),
        room: room,
        presenceCount: presenceCount,
        working: working,
      ),
    );
  }

  void _logDebug(DebugEvent event) => _debugLog?.log(event);

  void _logLifecycleFailure(
    LifecycleOperation operation,
    Object error, {
    String? peerTail,
    String? room,
    bool retryScheduled = false,
  }) {
    final type = error.runtimeType.toString();
    _logDebug(
      LifecycleFailureEvent(
        ts: DateTime.now(),
        operation: operation,
        reason: type.isEmpty ? 'unknown_error' : type,
        peerTail: peerTail,
        room: room,
        retryScheduled: retryScheduled,
      ),
    );
  }

  static String? _peerTail(String? epk) {
    if (epk == null || epk.isEmpty) return null;
    return epk.length <= 8 ? epk : epk.substring(epk.length - 8);
  }

  static int _idCounter = 0;
  static String _newId() => 'ping_${++_idCounter}';
}
