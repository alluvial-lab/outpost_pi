// SyncService is the single app-side transcript writer.
//
// Consumes the channel (ConnectionManager status + PeerChannel serverMessages),
// appends canonical TranscriptEvent records, and materializes the disposable
// row-granular `msgs` Hive projection read by repositories/UI. The `msgs` box
// is not transcript truth and can be rebuilt from the event store.
//
// Streaming remains in-memory for UI responsiveness; AgentChunk deltas are
// also event-store inputs, and finalized/projection rows are derived from the
// stored event log.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/sync/session_history_replay.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/session_gate.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/foundation.dart';

/// A cancellable scheduled callback used for pending-send expiry.
abstract interface class PendingSendTimer {
  /// Prevent the callback from running if it has not fired.
  void cancel();
}

/// Schedule a pending-send expiry callback.
typedef PendingSendTimerFactory =
    PendingSendTimer Function(Duration delay, void Function() callback);

final class _SystemPendingSendTimer implements PendingSendTimer {
  _SystemPendingSendTimer(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

final class _IdentityPendingSend {
  _IdentityPendingSend({
    required this.id,
    required this.peerEpk,
    required this.roomId,
    required this.text,
    required this.image,
    required this.streamingBehavior,
    required this.ts,
  });

  final String id;
  final String? peerEpk;
  final String roomId;
  final String text;
  final MessageImage? image;
  final UserMessageStreamingBehavior? streamingBehavior;
  final DateTime ts;
  UserMsgStatus status = UserMsgStatus.pending;

  UserMsg toMessage() =>
      UserMsg(id: id, text: text, status: status, image: image);
}

/// Own the app-side transcript write pipeline and active-turn convergence.
///
/// Serializes canonical event persistence, materializes disposable Hive
/// projections, subscribes to the active channel, and tears down timers and
/// streams on disposal. UI reads its snapshots rather than mutating storage.
class SyncService extends Service {
  final ConnectionManager _conn;
  final LocalBoxes _boxes;
  final TranscriptEventStore _eventStore;
  final DebugLog? _debugLog;
  final Future<void> Function(String key, Map<String, dynamic> value)?
  _runtimeRecordWriter;
  final SessionGate _sessionGate = const SessionGate();

  StreamSubscription<ConnectionStatus>? _connSub;
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;

  // Active session being written (follows ConnectionManager). Persistence is
  // bound to [_activeRef]; [_activeEpk]/[_activeRoomId] remain available for
  // room-scoped reachability/runtime while the canonical session id is unknown.
  String? _activeEpk;
  String _activeRoomId = 'main';
  RemoteSessionRef? _activeRef;

  // Highest `session_started_at` ever accepted for this active session.
  // Any incoming SessionHistory with a lower value is stale and rejected.
  int? _acceptedSessionStartedAtHighWater;

  // In-memory dedupe + ordering for the active session's msgs box. Rebuilt on
  // [activate]. Key = `<role>:<id>` so a user msg and the assistant reply that
  // shares its id don't collide.
  final Map<String, int> _idToSeq = {};
  int _nextSeq = 0;
  bool _indexLoaded = false;

  // Serialise box mutations so concurrent async writes stay ordered.
  Future<void> _writeChain = Future<void>.value();
  Future<void> _lifecycleChain = Future<void>.value();
  bool _disposed = false;
  int _lifecycleGeneration = 0;
  int _turnProjectionEpoch = 0;
  RemoteSessionRef? _persistenceDegradedRef;

  // Streaming — in-memory only (#7).
  final StringBuffer _chunkBuffer = StringBuffer();
  Timer? _flushTimer;
  StreamingMessage? _streaming;
  // Identity-source (a): tracks whether a deterministic `agent_message`
  // (carrying SDK `ts`, from the extension's `message_end`) has committed
  // the final assistant text for the current turn. When true, the
  // `AgentDone` buffer-commit is skipped (it would duplicate the
  // `agent_message` commit under a random eventId). Reset on turn start /
  // streaming clear. See
  // story-mobile-assistant-message-duplicated-live-replay decision 1.
  bool _agentMessageCommittedThisTurn = false;

  // Sticky capability flag: latched `true` the first time a live
  // `AgentMessage` carrying `ts != null` arrives (the fixed extension's
  // `message_end`-driven broadcast). Once observed, the extension is known
  // to emit deterministic `agent_message(ts)` frames for every assistant
  // turn, so a missing commit at `ToolRequest`/`AgentDone` time means the
  // frame was DROPPED mid-flap (relay suspend for an offline peer), not that
  // the extension is a legacy version that never sends one. In that case the
  // random-uuid fallback must be SUPPRESSED — committing it would produce a
  // row the reconnect `session_sync` replay cannot collapse (random id vs.
  // deterministic id → two rows → visible dupe). The replay alone fills the
  // transcript deterministically on reconnect. See
  // story-mobile-connection-flapping-drops-identity-frames Layer 2.
  bool _extensionSendsDeterministicAgentMessage = false;
  final StreamController<StreamingMessage?> _streamingController =
      StreamController<StreamingMessage?>.broadcast();

  final StreamController<SessionEvent> _eventController =
      StreamController<SessionEvent>.broadcast();

  String? _queuedText;
  final StreamController<String?> _queuedController =
      StreamController<String?>.broadcast();

  SteeringProjection _transcriptSteering = const NoSteering();
  final StreamController<SteeringProjection> _steeringController =
      StreamController<SteeringProjection>.broadcast();

  bool _pendingSyncRequest = false;
  Timer? _syncDebounce;

  // Active-room turn projection derived from transcript events and local
  // optimistic send state. This is the single in-memory source for chat
  // working/cancel state; legacy boolean getters below derive from it.
  TranscriptTurnView _turnView = TranscriptTurnView.idle;
  final StreamController<TranscriptTurnView> _turnViewController =
      StreamController<TranscriptTurnView>.broadcast();

  // Plan/32 safety net — if the relay never echoes a sent message back, the
  // optimistic `pending:true` bubble would spin forever. After this window we
  // replace the bubble with a visible failure row. The real delivery fix lives
  // in the relay/Pi path; this is the app-side backstop. Per-message (`id`)
  // timers are cancelled on echo, user-cancel, session switch, and dispose.
  final Duration deliveryPendingEchoTimeout;
  final Duration pendingSendTimeout;
  final PendingSendTimerFactory _pendingSendTimerFactory;
  final Map<String, PendingSendTimer> _pendingSendTimers = {};

  // A user can submit after room hydration but before the canonical session id
  // arrives. These rows remain in-memory and visible until they can migrate to
  // the session-scoped transcript; their own timers prevent an endless spinner.
  final Map<String, _IdentityPendingSend> _identityPendingSends = {};
  final Map<String, PendingSendTimer> _identityPendingTimers = {};
  final StreamController<List<ChatMessage>> _identityPendingController =
      StreamController<List<ChatMessage>>.broadcast();

  /// Ids of held-pending messages already re-sent on reconnect this session
  /// (story-app-reattempt-held-pending-on-reconnect). Prevents the
  /// self-retrigger loop: the re-send's own `working:true` room_meta update
  /// re-fires `_onRoomsChanged`, but each id is re-sent at most once per
  /// session. Cleared on session switch (the `_activeRef` change path).
  ///
  /// NOTE: the self-retrigger is now harmless (the Pi-side ingress idempotency
  /// guard re-echoes without re-waking on a duplicate), so this guard's only
  /// value is avoiding redundant traffic. It is an in-flight set (cleared on
  /// send failure) rather than a permanent block, so a failed re-send can be
  /// retried on a later healthy reconnect — not permanently suppressed.
  final Set<String> _resentHeldPendingIds = {};

  SyncService(
    this._conn,
    this._boxes, {
    TranscriptEventStore? transcriptEventStore,
    DebugLog? debugLog,
    Future<void> Function(String key, Map<String, dynamic> value)?
    runtimeRecordWriter,
    this.pendingSendTimeout = const Duration(seconds: 20),
    this.deliveryPendingEchoTimeout = const Duration(seconds: 60),
    PendingSendTimerFactory? pendingSendTimerFactory,
  }) : _eventStore = transcriptEventStore ?? HiveTranscriptEventStore(_boxes),
       _debugLog = debugLog,
       _runtimeRecordWriter = runtimeRecordWriter,
       _pendingSendTimerFactory =
           pendingSendTimerFactory ?? _SystemPendingSendTimer.new {
    _connSub = _conn.statusStream.listen(_onStatus);
    _roomsSub = _conn.roomsStream.listen((_) {
      _writeRuntime();
      _scheduleLifecycleOperation(
        LifecycleOperation.sessionRebind,
        _handleRoomsChanged,
      );
    });
    _presenceSub = _conn.presenceStream.listen((_) => _writeRuntime());
    _onStatus(_conn.status); // replay current
  }

  // ---------------------------------------------------------------------------
  // Public surface (commands + in-memory streams)
  // ---------------------------------------------------------------------------

  /// Return the current in-memory assistant stream, if a turn is producing text.
  StreamingMessage? get streaming => _streaming;

  /// Emit transient assistant stream snapshots; durable history comes from Hive.
  Stream<StreamingMessage?> get streamingStream => _streamingController.stream;

  /// Emit non-transcript session control events for ViewModel coordination.
  Stream<SessionEvent> get events => _eventController.stream;

  /// Return composer text queued by the active Pi session, if any.
  String? get queuedText => _queuedText;

  /// Emit queued-composer state from local commands and Pi updates.
  Stream<String?> get queuedStream => _queuedController.stream;

  /// Return transcript-derived steering acceptance/pickup state.
  SteeringProjection get steeringProjection => _transcriptSteering;

  /// Emit steering state as transcript acceptance and pickup events converge.
  Stream<SteeringProjection> get steeringProjectionStream =>
      _steeringController.stream;

  /// Return the canonical in-memory turn state for the active session.
  TranscriptTurnView get turnView => _turnView;

  /// Emit canonical turn snapshots as transcript and control events converge.
  Stream<TranscriptTurnView> get turnViewStream => _turnViewController.stream;

  /// Project the active turn into compatibility UI state without duplicate flags.
  AppTurnProjection get turnProjection => _turnView.toAppProjection();

  /// Emit compatibility UI projections derived from canonical turn snapshots.
  Stream<AppTurnProjection> get turnProjectionStream =>
      _turnViewController.stream.map((turn) => turn.toAppProjection());

  /// Compatibility getters. They are derived from [_turnView], never written as
  /// independent mutable booleans/ids.
  bool get isWorking => turnProjection.working;
  Stream<bool> get workingStream =>
      turnProjectionStream.map((projection) => projection.working).distinct();

  /// `cancel` target for the in-flight reply (null when idle).
  String? get workingReplyTo => turnProjection.cancelTargetId;

  /// Return the active peer identity while a room is bound, if known.
  String? get activeEpk => _activeEpk;

  /// Return the active Pi room, defaulting to `main` before metadata arrives.
  String get activeRoomId => _activeRoomId;

  /// Return the fully canonical active session required for transcript writes.
  RemoteSessionRef? get activeSessionRef => _activeRef;

  /// Return identity-blocked submissions visible for the active peer and room.
  List<ChatMessage> get identityPendingMessages =>
      List<ChatMessage>.unmodifiable(_visibleIdentityPendingMessages());

  /// Emit identity-blocked submissions as they become pending, failed, or bound.
  Stream<List<ChatMessage>> get identityPendingMessagesStream =>
      _identityPendingController.stream;

  RemoteSessionRef? _resolveActiveRef(String epk, String roomId) {
    final activePeer = _conn.activePeer;
    if (activePeer == null || activePeer.remoteEpk != epk) return null;
    if (_conn.activeRoomId != roomId) return null;
    final sessionId = _conn.activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return null;
    return RemoteSessionRef(peerEpk: epk, roomId: roomId, sessionId: sessionId);
  }

  bool _isStillActive(RemoteSessionRef ref) => !_disposed && _activeRef == ref;

  /// Bind the writer to a canonical remote session. The `(peer, room)` pair
  /// may be known before the Pi reports a `session_id`; in that state runtime
  /// reachability can still update, but transcript persistence waits for the
  /// full [RemoteSessionRef].
  Future<void> activate(String epk, String roomId) async {
    if (_disposed) return;
    final room = roomId.isEmpty ? 'main' : roomId;
    final nextRef = _resolveActiveRef(epk, room);
    final sameRoom = _activeEpk == epk && _activeRoomId == room;
    final sameRef = _activeRef == nextRef;
    if (sameRoom && sameRef && _indexLoaded) {
      _logDebug(
        RouteEvent(
          ts: DateTime.now(),
          room: room,
          phase: RoutePhase.entry,
          sessionIdTail: _sessionIdTail(nextRef?.sessionId),
        ),
      );
      return;
    }

    final generation = ++_lifecycleGeneration;
    await _activateForGeneration(epk, room, nextRef, generation);
  }

  Future<void> _activateForGeneration(
    String epk,
    String room,
    RemoteSessionRef? nextRef,
    int generation,
  ) async {
    if (!_isCurrentLifecycle(generation)) return;
    final previousRef = _activeRef;

    // Genuine session switch or session-id rotation: drop in-memory turn state
    // and projection buffers so the previous canonical transcript cannot bleed
    // into the newly active session-scoped box. We deliberately do NOT clear
    // the previous durable session index — the prior Pi session may still be
    // visible via room-level relay metadata.
    _resetTurnState(clearPendingSendTimers: true);
    _acceptedSessionStartedAtHighWater = null;
    _activeEpk = epk;
    _activeRoomId = room;
    _activeRef = nextRef;
    _logDebug(
      RouteEvent(
        ts: DateTime.now(),
        room: room,
        phase: RoutePhase.entry,
        sessionIdTail: _sessionIdTail(nextRef?.sessionId),
      ),
    );
    if (previousRef != nextRef) _clearPersistenceDegradationForReplacement();
    // Capability is per-active-session, not process-global: a prior peer that
    // sent deterministic agent_message(ts) must not cause a later legacy
    // peer's AgentDone/ToolRequest fallback to be suppressed.
    _extensionSendsDeterministicAgentMessage = false;
    _indexLoaded = false;
    _idToSeq.clear();
    _nextSeq = 0;

    if (nextRef != null) {
      await _loadIndex(nextRef, generation);
      if (!_isCurrentLifecycle(generation, nextRef)) return;
      await _materializeTranscriptProjectionForRef(nextRef, generation);
      if (!_isCurrentLifecycle(generation, nextRef)) return;
      await _bindIdentityPendingSends(nextRef, generation);
      if (!_isCurrentLifecycle(generation, nextRef)) return;
      await _resendHeldPendingMessages(generation, nextRef);
      if (!_isCurrentLifecycle(generation, nextRef)) return;
    }
    _emitIdentityPendingMessages();
    _writeRuntime();
  }

  /// Clears the in-memory streaming buffer + whole-turn working flag
  /// (emitting the cleared state so listeners update) WITHOUT touching the
  /// durable session index. Used on a session switch — see [activate].
  void _resetTurnState({bool clearPendingSendTimers = false}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    _chunkBuffer.clear();
    _agentMessageCommittedThisTurn = false;
    _setQueuedText(null);
    _setTranscriptSteering(const NoSteering());
    if (clearPendingSendTimers) {
      // Session switch: the previous chat's in-flight sends are no longer ours
      // to confirm — drop their backstops so a stale timer can't fire later.
      _cancelAllSendTimers();
    }
    if (_streaming != null) _emitStreaming(null);
    _setTurnViewLocalOnly(TranscriptTurnView.idle);
  }

  /// Append an optimistic user event and send it when the active room is live.
  ///
  /// Offline or stale-room sends remain held pending for reconnect retry and
  /// eventually become visible failures; the method never sends without a
  /// canonical session identity.
  Future<void> sendMessage(
    String text, {
    MessageImage? image,
    UserMessageStreamingBehavior? streamingBehavior,
  }) async {
    final generation = _lifecycleGeneration;
    final ref = _activeRef;
    final epk = _activeEpk;
    final id = _newId();
    final now = DateTime.now();
    final isSteer = streamingBehavior == UserMessageStreamingBehavior.steer;
    final sessionId = ref?.sessionId;
    if (ref == null || sessionId == null || sessionId.isEmpty) {
      _queueIdentityPendingSend(
        _IdentityPendingSend(
          id: id,
          peerEpk: epk,
          roomId: _activeRoomId,
          text: text,
          image: image,
          streamingBehavior: streamingBehavior,
          ts: now,
        ),
      );
      debugPrint(
        '[msg-send] id=$id blocked: session identity unavailable; held pending',
      );
      _logDebug(MsgSendEvent(ts: now, id: id, blocked: true));
      _logDebug(SendQueueEvent(ts: now, id: id, phase: SendQueuePhase.held));
      return;
    }
    // Compute whether this send will be held pending (never written to the
    // channel) because the connection is offline or the active room is not
    // live. Recorded on the UserMessageSubmitted event so the reconnect
    // re-send path (story-app-reattempt-held-pending-on-reconnect) knows
    // which failed/pending rows to re-send. Messages that WERE written to
    // the channel are left to the late-confirmation path (SessionHistory
    // replay) if they time out.
    final initialChannel = _conn.channel;
    final activeEpk = _activeEpk;
    final held =
        initialChannel == null ||
        (activeEpk != null && !_conn.isRoomLive(activeEpk, _activeRoomId));
    // Optimistic pending row (#defaults: optimistic + dedupe by id).
    if (epk != null) {
      await _appendTranscriptEvent(
        UserMessageSubmitted(
          eventId: 'local:user_submitted:$id',
          sessionId: ref.sessionId,
          ts: now,
          clientMessageId: id,
          text: text,
          image: image,
          held: held,
          awaitingPickup: isSteer,
        ),
        preserveTurnState: isSteer,
      );
      if (!_isCurrentLifecycle(generation, ref) ||
          !identical(_conn.channel, initialChannel) ||
          (!held && !_conn.isRoomLive(ref.peerEpk, ref.roomId))) {
        return;
      }
      if (!isSteer) {
        _setTurnActive(
          status: AppTurnStatus.working,
          preview: _preview(text, image),
          replyTo: id,
        );
      }
      // Arm the no-echo backstop for this row. The timeout is keyed off the
      // row's `ts`, NOT online-ness: an offline "held pending" send fails
      // visibly after its ts too, and ANY pending row is re-armed on session
      // load (see _loadIndex). So a quick session-switch or an app restart
      // still fails a stale bubble instead of letting it spin "sending…"
      // forever.
      _armSendTimeout(id, now);
    }
    if (held) {
      debugPrint(
        '[msg-send] id=$id (held pending — offline or room not live; fails in '
        '${pendingSendTimeout.inSeconds}s, re-sent on reconnect)',
      );
      _logDebug(MsgSendEvent(ts: DateTime.now(), id: id, blocked: true));
      _logDebug(
        SendQueueEvent(ts: DateTime.now(), id: id, phase: SendQueuePhase.held),
      );
      return;
    }
    // Half-open socket guard (story-app-half-open-socket-swallows-sends-
    // arrives-late): the WS may be StatusOnline while the active room has
    // been proven unreachable (3 missed protocol pongs →
    // `_markActiveRoomOffline` removed it from `_liveRoomIds`, or a
    // `RoomEnded` push). Sending into that socket writes bytes that won't
    // reach the Pi until a reconnect flushes them — minutes late, after the
    // 20s echo timeout has already marked the row failed. Gate on room
    // liveness, not just WS StatusOnline: if the room isn't live, hold the
    // message pending exactly like the offline branch so it fails visibly
    // (or re-attempts on the next healthy connection) instead of vanishing
    // into a dead send buffer.
    final sendChannel = _conn.channel;
    if (!_isCurrentLifecycle(generation, ref) ||
        sendChannel == null ||
        !identical(sendChannel, initialChannel) ||
        _activeEpk != ref.peerEpk ||
        _activeRoomId != ref.roomId ||
        !_conn.isRoomLive(ref.peerEpk, ref.roomId)) {
      return;
    }
    // Seed an EMPTY streaming buffer so the blinking cursor shows during the
    // "thinking" gap before the first agent_chunk (pre-31 behavior). In-memory
    // only (#7) — never written to the DB. agent_chunk appends; agent_done
    // clears it (even for a text-less, tool-only turn).
    // Steering messages should not create a new cursor, because they do not
    // start a fresh assistant turn.
    if (!isSteer) {
      _emitStreaming(StreamingMessage(inReplyTo: id));
    }
    debugPrint('[msg-send] id=$id');
    _logDebug(MsgSendEvent(ts: DateTime.now(), id: id, blocked: false));
    try {
      await sendChannel.send(
        UserMessage(
          id: id,
          sessionId: sessionId,
          text: text,
          streamingBehavior: streamingBehavior,
          images: image == null
              ? null
              : [WireImage(data: image.data, mime: image.mime)],
        ),
      );
    } catch (_) {
      await _failPendingSend(
        id,
        code: 'send_error',
        message:
            'Message could not be sent to the Pi. Check the connection and try again.',
        expectedRef: ref,
        expectedGeneration: generation,
      );
    }
  }

  void _queueIdentityPendingSend(_IdentityPendingSend send) {
    _identityPendingSends[send.id] = send;
    _identityPendingTimers.remove(send.id)?.cancel();
    _identityPendingTimers[send.id] = _pendingSendTimerFactory(
      pendingSendTimeout,
      () => _onIdentityPendingTimeout(send.id),
    );
    _emitIdentityPendingMessages();
  }

  void _onIdentityPendingTimeout(String id) {
    final send = _identityPendingSends[id];
    if (_disposed || send == null || send.status != UserMsgStatus.pending) {
      return;
    }
    _identityPendingTimers.remove(id)?.cancel();
    send.status = UserMsgStatus.failed;
    _emitIdentityPendingMessages();
    debugPrint('[msg-failed] id=$id code=send_timeout');
    _logDebug(MsgFailedEvent(ts: DateTime.now(), id: id, code: 'send_timeout'));
    _logDebug(
      SendQueueEvent(
        ts: DateTime.now(),
        id: id,
        phase: SendQueuePhase.visibleFail,
        code: 'send_timeout',
      ),
    );
  }

  Iterable<ChatMessage> _visibleIdentityPendingMessages() sync* {
    for (final send in _identityPendingSends.values) {
      if (send.roomId != _activeRoomId) continue;
      final activeEpk = _activeEpk;
      if (send.peerEpk != null && send.peerEpk != activeEpk) continue;
      yield send.toMessage();
    }
  }

  void _emitIdentityPendingMessages() {
    if (_identityPendingController.isClosed) return;
    _identityPendingController.add(identityPendingMessages);
  }

  Future<void> _bindIdentityPendingSends(
    RemoteSessionRef ref,
    int generation,
  ) async {
    final matching = _identityPendingSends.values
        .where(
          (send) =>
              send.roomId == ref.roomId &&
              (send.peerEpk == null || send.peerEpk == ref.peerEpk),
        )
        .toList(growable: false);
    if (matching.isEmpty) return;

    final events = <TranscriptEvent>[];
    for (final send in matching) {
      events.add(
        UserMessageSubmitted(
          eventId: 'local:user_submitted:${send.id}',
          sessionId: ref.sessionId,
          ts: send.ts,
          clientMessageId: send.id,
          text: send.text,
          image: send.image,
          held: true,
          awaitingPickup:
              send.streamingBehavior == UserMessageStreamingBehavior.steer,
        ),
      );
      if (send.status == UserMsgStatus.failed) {
        events.add(
          UserMessageFailed(
            eventId: 'local:user_failed:${send.id}:identity_timeout',
            sessionId: ref.sessionId,
            ts: DateTime.now(),
            clientMessageId: send.id,
            code: 'send_timeout',
            message:
                'Message waited for the session to reconnect and was not yet confirmed.',
          ),
        );
      }
    }
    await _appendTranscriptEvents(events);
    if (!_isCurrentLifecycle(generation, ref)) return;
    for (final send in matching) {
      _identityPendingSends.remove(send.id);
      _identityPendingTimers.remove(send.id)?.cancel();
    }
    _emitIdentityPendingMessages();
  }

  /// Arm (or re-arm) the no-echo backstop for a pending row, keyed by
  /// `id`. The window is the time REMAINING relative to the row's [ts], so a
  /// row loaded from disk already past [pendingSendTimeout] fires immediately
  /// (floored at zero). Idempotent — cancels any existing timer for `id`.
  void _armSendTimeout(String id, DateTime ts) {
    final ref = _activeRef;
    if (ref == null) return;
    _pendingSendTimers.remove(id)?.cancel();
    final remaining = pendingSendTimeout - DateTime.now().difference(ts);
    _pendingSendTimers[id] = _pendingSendTimerFactory(
      remaining > Duration.zero ? remaining : Duration.zero,
      () => _onSendTimeout(id, ref),
    );
  }

  /// No echo arrived within [pendingSendTimeout]: replace the optimistic
  /// bubble with a visible failure and unwind only the turn state that belongs
  /// to THIS `id`.
  void _onSendTimeout(String id, RemoteSessionRef expectedRef) {
    _runDetachedWrite(
      operation: LifecycleOperation.transcriptWrite,
      write: () => _failPendingSend(
        id,
        code: 'send_timeout',
        message:
            'Message was not confirmed by the Pi. It may not have been delivered.',
        expectedRef: expectedRef,
      ),
      expectedRef: expectedRef,
      requestReplayOnFailure: true,
    );
  }

  void _handleDeliveryPending(String? id) {
    if (id == null) return;
    final existing = _pendingSendTimers.remove(id);
    if (existing == null) return;
    existing.cancel();
    final ref = _activeRef;
    if (ref == null) return;
    _pendingSendTimers[id] = _pendingSendTimerFactory(
      deliveryPendingEchoTimeout,
      () => _onDeliveryPendingTimeout(id, ref),
    );
  }

  void _onDeliveryPendingTimeout(String id, RemoteSessionRef expectedRef) {
    _runDetachedWrite(
      operation: LifecycleOperation.transcriptWrite,
      write: () => _failPendingSend(
        id,
        code: 'send_timeout',
        message:
            'Message was not confirmed by the Pi. It may not have been delivered.',
        expectedRef: expectedRef,
      ),
      expectedRef: expectedRef,
      requestReplayOnFailure: true,
    );
  }

  Future<void> _failPendingSend(
    String id, {
    required String code,
    required String message,
    RemoteSessionRef? expectedRef,
    int? expectedGeneration,
  }) async {
    final generation = expectedGeneration ?? _lifecycleGeneration;
    if (!_isCurrentLifecycle(generation, expectedRef)) return;
    final preservesActiveTurn = _pendingSteeringId == id;
    _pendingSendTimers.remove(id)?.cancel();
    if (!_isCurrentLifecycle(generation, expectedRef)) return;
    try {
      await _appendTranscriptEvent(
        UserMessageFailed(
          eventId: 'local:user_failed:$id:$code',
          sessionId: expectedRef?.sessionId ?? _activeTranscriptSessionId(),
          ts: DateTime.now(),
          clientMessageId: id,
          code: code,
          message: message,
        ),
        preserveTurnState: preservesActiveTurn,
      );
    } finally {
      if (_isCurrentLifecycle(generation, expectedRef)) {
        // Terminal in-memory convergence is independent of durable storage.
        if (_pendingSteeringId == id) {
          _setTranscriptSteering(const NoSteering());
        }
        if (_streaming?.inReplyTo == id) _emitStreaming(null);
        if (turnProjection.cancelTargetId == id) _setTurnIdle();
        final diagnosticCode = admitFailureCode(code);
        debugPrint('[msg-failed] id=$id code=$diagnosticCode');
        _logDebug(
          MsgFailedEvent(ts: DateTime.now(), id: id, code: diagnosticCode),
        );
        _logDebug(
          SendQueueEvent(
            ts: DateTime.now(),
            id: id,
            phase: SendQueuePhase.visibleFail,
            code: diagnosticCode,
          ),
        );
      }
    }
  }

  void _cancelAllSendTimers() {
    for (final t in _pendingSendTimers.values) {
      t.cancel();
    }
    _pendingSendTimers.clear();
  }

  /// Test seam — number of armed no-echo timers (asserts no leak on reset).
  @visibleForTesting
  int get debugPendingSendTimerCount =>
      _pendingSendTimers.length + _identityPendingTimers.length;

  @visibleForTesting
  TranscriptEventStore get debugTranscriptEventStore => _eventStore;

  @visibleForTesting
  Future<void> debugApplyHistory(SessionHistory history) =>
      _replayHistory(history);

  /// Set the Pi-visible queued composer text when an active channel exists.
  Future<void> setQueuedMessage(String text) async {
    final ch = _conn.channel;
    if (ch == null) return;
    _setQueuedText(text);
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      QueuedMessageSet(id: _newId(), sessionId: ref.sessionId, text: text),
    );
  }

  /// Clear local queued text and request the same clear from the active Pi.
  Future<void> clearQueuedMessage() async {
    final ch = _conn.channel;
    _setQueuedText(null);
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(QueuedMessageClear(id: _newId(), sessionId: ref.sessionId));
  }

  /// Cancel the named active reply and disarm its local delivery backstop.
  Future<void> cancel(String targetId) async {
    // User-driven cancel of this message → disarm its no-echo backstop too.
    _pendingSendTimers.remove(targetId)?.cancel();
    final ch = _conn.channel;
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      Cancel(id: _newId(), sessionId: ref.sessionId, targetId: targetId),
    );
  }

  /// Send one tool-approval decision to the active canonical session.
  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {
    final ch = _conn.channel;
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      ApproveTool(
        id: _newId(),
        sessionId: ref.sessionId,
        toolCallId: toolCallId,
        decision: decision,
      ),
    );
    // Tool approval status is ultimately materialized from the transcript/tool
    // event stream. Do not mutate the disposable msgs projection directly here.
  }

  /// Request authoritative session history, deferring until channel and session bind.
  void requestSync() {
    final ch = _conn.channel;
    final ref = _activeRef;
    if (ch == null || ref == null) {
      _pendingSyncRequest = true;
      return;
    }
    _pendingSyncRequest = false;
    ch.send(SessionSync(id: _newId(), sessionId: ref.sessionId)).catchError((
      Object err,
      StackTrace _,
    ) {
      debugPrint('[session-sync] request failed');
      _logDebug(SessionSyncEvent(ts: DateTime.now()));
    });
  }

  /// Plan/28 — `session_new` acked: wipe the active session's rows.
  /// Keep the persisted `session_started_at` high-water so stale post-clear
  /// history can still be identified from persisted state.
  Future<void> clearActiveSession() async {
    final ref = _activeRef;
    if (ref == null) return;
    final generation = _lifecycleGeneration;
    // Session wiped → any optimistic sends are moot; disarm their backstops.
    _cancelAllSendTimers();
    await _enqueue(() async {
      if (!_isCurrentLifecycle(generation, ref)) return;
      final box = await _boxes.msgsBox(ref);
      if (!_isCurrentLifecycle(generation, ref)) return;
      await box.clear();
      if (!_isCurrentLifecycle(generation, ref)) return;
      _idToSeq.clear();
      _nextSeq = 0;
      _indexLoaded = true;
      await _clearTranscriptEventsForRef(ref, generation);
      if (!_isCurrentLifecycle(generation, ref)) return;
      await _rewriteMessageProjectionInWriteChain(
        ref,
        const TranscriptProjection(
          messages: <ChatMessage>[],
          turn: TranscriptTurnView.idle,
          steering: NoSteering(),
        ),
        const <TranscriptEvent>[],
        generation,
      );
      if (!_isCurrentLifecycle(generation, ref)) return;
      // Session-clear is a `session_new` wipe boundary: a clear during an
      // active turn would otherwise leave the turn projection / streaming
      // cursor stuck on a stale cancel target. Reset the whole-turn state so
      // working converges false.
      // (`_cancelAllSendTimers()` already ran above; no need to repeat.)
      _resetTurnState();
    });
  }

  // ---------------------------------------------------------------------------
  // Channel → DB
  // ---------------------------------------------------------------------------

  void _onStatus(ConnectionStatus s) {
    _msgSub?.cancel();
    _msgSub = null;
    if (s is StatusOnline) {
      // Capture the peer that owns this channel so late frames from a replaced
      // connection cannot land in the newly selected session.
      final originEpk = _conn.activePeer?.remoteEpk;
      _msgSub = s.channel.serverMessages.listen(
        (msg) => _onServerMessage(msg, originEpk),
        onError: (Object _, StackTrace _) {},
      );
      _scheduleLifecycleOperation(
        LifecycleOperation.sessionRebind,
        _onlineActivated,
      );
    } else {
      _lifecycleGeneration++;
      // Disconnect is terminal for the in-memory turn regardless of whether a
      // pending persistence operation eventually succeeds.
      _resetTurnState(clearPendingSendTimers: false);
      _setTurnIdle();
    }
    _writeRuntime();
  }

  Future<void> _onlineActivated() async {
    if (_disposed || _conn.status is! StatusOnline) return;
    final peer = _conn.activePeer;
    var generation = _lifecycleGeneration;
    if (peer != null && _activeEpk == null) {
      generation = ++_lifecycleGeneration;
      final room = _conn.activeRoomId;
      final ref = _resolveActiveRef(peer.remoteEpk, room);
      await _activateForGeneration(peer.remoteEpk, room, ref, generation);
      if (!_isCurrentLifecycle(generation, ref)) return;
    }
    if (!_isCurrentLifecycle(generation)) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!_disposed && generation == _lifecycleGeneration) requestSync();
    });
    if (_pendingSyncRequest) requestSync();
  }

  Future<void> _handleRoomsChanged() async {
    if (_disposed) return;
    final epk = _activeEpk;
    final room = _activeRoomId;
    if (epk == null) return;
    var generation = _lifecycleGeneration;
    var expectedRef = _activeRef;
    final nextRef = _resolveActiveRef(epk, room);
    final sessionChanged = nextRef != expectedRef;
    if (sessionChanged) {
      _pendingSyncRequest = true;
      _resentHeldPendingIds.clear();
      generation = ++_lifecycleGeneration;
      expectedRef = nextRef;
      await _activateForGeneration(epk, room, nextRef, generation);
      if (!_isCurrentLifecycle(generation, expectedRef)) return;
    }

    if (expectedRef != null) {
      await _resendHeldPendingMessages(generation, expectedRef);
      if (!_isCurrentLifecycle(generation, expectedRef)) return;
    }
    if (sessionChanged || _pendingSyncRequest) requestSync();
  }

  /// Re-send messages whose `UserMessageSubmitted` event has `held: true`
  /// (never written to the channel because the room was offline at send
  /// time) and that are still pending or failed (not confirmed). Reuses the
  /// ORIGINAL `clientMessageId` so the echo/replay dedupes by id. A relay
  /// channel alone is not sufficient: room liveness must have been confirmed
  /// in the current transport generation, and is revalidated after async reads.
  /// Each id is re-sent at most once per session (`_resentHeldPendingIds`) to
  /// prevent the self-retrigger loop (the re-send's own `working:true`
  /// room_meta update re-fires `_onRoomsChanged`).
  Future<void> _resendHeldPendingMessages(
    int generation,
    RemoteSessionRef ref,
  ) async {
    if (!_isCurrentLifecycle(generation, ref)) return;
    final ch = _conn.channel;
    if (ch == null || !_conn.isRoomLive(ref.peerEpk, ref.roomId)) {
      return; // relay-only reconnect: wait for fresh room confirmation
    }
    final key = TranscriptSessionKey(
      peerId: ref.peerEpk,
      roomId: ref.roomId,
      sessionId: ref.sessionId,
    );
    final events = await _eventStore.readSession(key);
    if (!_isCurrentLifecycle(generation, ref) ||
        !_conn.isRoomLive(ref.peerEpk, ref.roomId)) {
      return;
    }
    final confirmedIds = <String>{};
    final heldPending = <UserMessageSubmitted>[];
    for (final e in events) {
      if (e is UserMessageConfirmed) {
        confirmedIds.add(e.clientMessageId);
      } else if (e is UserMessageSubmitted && e.held) {
        heldPending.add(e);
      }
    }
    for (final submitted in heldPending) {
      final id = submitted.clientMessageId;
      if (confirmedIds.contains(id)) continue; // already delivered
      if (_resentHeldPendingIds.contains(id)) continue; // in-flight this sweep
      // Re-verify the channel is still the active one (could have rotated
      // during the loop). Reuses the ORIGINAL id so the echo/replay dedupes.
      if (!_isCurrentLifecycle(generation, ref)) return;
      final currentCh = _conn.channel;
      if (currentCh == null || !_conn.isRoomLive(ref.peerEpk, ref.roomId)) {
        return;
      }
      _resentHeldPendingIds.add(id); // in-flight guard for this sweep
      try {
        if (!_isCurrentLifecycle(generation, ref)) return;
        await currentCh.send(
          UserMessage(
            id: id,
            sessionId: ref.sessionId,
            text: submitted.text,
            streamingBehavior: submitted.awaitingPickup
                ? UserMessageStreamingBehavior.steer
                : null,
            images: submitted.image == null
                ? null
                : [
                    WireImage(
                      data: submitted.image!.data,
                      mime: submitted.image!.mime,
                    ),
                  ],
          ),
        );
        if (!_isCurrentLifecycle(generation, ref)) return;
        // Re-arm the send-timeout from now (the original ts is stale).
        _armSendTimeout(id, DateTime.now());
        _logDebug(
          SendQueueEvent(
            ts: DateTime.now(),
            id: id,
            phase: SendQueuePhase.resend,
            outcome: SendQueueOutcome.sent,
          ),
        );
        debugPrint('[msg-resend] id=$id (held-pending re-sent on reconnect)');
      } catch (err) {
        if (!_isCurrentLifecycle(generation, ref)) return;
        // Remove from in-flight so a later healthy reconnect can retry —
        // a failed re-send must NOT be permanently suppressed.
        _resentHeldPendingIds.remove(id);
        _logDebug(
          SendQueueEvent(
            ts: DateTime.now(),
            id: id,
            phase: SendQueuePhase.resend,
            outcome: SendQueueOutcome.failed,
            code: 'send_error',
          ),
        );
        debugPrint('[msg-resend] id=$id failed');
      }
    }
  }

  void _onServerMessage(ServerMessage msg, [String? originEpk]) {
    // Plan/32f — drop frames from a peer whose channel is no longer the active
    // session (a stale connection still draining after `switchTo`). Without
    // this, a straggler write targets `_activeEpk` — which already points at
    // the NEW chat — and bleeds the old session's messages into the new box.
    // Only gate when BOTH origin and active are set and differ: pre-bind
    // (`_activeEpk == null`, cold boot before `activate`) must still flow, and
    // direct test calls without an origin aren't gated.
    if (originEpk != null && _activeEpk != null && originEpk != _activeEpk) {
      return;
    }
    final gate = _sessionGate.accepts(msg, _activeRef);
    if (!gate.accepted) {
      debugPrint(
        '[session-gate] drop type=${gate.messageType ?? typeOfServerMessage(msg)} '
        'room=$_activeRoomId reason=${gate.reason} '
        'msg_session=${_shortSessionId(gate.messageSessionId)} '
        'active_session=${_shortSessionId(gate.expectedSessionId)}',
      );
      _logDebug(
        SessionGateEvent(
          ts: DateTime.now(),
          messageType: gate.messageType ?? typeOfServerMessage(msg),
          reason: gate.reason,
          sessionIdTail: _sessionIdTail(gate.messageSessionId),
        ),
      );
      _disarmGateRejectedUserInputEcho(msg);
      return;
    }
    final expectedRef = _activeRef;
    switch (msg) {
      case AgentChunk(:final inReplyTo, :final delta):
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvent(
            AssistantDeltaReceived(
              eventId: 'server:assistant_delta:$inReplyTo:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: DateTime.now(),
              replyTo: inReplyTo,
              delta: delta,
            ),
          ),
          expectedRef: expectedRef,
        );
        _setTurnActive(status: AppTurnStatus.streaming, replyTo: inReplyTo);

      case AgentDone(:final inReplyTo, :final ts):
        final buffered = _streaming?.buffer ?? '';
        // Legacy streamed turns have no agent_message commit to carry the
        // canonical timestamp. Prefer agent_done's server timestamp for the
        // fallback authoritative bubble; retain the local clock only for old
        // extensions that omit it.
        final assistantTs = ts != null
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now();
        // Identity-source (a): if a deterministic `agent_message` (from the
        // extension's `message_end`) already committed the final assistant
        // text for this turn, skip the buffer-commit — it would duplicate
        // the `agent_message` commit under a random eventId. The buffer is
        // cleared (streaming UI hides) regardless. Falls back to the
        // buffer-commit when no `agent_message` with `ts` arrived (legacy
        // extension, or a turn whose text only ever streamed). See
        // story-mobile-assistant-message-duplicated-live-replay decision 1.
        //
        // Layer 2 (dropped-frame robustness): once the capability flag is
        // latched (a live agent_message(ts) was seen at least once), a turn
        // with no agent_message(ts) at flush time means the frame was
        // DROPPED mid-flap (relay suspend for an offline peer), not a legacy
        // extension. Committing a random-uuid row there would dupe against
        // the deterministic replay that arrives on reconnect. Suppress the
        // commit and clear the buffer; the session_sync replay fills it
        // deterministically. See story-mobile-connection-flapping-drops-
        // identity-frames Layer 2.
        final committedViaAgentMessage = _agentMessageCommittedThisTurn;
        _agentMessageCommittedThisTurn = false;
        final deterministicExpectedButDropped =
            !committedViaAgentMessage &&
            _extensionSendsDeterministicAgentMessage;
        final terminalEvents = <TranscriptEvent>[];
        if (_streaming != null) _emitStreaming(null);
        if (buffered.isNotEmpty &&
            !committedViaAgentMessage &&
            !deterministicExpectedButDropped) {
          terminalEvents.add(
            AssistantMessageCommitted(
              eventId: 'server:assistant_committed:$inReplyTo:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: assistantTs,
              messageId: 'agent_${uuid7()}',
              replyTo: inReplyTo,
              text: buffered,
            ),
          );
        }
        terminalEvents.add(
          AssistantDoneReceived(
            eventId: 'server:assistant_done:$inReplyTo:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            replyTo: inReplyTo,
          ),
        );
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvents(terminalEvents),
          expectedRef: expectedRef,
        );
        _setTurnIdle(preview: buffered.isEmpty ? null : buffered);

      case AgentMessage(
        :final inReplyTo,
        :final text,
        :final ts,
        :final usage,
        :final messageId,
      ):
        // Identity-source (a): derive the SAME deterministic eventId/messageId
        // as session_history replay (AgentMessageEvt) so a live commit and
        // a replay of the same assistant message collapse to ONE Hive row
        // (deduped by eventId). The extension's `message_end`-driven
        // `agent_message` broadcast carries the SDK `ts` for this. Falls
        // back to the old random-id scheme only when `ts` is absent (legacy
        // extension / pre-fix) — see
        // story-mobile-assistant-message-duplicated-live-replay decision 1.
        if (ts != null) {
          final sessionId = _activeTranscriptSessionId();
          _agentMessageCommittedThisTurn = true;
          // Latch the capability: this extension emits deterministic
          // agent_message(ts). Future turns with no agent_message(ts) at
          // flush time were dropped, not legacy.
          _extensionSendsDeterministicAgentMessage = true;
          // Identity source (a): use `messageId` (sync_<ts>:assistant:
          // <blockIndex>) as the stable key when present so multi-block
          // assistant messages (same in_reply_to+ts, different blocks) do
          // NOT collide on the same eventId. Falls back to inReplyTo for
          // legacy live frames without message_id. Mirrors the replay path
          // (AgentMessageEvt). See story-mobile-assistant-message-
          // duplicated-live-replay decision 1.
          final stableKey = messageId ?? inReplyTo;
          _runDetachedTranscriptWrite(
            () => _appendTranscriptEvent(
              AssistantMessageCommitted(
                eventId: serverReplayEventId(
                  sessionId,
                  agentMessageWireType,
                  stableKey,
                  ts,
                ),
                sessionId: sessionId,
                ts: DateTime.fromMillisecondsSinceEpoch(ts),
                messageId: serverReplayMessageId(
                  sessionId,
                  agentMessageWireType,
                  stableKey,
                  ts,
                ),
                replyTo: inReplyTo,
                text: text,
                usage: usage,
              ),
            ),
            expectedRef: expectedRef,
          );
        } else {
          _runDetachedTranscriptWrite(
            () => _appendTranscriptEvent(
              AssistantMessageCommitted(
                eventId: 'server:assistant_message:$inReplyTo:${uuid7()}',
                sessionId: _activeTranscriptSessionId(),
                ts: DateTime.now(),
                messageId: 'agent_$inReplyTo',
                replyTo: inReplyTo,
                text: text,
              ),
            ),
            expectedRef: expectedRef,
          );
        }

      case QueuedMessageState(:final text):
        _setQueuedText(text?.isNotEmpty == true ? text : null);

      case UserInput(
        :final id,
        :final text,
        :final image,
        :final streamingBehavior,
        :final ts,
      ):
        // Echo dedupes against the optimistic row (same id): confirm it
        // (pending=false) or insert as confirmed (foreign device).
        _recordUserInputEcho(id);
        // Echo arrived → the send landed; disarm the no-echo backstop.
        _pendingSendTimers.remove(id)?.cancel();
        // Identity source (a) — user-message follow-up: when the echo carries
        // the SDK `ts` (from the extension's message_end-driven broadcast),
        // derive the SAME deterministic eventId as session_history replay
        // (UserInputEvt) so a live commit + replay collapse to ONE Hive row.
        // Falls back to the old scheme when `ts` is absent (legacy extension /
        // the early delivery-time echo). See story-mobile-assistant-message-
        // duplicated-live-replay user-message follow-up.
        final messageType = typeOfServerMessage(msg);
        final userEventId = ts != null
            ? serverReplayUserEventId(
                _activeTranscriptSessionId(),
                messageType,
                ts,
              )
            : 'server:user_confirmed:$id';
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvent(
            UserMessageConfirmed(
              eventId: userEventId,
              sessionId: _activeTranscriptSessionId(),
              ts: ts != null
                  ? DateTime.fromMillisecondsSinceEpoch(ts)
                  : DateTime.now(),
              clientMessageId: id,
              text: text,
              image: image == null
                  ? null
                  : MessageImage(data: image.data, mime: image.mime),
              streamingBehavior: streamingBehavior,
              semanticPickup:
                  ts != null ||
                  streamingBehavior != UserMessageStreamingBehavior.steer,
            ),
            preserveTurnState: true,
          ),
          expectedRef: expectedRef,
        );
        // Steering input should not start/replace the working turn bubble.
        if (streamingBehavior == UserMessageStreamingBehavior.steer) {
          _setActivity(SessionActivity.working, preview: text);
        } else {
          // New user turn → reset the per-turn agent_message-commit flag.
          _agentMessageCommittedThisTurn = false;
          _setTurnActive(
            status: AppTurnStatus.working,
            preview: text,
            replyTo: id,
          );
          // Show the thinking cursor for this turn (foreign-device echo, or the
          // local echo when the send-seed was already cleared). Guarded so it
          // never wipes a buffer that's already accumulating for this id.
          if (_streaming?.inReplyTo != id) {
            _emitStreaming(StreamingMessage(inReplyTo: id));
          }
        }

      case ToolRequest(:final toolCallId, :final tool, :final args, :final ts):
        // Sequential ordering: close the current text segment as its own row
        // BEFORE the tool, so "narration → command → narration" renders in
        // order instead of all text landing after the commands.
        final buffered = _streaming?.buffer ?? '';
        final toolEvents = <TranscriptEvent>[];
        if (buffered.isNotEmpty) {
          // Identity-source (a) guard: if a deterministic `agent_message`
          // (from the extension's `message_end`) already committed this
          // turn's assistant text, skip the buffer-commit — it would
          // duplicate the `agent_message` commit under a random eventId
          // (the live×replay eventId mismatch root cause — see
          // `story-mobile-assistant-message-duplicated-live-replay`
          // decision 1). The SDK fires `message_end` (→ `agent_message`
          // broadcast) BEFORE `tool_execution_start`, so the deterministic
          // commit lands first; this guard mirrors the `AgentDone` handler's
          // skip. Falls back to the buffer-commit only when no
          // `agent_message(ts)` arrived (legacy extension / pre-fix). The
          // streaming buffer is cleared regardless so the next text segment
          // starts fresh.
          //
          // Layer 2 (dropped-frame robustness): once the capability flag is
          // latched, a missing commit here means the deterministic
          // `agent_message(ts)` was DROPPED mid-flap (relay suspend for an
          // offline peer), not a legacy extension. Suppress the random-uuid
          // commit so the reconnect `session_sync` replay can fill the row
          // deterministically (a random-uuid live row would dupe against
          // the deterministic replay row). See
          // story-mobile-connection-flapping-drops-identity-frames Layer 2.
          final committedViaAgentMessage = _agentMessageCommittedThisTurn;
          final flushInReplyTo = _streaming!.inReplyTo;
          _emitStreaming(null);
          if (!committedViaAgentMessage &&
              !_extensionSendsDeterministicAgentMessage) {
            toolEvents.add(
              AssistantMessageCommitted(
                eventId: 'server:assistant_committed:$toolCallId:${uuid7()}',
                sessionId: _activeTranscriptSessionId(),
                ts: DateTime.now(),
                messageId: 'agent_${uuid7()}',
                replyTo: flushInReplyTo,
                text: buffered,
              ),
            );
          }
        }
        toolEvents.add(
          ToolRequested(
            eventId: 'server:tool_requested:$toolCallId',
            sessionId: _activeTranscriptSessionId(),
            ts: ts != null
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now(),
            toolCallId: toolCallId,
            tool: tool,
            args: _objectMap(args),
          ),
        );
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvents(toolEvents),
          expectedRef: expectedRef,
        );

      case ToolResult(
        :final toolCallId,
        :final result,
        :final error,
        :final ts,
      ):
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvent(
            ToolFinished(
              eventId: 'server:tool_finished:$toolCallId',
              sessionId: _activeTranscriptSessionId(),
              ts: ts != null
                  ? DateTime.fromMillisecondsSinceEpoch(ts)
                  : DateTime.now(),
              toolCallId: toolCallId,
              result: result,
              error: error,
            ),
          ),
          expectedRef: expectedRef,
        );

      case Cancelled(:final targetId):
        final pendingSteeringId = _pendingSteeringId;
        _pendingSendTimers.remove(targetId)?.cancel();
        if (pendingSteeringId != null && pendingSteeringId != targetId) {
          _pendingSendTimers.remove(pendingSteeringId)?.cancel();
        }
        _discardStreamingState();
        // A Pi cancellation clears its steering queue as well as the active
        // turn. Converge the overlay immediately, then persist a terminal event
        // for the separate steering id so cold replay cannot resurrect it.
        _setTranscriptSteering(const NoSteering());
        final cancelledAt = DateTime.now();
        final terminalEvents = <TranscriptEvent>[
          UserMessageFailed(
            eventId: 'server:user_cancelled:$targetId',
            sessionId: _activeTranscriptSessionId(),
            ts: cancelledAt,
            clientMessageId: targetId,
            code: 'cancelled',
            message: 'Message was cancelled before delivery was confirmed.',
          ),
          if (pendingSteeringId != null && pendingSteeringId != targetId)
            UserMessageFailed(
              eventId: 'server:steering_cancelled:$pendingSteeringId',
              sessionId: _activeTranscriptSessionId(),
              ts: cancelledAt,
              clientMessageId: pendingSteeringId,
              code: 'cancelled',
              message: 'Steering was cancelled before the agent picked it up.',
            ),
          AssistantDoneReceived(
            eventId: 'server:assistant_cancelled:$targetId:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: cancelledAt,
            replyTo: targetId,
          ),
        ];
        final cancellationGeneration = _lifecycleGeneration;
        _runDetachedWrite(
          operation: LifecycleOperation.transcriptWrite,
          write: () async {
            try {
              await _appendTranscriptEvents(terminalEvents);
            } finally {
              if (_isCurrentLifecycle(cancellationGeneration, expectedRef) &&
                  _pendingSteeringId == pendingSteeringId) {
                _setTranscriptSteering(const NoSteering());
              }
            }
          },
          expectedRef: expectedRef,
          requestReplayOnFailure: true,
        );
        _setTurnIdle();

      case Bye(:final rawReason):
        if (!_eventController.isClosed) {
          _eventController.add(PeerWentOffline(rawReason));
        }
        _setTurnIdle();
        final peer = _conn.activePeer;
        if (peer != null) {
          _scheduleLifecycleOperation(
            LifecycleOperation.sessionRebind,
            () => _conn.switchTo(peer),
          );
        }

      case SessionHistory():
        _runDetachedTranscriptWrite(
          () => _replayHistory(msg),
          expectedRef: expectedRef,
        );

      case ErrorMessage(:final inReplyTo, :final code, :final message):
        if (code == 'delivery_pending') {
          _handleDeliveryPending(inReplyTo);
          break;
        }
        if (code.contains('unknown_peer')) {
          if (!_eventController.isClosed) {
            _eventController.add(const PairingRevoked());
          }
          break;
        }
        // The foreign case is already dropped by `SessionGate` before this arm;
        // the narrow remaining window is when room metadata has already
        // rebound `_activeRef` to the rejecting Pi's session, so the gate
        // accepts the error. In both cases the mismatch is a convergence /
        // control signal, never transcript content: render no `⚠` row. The
        // legitimate re-sync is driven separately by canonical room-metadata
        // rotation (see `_onRoomsChanged`), never by this error's session id.
        // See story-foreign-session-user-message-tolerance.
        if (code == 'session_mismatch') {
          break;
        }
        final pendingId = inReplyTo;
        final rejectsPendingSteering =
            pendingId != null && _pendingSteeringId == pendingId;
        if (pendingId != null &&
            (_pendingSendTimers.containsKey(pendingId) ||
                rejectsPendingSteering)) {
          _runDetachedWrite(
            operation: LifecycleOperation.transcriptWrite,
            write: () => _failPendingSend(
              pendingId,
              code: code,
              message: message,
              expectedRef: expectedRef,
            ),
            expectedRef: expectedRef,
            requestReplayOnFailure: true,
          );
        }
        if (rejectsPendingSteering) break;
        _discardStreamingState();
        _setTurnIdle();
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvents(<TranscriptEvent>[
            AssistantMessageCommitted(
              eventId: 'server:error_message:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: DateTime.now(),
              messageId: 'err_${uuid7()}',
              replyTo: inReplyTo ?? 'error',
              text: '⚠ $code: $message',
            ),
            AssistantDoneReceived(
              eventId: 'server:error_done:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: DateTime.now(),
              replyTo: inReplyTo ?? 'error',
            ),
          ]),
          expectedRef: expectedRef,
        );

      case Compaction(:final summary, :final tokensBefore, :final ts):
        _setTurnIdle();
        _runDetachedTranscriptWrite(
          () => _appendTranscriptEvent(
            CompactionRecorded(
              eventId: 'server:compaction:${ts ?? uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: ts != null
                  ? DateTime.fromMillisecondsSinceEpoch(ts)
                  : DateTime.now(),
              summary: summary,
              tokensBefore: tokensBefore,
            ),
          ),
          expectedRef: expectedRef,
        );

      case Pong():
      case PairOk():
      case PairError():
      case ActionOk():
      case ActionError():
      case ModelsList():
        break;
    }
  }

  void _disarmGateRejectedUserInputEcho(ServerMessage msg) {
    if (msg case UserInput(:final id)) {
      final timer = _pendingSendTimers.remove(id);
      if (timer == null) return;
      timer.cancel();
      // The session gate still owns transcript acceptance, but a matching
      // echo id is sufficient to prove local delivery and disarm the no-echo
      // backstop even when the echo belongs to a freshly-resumed session.
      _recordUserInputEcho(id);
    }
  }

  void _recordUserInputEcho(String id) {
    debugPrint('[msg-echo] id=$id');
    _logDebug(MsgEchoEvent(ts: DateTime.now(), id: id));
  }

  static String _shortSessionId(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return '-';
    return sessionId.length <= 8
        ? sessionId
        : '…${sessionId.substring(sessionId.length - 8)}';
  }

  static String? _sessionIdTail(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return null;
    return sessionId.length <= 8
        ? sessionId
        : sessionId.substring(sessionId.length - 8);
  }

  static String _eventIdTail(String eventId) =>
      eventId.length <= 12 ? eventId : eventId.substring(eventId.length - 12);

  void _logDebug(DebugEvent event) => _debugLog?.log(event);

  bool _isCurrentLifecycle(int generation, [RemoteSessionRef? expectedRef]) =>
      !_disposed &&
      generation == _lifecycleGeneration &&
      (expectedRef == null ||
          (_activeRef == expectedRef &&
              _resolveActiveRef(expectedRef.peerEpk, expectedRef.roomId) ==
                  expectedRef));

  bool _canPublishTurnProjection(
    int generation,
    RemoteSessionRef ref,
    int projectionEpoch,
  ) =>
      projectionEpoch == _turnProjectionEpoch &&
      _isCurrentLifecycle(generation, ref);

  void _logLifecycleFailure(
    LifecycleOperation operation,
    Object error, {
    RemoteSessionRef? expectedRef,
  }) {
    final reason = error.runtimeType.toString();
    final peer = expectedRef?.peerEpk ?? _activeEpk;
    final sessionId = expectedRef?.sessionId;
    _logDebug(
      LifecycleFailureEvent(
        ts: DateTime.now(),
        operation: operation,
        reason: reason.isEmpty ? 'unknown_error' : reason,
        peerTail: peer == null
            ? null
            : (peer.length <= 8 ? peer : peer.substring(peer.length - 8)),
        room: expectedRef?.roomId ?? _activeRoomId,
        sessionIdTail: _sessionIdTail(sessionId),
      ),
    );
  }

  bool _markPersistenceDegraded(RemoteSessionRef ref) {
    if (_persistenceDegradedRef == ref || !_isStillActive(ref)) return false;
    _persistenceDegradedRef = ref;
    if (!_eventController.isClosed) {
      _eventController.add(
        const SessionPersistenceDegraded(
          'Messages could not be saved on this device.',
        ),
      );
    }
    return true;
  }

  void _markPersistenceRecovered(RemoteSessionRef ref) {
    if (_persistenceDegradedRef != ref || !_isStillActive(ref)) return;
    _persistenceDegradedRef = null;
    if (!_eventController.isClosed) {
      _eventController.add(const SessionPersistenceRecovered());
    }
  }

  void _clearPersistenceDegradationForReplacement() {
    if (_persistenceDegradedRef == null) return;
    _persistenceDegradedRef = null;
    if (!_eventController.isClosed) {
      _eventController.add(const SessionPersistenceRecovered());
    }
  }

  /// Plan/32 — persist a compaction as a system row so it renders a system
  /// bubble in the chat and survives a re-sync. Keyed by `ts` when present so
  /// the live message and its history replay collapse to one row.
  String _activeTranscriptSessionId() =>
      _activeRef?.sessionId ?? 'inactive-session';

  Future<void> _appendTranscriptEvent(
    TranscriptEvent event, {
    bool preserveTurnState = false,
  }) => _appendTranscriptEvents(<TranscriptEvent>[
    event,
  ], preserveTurnState: preserveTurnState);

  Future<void> _appendTranscriptEvents(
    Iterable<TranscriptEvent> events, {
    bool preserveTurnState = false,
  }) async {
    final ref = _activeRef;
    if (ref == null) return;
    final generation = _lifecycleGeneration;
    final projectionEpoch = _turnProjectionEpoch;
    final key = _transcriptKeyForRef(ref);
    final batch = events
        .where((event) => event.sessionId == key.sessionId)
        .toList(growable: false);
    if (batch.isEmpty) return;

    await _enqueue(() async {
      if (!_isCurrentLifecycle(generation, ref)) return;
      final result = await _eventStore.appendAll(key, batch);
      if (!_isCurrentLifecycle(generation, ref)) return;
      if (result.appended == 0) {
        _markPersistenceRecovered(ref);
        return;
      }
      final log = await _eventStore.readSession(key);
      if (!_isCurrentLifecycle(generation, ref)) return;
      final projection = deriveTranscriptProjection(
        sessionId: key.sessionId,
        events: log,
      );
      _setTranscriptSteering(projection.steering);
      if (!preserveTurnState &&
          _canPublishTurnProjection(generation, ref, projectionEpoch)) {
        _emitStreaming(projection.streaming);
        _setTurnView(projection.turn);
      }
      await _rewriteMessageProjectionInWriteChain(
        ref,
        projection,
        log,
        generation,
      );
      if (_isCurrentLifecycle(generation, ref)) {
        _markPersistenceRecovered(ref);
      }
    });
  }

  Future<void> _materializeTranscriptProjectionForRef(
    RemoteSessionRef ref,
    int generation,
  ) {
    final key = _transcriptKeyForRef(ref);
    final projectionEpoch = _turnProjectionEpoch;
    return _enqueue(() async {
      if (!_isCurrentLifecycle(generation, ref)) return;
      final log = await _eventStore.readSession(key);
      if (!_isCurrentLifecycle(generation, ref)) return;
      final projection = deriveTranscriptProjection(
        sessionId: key.sessionId,
        events: log,
      );
      _setTranscriptSteering(projection.steering);
      if (_isCurrentLifecycle(generation, ref)) {
        _logDebug(
          RouteEvent(
            ts: DateTime.now(),
            room: ref.roomId,
            phase: projection.messages.isEmpty
                ? RoutePhase.projectionEmpty
                : RoutePhase.projectionReady,
            sessionIdTail: _sessionIdTail(ref.sessionId),
            messageCount: projection.messages.length,
          ),
        );
      }
      if (_canPublishTurnProjection(generation, ref, projectionEpoch)) {
        _emitStreaming(projection.streaming);
        _setTurnView(projection.turn);
      }
      await _rewriteMessageProjectionInWriteChain(
        ref,
        projection,
        log,
        generation,
      );
      if (_isCurrentLifecycle(generation, ref)) {
        _markPersistenceRecovered(ref);
      }
    });
  }

  Future<void> _clearTranscriptEventsForRef(
    RemoteSessionRef ref,
    int generation,
  ) async {
    final key = _transcriptKeyForRef(ref);
    final box = await _boxes.transcriptEventsBox(key);
    if (!_isCurrentLifecycle(generation, ref)) return;
    await box.clear();
  }

  TranscriptSessionKey _transcriptKeyForRef(RemoteSessionRef ref) =>
      TranscriptSessionKey(
        peerId: ref.peerEpk,
        roomId: ref.roomId,
        sessionId: ref.sessionId,
      );

  bool _sameTranscriptKey(TranscriptSessionKey key, RemoteSessionRef ref) =>
      key.peerId == ref.peerEpk &&
      key.roomId == ref.roomId &&
      key.sessionId == ref.sessionId;

  Future<void> _rewriteMessageProjectionInWriteChain(
    RemoteSessionRef ref,
    TranscriptProjection projection,
    List<TranscriptEvent> log,
    int generation,
  ) async {
    if (!_isCurrentLifecycle(generation, ref)) return;
    final desired = <MessageRecord>[
      for (var i = 0; i < projection.messages.length; i++)
        _recordFromProjectedMessage(projection.messages[i], i, log),
    ];
    final box = await _boxes.msgsBox(ref);
    if (!_isCurrentLifecycle(generation, ref)) return;
    for (final k in box.keys.toList()) {
      if (!_isCurrentLifecycle(generation, ref)) return;
      if ((k as num).toInt() >= desired.length) {
        await box.delete(k);
        if (!_isCurrentLifecycle(generation, ref)) return;
      }
    }
    for (var i = 0; i < desired.length; i++) {
      final newJson = desired[i].toJson();
      final curRaw = box.get(i);
      final curJson = curRaw == null
          ? null
          : MessageRecord.fromJson(_coerce(curRaw)).toJson();
      if (curJson == null || !_sameMessageRecordJson(curJson, newJson)) {
        if (!_isCurrentLifecycle(generation, ref)) return;
        await box.put(i, newJson);
        if (!_isCurrentLifecycle(generation, ref)) return;
      }
    }
    if (!_isCurrentLifecycle(generation, ref)) return;
    _idToSeq
      ..clear()
      ..addEntries([
        for (var i = 0; i < desired.length; i++)
          MapEntry(_key(desired[i].role, desired[i].id), i),
      ]);
    _nextSeq = desired.length;
    _indexLoaded = true;
    _reconcilePendingSendTimers(desired);
  }

  MessageRecord _recordFromProjectedMessage(
    ChatMessage message,
    int seq,
    List<TranscriptEvent> log,
  ) {
    final ts = _timestampForProjectedMessage(message, log) ?? DateTime.now();
    return switch (message) {
      UserMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.user,
        text: message.text,
        image: message.image,
        status: message.status,
        ts: ts,
      ),
      AssistantMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.assistant,
        text: message.text,
        ts: ts,
      ),
      ToolEvent() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.tool,
        ts: ts,
        tool: ToolEventData(
          toolCallId: message.toolCallId,
          tool: message.tool,
          args: message.args,
          status: message.status,
          result: message.result,
          error: message.error,
        ),
      ),
      CompactionMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.compaction,
        text: message.summary,
        tokensBefore: message.tokensBefore,
        ts: ts,
      ),
    };
  }

  DateTime? _timestampForProjectedMessage(
    ChatMessage message,
    List<TranscriptEvent> log,
  ) {
    DateTime? ts;
    for (final event in log) {
      switch ((message, event)) {
        case (UserMsg(:final id), UserMessageConfirmed(:final clientMessageId))
            when id == clientMessageId:
          ts = event.ts;
        case (UserMsg(:final id), UserMessageSubmitted(:final clientMessageId))
            when id == clientMessageId && ts == null:
          ts = event.ts;
        case (UserMsg(:final id), UserMessageFailed(:final clientMessageId))
            when id == clientMessageId:
          ts = event.ts;
        case (
              AssistantMsg(:final id),
              AssistantMessageCommitted(:final messageId),
            )
            when id == messageId:
          ts = event.ts;
        case (
              ToolEvent(toolCallId: final messageToolCallId),
              ToolRequested(toolCallId: final eventToolCallId),
            )
            when messageToolCallId == eventToolCallId && ts == null:
          ts = event.ts;
        case (
              ToolEvent(toolCallId: final messageToolCallId),
              ToolFinished(toolCallId: final eventToolCallId),
            )
            when messageToolCallId == eventToolCallId:
          ts = event.ts;
        case (CompactionMsg(:final id), CompactionRecorded())
            when id == event.eventId:
          ts = event.ts;
        default:
          break;
      }
    }
    return ts;
  }

  void _reconcilePendingSendTimers(List<MessageRecord> desired) {
    final pendingIds = <String>{
      for (final record in desired)
        if (record.role == MsgRole.user && record.pending) record.id,
    };
    for (final id in _pendingSendTimers.keys.toList()) {
      if (!pendingIds.contains(id)) _pendingSendTimers.remove(id)?.cancel();
    }
    for (final record in desired) {
      if (record.role == MsgRole.user && record.pending) {
        _armSendTimeout(record.id, record.ts);
      }
    }
  }

  Future<void> _replayHistory(SessionHistory history) async {
    final ref = _activeRef;
    if (ref == null) return;
    final generation = _lifecycleGeneration;
    final projectionEpoch = _turnProjectionEpoch;
    final key = _transcriptKeyForRef(ref);
    if (history.sessionId != key.sessionId) return;
    if (_isStaleHistory(history.sessionStartedAt)) return;

    final replayEvents = sessionHistoryToTranscriptEvents(
      history: history,
      sessionId: key.sessionId,
    );

    await _enqueue(() async {
      if (!_isCurrentLifecycle(generation, ref) ||
          !_sameTranscriptKey(key, ref)) {
        return;
      }
      if (history.sessionId != key.sessionId) return;
      // Re-check inside the serialized write boundary: two replay batches can
      // race in from reconnect/status streams, and a stale boundary must be
      // rejected before any store append observes it.
      if (_isStaleHistory(history.sessionStartedAt)) return;

      // Track every eventId we have seen (pre-existing in the store PLUS each
      // one as we walk this batch) so a duplicate WITHIN a single replay batch
      // is reported as dropped, not just duplicates that pre-existed before
      // appendAll. Set.add returns true when the element was newly added, so
      // !add(...) == "already seen" == dropped. Without this, two identical
      // eventIds in one SessionHistory would both log dropped:false even
      // though appendAll skips the second — a false-negative exactly in the
      // collision case the ring log exists to diagnose.
      final existing = await _eventStore.readSession(key);
      if (!_isCurrentLifecycle(generation, ref)) return;
      final seenEventIds = <String>{
        for (final event in existing) event.eventId,
      };
      final result = await _eventStore.appendAll(key, replayEvents);
      if (!_isCurrentLifecycle(generation, ref)) return;
      for (final event in replayEvents) {
        final dropped = !seenEventIds.add(event.eventId);
        _logDebug(
          ReplayDedupEvent(
            ts: DateTime.now(),
            sessionId: key.sessionId,
            eventIdTail: _eventIdTail(event.eventId),
            dropped: dropped,
          ),
        );
      }
      if (result.appended > 0) {
        final log = await _eventStore.readSession(key);
        if (!_isCurrentLifecycle(generation, ref)) return;
        final projection = deriveTranscriptProjection(
          sessionId: key.sessionId,
          events: log,
        );
        _setTranscriptSteering(projection.steering);
        if (_canPublishTurnProjection(generation, ref, projectionEpoch)) {
          _emitStreaming(projection.streaming);
          _setTurnView(projection.turn);
        }
        await _rewriteMessageProjectionInWriteChain(
          ref,
          projection,
          log,
          generation,
        );
        if (!_isCurrentLifecycle(generation, ref)) return;
      }
      await _acceptHistoryBoundaryInWriteChain(
        ref,
        history.sessionStartedAt,
        generation,
      );
      if (_isCurrentLifecycle(generation, ref)) {
        _markPersistenceRecovered(ref);
      }
    });
  }

  bool _isStaleHistory(int sessionStartedAt) =>
      _acceptedSessionStartedAtHighWater != null &&
      sessionStartedAt < _acceptedSessionStartedAtHighWater!;

  Future<void> _acceptHistoryBoundaryInWriteChain(
    RemoteSessionRef ref,
    int sessionStartedAt,
    int generation,
  ) async {
    if (!_isCurrentLifecycle(generation, ref)) return;
    if (_acceptedSessionStartedAtHighWater != null &&
        sessionStartedAt <= _acceptedSessionStartedAtHighWater!) {
      return;
    }
    _acceptedSessionStartedAtHighWater = sessionStartedAt;
    final idx = _boxes.sessionsIndexBox();
    final key = LocalBoxes.sessionKey(ref);
    final raw = idx.get(key);
    final cur = raw is Map
        ? SessionIndexRecord.tryFromJson(raw.cast<String, dynamic>())
        : null;
    final base =
        cur ??
        SessionIndexRecord(
          epk: ref.peerEpk,
          roomId: ref.roomId,
          sessionId: ref.sessionId,
        );
    if (!_isCurrentLifecycle(generation, ref)) return;
    await idx.put(
      key,
      base
          .copyWith(
            sessionStartedAt: DateTime.fromMillisecondsSinceEpoch(
              sessionStartedAt,
            ),
          )
          .toJson(),
    );
  }

  // ---------------------------------------------------------------------------
  // Box write helpers (all serialised through _enqueue)
  // ---------------------------------------------------------------------------

  String _key(MsgRole role, String id) => '${role.name}:$id';

  Future<void> _loadIndex(RemoteSessionRef ref, int generation) {
    return _enqueue(() async {
      if (!_isCurrentLifecycle(generation, ref)) return;
      final box = await _boxes.msgsBox(ref);
      if (!_isCurrentLifecycle(generation, ref)) return;
      final idx = _boxes.sessionsIndexBox();
      final indexRaw = idx.get(LocalBoxes.sessionKey(ref));
      final indexRecord = indexRaw is Map<String, dynamic>
          ? SessionIndexRecord.tryFromJson(indexRaw)
          : indexRaw is Map
          ? SessionIndexRecord.tryFromJson(indexRaw.cast<String, dynamic>())
          : null;
      _acceptedSessionStartedAtHighWater =
          indexRecord?.sessionStartedAt?.millisecondsSinceEpoch;
      _idToSeq.clear();
      _nextSeq = 0;
      for (final k in box.keys) {
        if (!_isCurrentLifecycle(generation, ref)) return;
        final seq = (k as num).toInt();
        final r = MessageRecord.fromJson(_coerce(box.get(k)));
        _idToSeq[_key(r.role, r.id)] = seq;
        _nextSeq = math.max(_nextSeq, seq + 1);
        // Re-arm the no-echo backstop for any pending row this session owns, so
        // a bubble persisted across an app restart / quick session-switch fails
        // by its `ts` instead of spinning forever (already-stale → fires
        // immediately). Timers were cleared by _resetTurnState before this load.
        if (r.role == MsgRole.user && r.pending) _armSendTimeout(r.id, r.ts);
      }
      _indexLoaded = true;
    });
  }

  void _setActivity(SessionActivity status, {String? preview}) {
    _updateIndex(
      (cur) => cur.copyWith(
        status: status,
        lastMessageAt: preview != null ? DateTime.now() : null,
        lastMessagePreview: preview,
      ),
    );
  }

  void _setQueuedText(String? text) {
    if (_queuedText == text) return;
    _queuedText = text;
    if (!_queuedController.isClosed) _queuedController.add(text);
  }

  String? get _pendingSteeringId => switch (_transcriptSteering) {
    SteeringPending(:final clientMessageId) => clientMessageId,
    NoSteering() => null,
  };

  void _setTranscriptSteering(SteeringProjection next) {
    if (_transcriptSteering == next) return;
    _transcriptSteering = next;
    if (!_steeringController.isClosed) _steeringController.add(next);
  }

  void _setTurnViewLocalOnly(TranscriptTurnView next) {
    if (_sameTurnView(_turnView, next)) return;
    _turnView = next;
    if (!_turnViewController.isClosed) _turnViewController.add(next);
  }

  /// Single source of the active session's transcript turn projection.
  ///
  /// Terminal observations may clear matching room metadata as a compatibility
  /// correction. A replay-derived working state must not overwrite fresh idle
  /// metadata; live working observations opt in through [_setTurnActive].
  void _setTurnView(TranscriptTurnView next, {String? preview}) {
    final sameTurn = _sameTurnView(_turnView, next);
    if (sameTurn && preview == null) {
      if (!next.working) _correctRoomWorking(false);
      return;
    }
    _setActivity(
      next.working ? SessionActivity.working : SessionActivity.idle,
      preview: preview,
    );
    if (!next.working) _correctRoomWorking(false);
    if (sameTurn) return;
    _turnView = next;
    if (!_turnViewController.isClosed) _turnViewController.add(next);
  }

  void _correctRoomWorking(bool working) {
    final ref = _activeRef;
    if (ref == null) return;
    _conn.markRoomWorking(
      ref.peerEpk,
      ref.roomId,
      working,
      sessionId: ref.sessionId,
    );
  }

  void _setTurnActive({
    required AppTurnStatus status,
    String? preview,
    String? turnId,
    String? replyTo,
  }) {
    final target = replyTo ?? _turnView.replyTo ?? turnId;
    _correctRoomWorking(true);
    _setTurnView(
      TranscriptTurnView(
        status: status,
        sessionId: _activeRef?.sessionId,
        turnId: turnId ?? _turnView.turnId ?? target,
        replyTo: target,
      ),
      preview: preview,
    );
  }

  void _setTurnIdle({String? preview}) {
    _turnProjectionEpoch += 1;
    _setTurnView(TranscriptTurnView.idle, preview: preview);
  }

  bool _sameTurnView(TranscriptTurnView left, TranscriptTurnView right) =>
      left.status == right.status &&
      left.turnId == right.turnId &&
      left.replyTo == right.replyTo &&
      left.error == right.error;

  void _updateIndex(SessionIndexRecord Function(SessionIndexRecord cur) build) {
    final ref = _activeRef;
    if (ref == null) return;
    final generation = _lifecycleGeneration;
    _runDetachedWrite(
      operation: LifecycleOperation.runtimeWrite,
      write: () => _enqueue(() async {
        if (!_isCurrentLifecycle(generation, ref)) return;
        final idx = _boxes.sessionsIndexBox();
        final key = LocalBoxes.sessionKey(ref);
        final raw = idx.get(key);
        final cur = raw is Map
            ? SessionIndexRecord.tryFromJson(raw.cast<String, dynamic>())
            : null;
        final base =
            cur ??
            SessionIndexRecord(
              epk: ref.peerEpk,
              roomId: ref.roomId,
              sessionId: ref.sessionId,
            );
        if (!_isCurrentLifecycle(generation, ref)) return;
        await idx.put(key, build(base).toJson());
      }),
      expectedRef: ref,
    );
  }

  void _writeRuntime() {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    final ref = _activeRef;
    final generation = _lifecycleGeneration;
    final s = _conn.status;
    final conn = switch (s) {
      StatusOnline() => RuntimeConnection.online,
      StatusConnecting() => RuntimeConnection.connecting,
      StatusRetrying() => RuntimeConnection.retrying,
      StatusOffline() => RuntimeConnection.offline,
      StatusNoPeer() => RuntimeConnection.connecting,
    };
    final presence = (s is StatusOnline && _conn.isRoomLive(epk, room))
        ? RuntimePresence.alive
        : (s is StatusOnline ? RuntimePresence.stale : RuntimePresence.unknown);
    _runDetachedWrite(
      operation: LifecycleOperation.runtimeWrite,
      write: () => _enqueue(() async {
        if (!_isCurrentLifecycle(generation, ref) ||
            _activeEpk != epk ||
            _activeRoomId != room) {
          return;
        }
        final key = LocalBoxes.runtimeKey(epk, room);
        final value = RuntimeRecord(
          connection: conn,
          presence: presence,
        ).toJson();
        final writer = _runtimeRecordWriter;
        if (!_isCurrentLifecycle(generation, ref) ||
            _activeEpk != epk ||
            _activeRoomId != room) {
          return;
        }
        if (writer == null) {
          await _boxes.runtimeBox().put(key, value);
        } else {
          await writer(key, value);
        }
      }),
      expectedRef: ref,
    );
  }

  // ---------------------------------------------------------------------------
  // Streaming (in-memory only)
  // ---------------------------------------------------------------------------

  void _discardStreamingState() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _chunkBuffer.clear();
    _agentMessageCommittedThisTurn = false;
    _emitStreaming(null);
  }

  void _emitStreaming(StreamingMessage? s) {
    _streaming = s;
    if (!_streamingController.isClosed) _streamingController.add(s);
  }

  // ---------------------------------------------------------------------------

  void _runDetachedTranscriptWrite(
    Future<void> Function() write, {
    RemoteSessionRef? expectedRef,
  }) {
    _runDetachedWrite(
      operation: LifecycleOperation.transcriptWrite,
      write: write,
      expectedRef: expectedRef,
      requestReplayOnFailure: true,
    );
  }

  void _runDetachedWrite({
    required LifecycleOperation operation,
    required Future<void> Function() write,
    RemoteSessionRef? expectedRef,
    bool requestReplayOnFailure = false,
  }) {
    final generation = _lifecycleGeneration;
    unawaited(
      _observeDetachedWrite(
        operation: operation,
        write: write,
        generation: generation,
        expectedRef: expectedRef,
        requestReplayOnFailure: requestReplayOnFailure,
      ),
    );
  }

  Future<void> _observeDetachedWrite({
    required LifecycleOperation operation,
    required Future<void> Function() write,
    required int generation,
    RemoteSessionRef? expectedRef,
    required bool requestReplayOnFailure,
  }) async {
    if (!_isCurrentLifecycle(generation, expectedRef)) return;
    try {
      await write();
    } on Object catch (error) {
      if (!_isCurrentLifecycle(generation, expectedRef)) return;
      _logLifecycleFailure(operation, error, expectedRef: expectedRef);
      if (operation == LifecycleOperation.transcriptWrite &&
          expectedRef != null) {
        final newlyDegraded = _markPersistenceDegraded(expectedRef);
        if (newlyDegraded && requestReplayOnFailure) requestSync();
      }
    }
  }

  void _scheduleLifecycleOperation(
    LifecycleOperation operation,
    Future<void> Function() run,
  ) {
    final next = _lifecycleChain.then((_) async {
      if (_disposed) return;
      await run();
    });
    _lifecycleChain = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(_observeLifecycleOperation(next, operation));
  }

  Future<void> _observeLifecycleOperation(
    Future<void> operation,
    LifecycleOperation lifecycleOperation,
  ) async {
    try {
      await operation;
    } on Object catch (error) {
      if (_disposed) return;
      _logLifecycleFailure(lifecycleOperation, error, expectedRef: _activeRef);
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeChain.then((_) => operation());
    // Keep the predecessor usable after failure while returning [next] so an
    // awaited caller still receives the real persistence error.
    _writeChain = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static Map<String, dynamic> _coerce(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  static bool _sameMessageRecordJson(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final normalizedLeft = Map<String, dynamic>.of(left)..remove('ts');
    final normalizedRight = Map<String, dynamic>.of(right)..remove('ts');
    return jsonEncode(normalizedLeft) == jsonEncode(normalizedRight);
  }

  static Map<String, Object?> _objectMap(Object? raw) {
    if (raw == null) return <String, Object?>{};
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((key, value) {
        if (key is! String) {
          throw const FormatException('Tool request args keys must be strings');
        }
        return MapEntry(key, value as Object?);
      });
    }
    throw const FormatException('Tool request args must be an object');
  }

  static String _preview(String text, MessageImage? image) {
    if (text.isEmpty && image != null) return '📷 Image';
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  static String _newId() => 'cli_${uuid7()}';

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycleGeneration++;
    _resetTurnState(clearPendingSendTimers: true);
    _flushTimer?.cancel();
    _syncDebounce?.cancel();
    _cancelAllSendTimers();
    for (final timer in _identityPendingTimers.values) {
      timer.cancel();
    }
    _identityPendingTimers.clear();
    _connSub?.cancel();
    _msgSub?.cancel();
    _roomsSub?.cancel();
    _presenceSub?.cancel();
    _streamingController.close();
    _eventController.close();
    _turnViewController.close();
    _identityPendingController.close();
    _queuedController.close();
    _steeringController.close();
  }
}
