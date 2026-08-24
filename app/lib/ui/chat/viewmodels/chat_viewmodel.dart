import 'dart:async';

import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/room_snapshot_change.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

/// Plan/31 — ChatViewModel is now a thin composer over the local SSOT.
///
/// It reads messages + runtime from [SessionReadRepository] (the DB), composes
/// the in-memory streaming buffer from [SyncService] (#7), and issues commands
/// (send/cancel/approve) through [SyncService]. Connection lifecycle +
/// presence/rooms queries (AppBar) stay on [ConnectionManager]. It NEVER
/// subscribes to the channel directly — that's the SyncService's job.
class ChatViewModel extends ViewModel<ChatState> {
  final SessionReadRepository _read;
  final SyncService _sync;
  final ConnectionManager _conn;
  final Preferences _prefs;
  final PairingStorage _storage;

  StreamSubscription<List<MessageRecord>>? _msgsSub;
  StreamSubscription<RuntimeRecord>? _runtimeSub;
  StreamSubscription<StreamingMessage?>? _streamingSub;
  StreamSubscription<TranscriptTurnView>? _turnViewSub;
  StreamSubscription<SteeringProjection>? _steeringSub;
  StreamSubscription<String?>? _queuedSub;
  StreamSubscription<SessionEvent>? _eventSub;
  StreamSubscription<List<ChatMessage>>? _identityPendingSub;
  StreamSubscription<RoomSnapshotChange>? _roomChangesSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  PeerRecord? _activePeer;
  String _activeRoomId = 'main';
  RemoteSessionRef? _activeSessionRef;
  bool _bootstrapping = true;
  bool _disposed = false;
  bool _initialized = false;
  int _generation = 0;
  Future<void>? _initializeFuture;
  int? _initializeFutureGeneration;
  Future<void> _bindingChain = Future<void>.value();
  String? _initializationFailure;

  List<ChatMessage> _messages = const [];
  List<ChatMessage> _identityPendingMessages = const [];
  StreamingMessage? _streaming;
  TranscriptTurnView _transcriptTurn = TranscriptTurnView.idle;
  AppTurnProjection _turnProjection = AppTurnProjection.stale;
  SteeringProjection _transcriptSteering = const NoSteering();
  String? _queuedText;
  bool _pairingRevoked = false;
  String? _peerOfflineReason;
  String? _persistenceWarning;
  ConnectionStatus? _lastStatus;

  ChatViewModel(this._read, this._sync, this._conn, this._prefs, this._storage)
    : super(const ChatReady(messages: [])) {
    // Plan/32f — do NOT seed the shared SyncService turn projection here: it
    // may still be bound to the PREVIOUS chat (this VM is recreated
    // on session switch, before _bootstrap rebinds via activate). Seeding now
    // would briefly paint the old chat's streaming bubble / working pill. We
    // seed AFTER activate() in _bootstrap, when the sync owns THIS session.
    _streamingSub = _sync.streamingStream.listen(_onStreaming);
    _turnViewSub = _sync.turnViewStream.listen(_onTurnView);
    _steeringSub = _sync.steeringProjectionStream.listen(_onSteering);
    _queuedSub = _sync.queuedStream.listen(_onQueued);
    _eventSub = _sync.events.listen(_onEvent);
    _identityPendingSub = _sync.identityPendingMessagesStream.listen((rows) {
      _identityPendingMessages = rows;
      _recompute();
    });
    _roomChangesSub = _conn.roomChangesStream.listen(_onRoomChange);
    _statusSub = _conn.statusStream.listen(_onStatus);
    // Provider factories are synchronous. initialize owns and projects every
    // failure, so this detached constructor launch cannot leak an error.
    unawaited(initialize());
  }

  // --- AppBar-facing getters (relay/connection queries, not message data) ---

  PeerRecord? get activePeer => _activePeer;

  RoomInfo? get activeRoom {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return null;
    for (final r in _conn.roomsFor(epk)) {
      if (r.roomId == _activeRoomId) return r;
    }
    return null;
  }

  bool get isRoomLive {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return false;
    return _conn.isRoomLive(epk, _activeRoomId);
  }

  /// Whole-turn working signal for the room THIS chat is viewing.
  ///
  /// A single [AppTurnProjection] composes the fresh room projection with the
  /// active-room transcript/streaming projection. No sticky OR of unrelated
  /// booleans lives in the ViewModel.
  bool get isWorking => statusProjection.turn.working;

  /// Compose transport, turn, and steering without flattening their axes.
  ChatStatusProjection get statusProjection {
    final transport = _transportProjection();
    final steering = _transcriptSteering is SteeringPending
        ? _transcriptSteering
        : _queuedText == null
        ? const NoSteering()
        : SteeringPending(
            clientMessageId: 'queued-message',
            text: _queuedText!,
          );
    return ChatStatusProjection(
      transport: transport,
      turn: _turnProjection,
      steering: transport is ChatTransportOnline
          ? steering
          : const NoSteering(),
    );
  }

  /// The id to `cancel` to stop the in-flight reply. Null when idle/stale.
  String? get cancelTargetId =>
      statusProjection.canCancel ? statusProjection.turn.cancelTargetId : null;

  String? get queuedText => _queuedText;

  void setQueuedMessage(String text) {
    unawaited(_sync.setQueuedMessage(text));
  }

  void clearQueuedMessage() {
    unawaited(_sync.clearQueuedMessage());
  }

  // ---------------------------------------------------------------------------

  /// Initialize the selected chat once and project recoverable failures.
  ///
  /// Concurrent callers share one run. A retry after failure starts a fresh
  /// generation; disposal and newer generations prevent stale subscriptions.
  Future<void> initialize() {
    if (_disposed || (_initialized && _initializationFailure == null)) {
      return Future<void>.value();
    }
    final running = _initializeFuture;
    if (running != null) return running;

    final generation = ++_generation;
    _bootstrapping = true;
    _initialized = false;
    _initializationFailure = null;
    final future = _initializeOwned(generation);
    _initializeFuture = future;
    _initializeFutureGeneration = generation;
    return future;
  }

  Future<void> _initializeOwned(int generation) async {
    try {
      await _initializeRun(generation);
    } on Object {
      await _projectInitializationFailure(generation);
    } finally {
      if (_initializeFutureGeneration == generation) {
        _initializeFuture = null;
        _initializeFutureGeneration = null;
      }
    }
  }

  Future<void> _initializeRun(int generation) async {
    await _cancelProjectionSubscriptions();
    if (!_isCurrentRun(generation)) return;
    _activePeer = null;
    _activeSessionRef = null;
    _messages = const [];
    _connectionResolved = false;

    final epk = _prefs.selectedPeerEpk;
    final roomId = _prefs.selectedRoomId ?? 'main';
    if (epk == null) {
      _bootstrapping = false;
      _initialized = true;
      emit(const ChatNoPeer());
      return;
    }

    final peer = await _storage.loadPeer(epk);
    if (!_isCurrentRun(generation)) return;
    if (peer == null) {
      _bootstrapping = false;
      _initialized = true;
      emit(const ChatNoPeer());
      return;
    }

    final sessionPeer = peer.copyWith(roomId: roomId);
    _activePeer = sessionPeer;
    _activeRoomId = roomId;

    // Bind transport before the singleton writer. Otherwise a same-peer room
    // switch can briefly accept old-room frames while SyncService already
    // writes to the new room.
    _conn.switchRoom(roomId);
    if (_conn.activePeer?.remoteEpk != sessionPeer.remoteEpk) {
      await _conn.switchTo(sessionPeer);
      if (!_isCurrentRun(generation)) return;
      if (_activePeer != sessionPeer || _activeRoomId != roomId) return;
      _conn.switchRoom(roomId);
    }

    await _serializeSessionBinding(generation);
    if (!_isCurrentRun(generation)) return;
    if (_activePeer != sessionPeer || _activeRoomId != roomId) return;

    _runtimeSub = _read.watchRuntime(epk, roomId).listen((runtime) {
      if (_isCurrentRun(generation) &&
          _activePeer?.remoteEpk == epk &&
          _activeRoomId == roomId) {
        _onRuntime(runtime);
      }
    });

    _bootstrapping = false;
    _initialized = true;
    _sync.requestSync();
    _recompute();
  }

  Future<void> _serializeSessionBinding(int generation) {
    final operation = _bindingChain.then((_) async {
      if (!_isCurrentRun(generation)) return;
      await _refreshSessionBinding(generation);
    });
    _bindingChain = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _refreshSessionBinding(int generation) async {
    final peer = _activePeer;
    final roomId = _activeRoomId;
    if (peer == null || !_isCurrentRun(generation)) return;

    await _sync.activate(peer.remoteEpk, roomId);
    if (!_isCurrentRun(generation)) return;
    if (_activePeer != peer || _activeRoomId != roomId) return;

    // Seed only after activate owns this canonical session, avoiding a frame of
    // streaming/working state inherited from the previously selected chat.
    _streaming = _sync.streaming;
    _transcriptTurn = _sync.turnView;
    _transcriptSteering = _sync.steeringProjection;
    _queuedText = _sync.queuedText;
    _identityPendingMessages = _sync.identityPendingMessages;
    _updateTurnProjection();

    final ref = _sync.activeSessionRef;
    if (ref == _activeSessionRef) {
      _recompute();
      return;
    }

    final previous = _msgsSub;
    _msgsSub = null;
    _activeSessionRef = null;
    _messages = const [];
    await previous?.cancel();
    if (!_isCurrentRun(generation)) return;
    if (_activePeer != peer || _activeRoomId != roomId) return;

    _activeSessionRef = ref;
    if (ref != null) {
      _msgsSub = _read.watchMessages(ref).listen((rows) {
        if (_isCurrentRun(generation) && _activeSessionRef == ref) {
          _onMessages(rows);
        }
      });
    }
    _recompute();
  }

  void _onRoomChange(RoomSnapshotChange change) {
    final peer = _activePeer;
    if (_disposed ||
        peer == null ||
        change.isNoop ||
        !change.affectsRoom(peer.remoteEpk, _activeRoomId) ||
        !change.activeRoomPresentationChanged) {
      return;
    }
    if (_conn.isRoomLive(peer.remoteEpk, _activeRoomId)) {
      _peerOfflineReason = null;
    }
    if (change.requiresBinding) {
      unawaited(_handleRoomsChanged(change));
      return;
    }
    _recompute();
  }

  Future<void> _handleRoomsChanged(RoomSnapshotChange change) async {
    final generation = _generation;
    final peer = _activePeer;
    if (!_isCurrentRun(generation) ||
        peer == null ||
        !change.affectsRoom(peer.remoteEpk, _activeRoomId)) {
      return;
    }
    try {
      // The serialized binding owns the one coherent recompute after its
      // generation and session guards pass.
      await _serializeSessionBinding(generation);
    } on Object {
      await _projectInitializationFailure(generation);
    }
  }

  Future<void> _projectInitializationFailure(int generation) async {
    if (!_isCurrentRun(generation)) return;
    final failureGeneration = ++_generation;
    _bootstrapping = false;
    _initialized = false;
    _activePeer = null;
    _activeSessionRef = null;
    _messages = const [];
    await _cancelProjectionSubscriptions();
    if (_disposed || failureGeneration != _generation) return;
    _initializationFailure = 'Could not load this chat. Try again.';
    emit(ChatInitializationFailed(_initializationFailure!));
  }

  Future<void> _cancelProjectionSubscriptions() async {
    final messages = _msgsSub;
    final runtime = _runtimeSub;
    _msgsSub = null;
    _runtimeSub = null;
    await messages?.cancel();
    await runtime?.cancel();
  }

  bool _isCurrentRun(int generation) => !_disposed && generation == _generation;

  void _onMessages(List<MessageRecord> rows) {
    _messages = [for (final r in rows) r.toChatMessage()];
    _recompute();
  }

  void _onStreaming(StreamingMessage? s) {
    _streaming = s;
    _updateTurnProjection();
    _recompute();
  }

  void _onTurnView(TranscriptTurnView turn) {
    _transcriptTurn = turn;
    _updateTurnProjection();
    _recompute();
  }

  void _updateTurnProjection() {
    final epk = _activePeer?.remoteEpk;
    final room = epk == null
        ? RoomTurnProjection.stale
        : _conn.roomTurnProjection(epk, _activeRoomId);
    _turnProjection = deriveChatTurnProjection(
      room: room,
      transcript: _transcriptTurn,
      streaming: _streaming,
    );
  }

  // A non-null raw cursor is not independently renderable. Matching-session
  // authoritative idle is resolved by deriveChatTurnProjection; suppressing
  // its cursor here keeps stale replay residue out of ChatReady without hiding
  // a replacement session whose projection is still genuinely streaming.
  StreamingMessage? get _visibleStreaming =>
      _turnProjection.status == AppTurnStatus.idle ? null : _streaming;

  ChatTransportProjection _transportProjection() {
    final status = _lastStatus ?? _conn.status;
    return switch (status) {
      StatusOnline() when isRoomLive => ChatTransportOnline(
        roomId: _activeRoomId,
      ),
      StatusOnline() => const ChatTransportOffline(
        reason: 'Selected Pi room is unavailable',
      ),
      StatusConnecting() => const ChatTransportRetrying(
        attempt: 0,
        nextRetry: Duration.zero,
      ),
      StatusRetrying(:final attempt, :final nextRetry) => ChatTransportRetrying(
        attempt: attempt,
        nextRetry: nextRetry,
      ),
      StatusOffline(:final reason) => ChatTransportOffline(reason: reason),
      StatusNoPeer() => const ChatTransportOffline(
        reason: 'No paired Pi selected',
      ),
    };
  }

  void _onSteering(SteeringProjection steering) {
    _transcriptSteering = steering;
    _recompute();
  }

  void _onQueued(String? text) {
    _queuedText = text;
    _recompute();
  }

  /// Plan/32g — `true` once a real runtime (connection/presence) has been read
  /// from the box. Until then the AppBar trusts the `initialOnline` hint Home
  /// passed (the tile's live state) so the status dot doesn't flash
  /// "reconnecting" on the default runtime before the first read.
  bool get connectionResolved => _connectionResolved;
  bool _connectionResolved = false;

  void _onRuntime(RuntimeRecord _) {
    _connectionResolved = true;
    _recompute();
  }

  void _onStatus(ConnectionStatus s) {
    final wasOnline = _lastStatus is StatusOnline;
    final nowOnline = s is StatusOnline;
    _lastStatus = s;
    // A relay reconnect supersedes the sticky peer-offline event. Room
    // liveness still gates input independently, so clearing this reason cannot
    // enable sends until an authoritative room snapshot/announce arrives.
    if (nowOnline) _peerOfflineReason = null;
    // Auto re-sync on a fresh online edge so the chat catches up.
    if (nowOnline && !wasOnline) _sync.requestSync();
    _recompute();
  }

  void _onEvent(SessionEvent e) {
    if (e is PairingRevoked) {
      _pairingRevoked = true;
    } else if (e is PeerWentOffline) {
      _peerOfflineReason = e.rawReason;
    } else if (e is SessionPersistenceDegraded) {
      _persistenceWarning = e.message;
    } else if (e is SessionPersistenceRecovered) {
      _persistenceWarning = null;
    }
    _recompute();
  }

  void _recompute() {
    if (_disposed) return;
    _updateTurnProjection();
    emit(_compose());
  }

  ChatState _compose() {
    final initializationFailure = _initializationFailure;
    if (initializationFailure != null) {
      return ChatInitializationFailed(initializationFailure);
    }
    // No "loading"/connecting screen — once a peer is selected we always
    // render ChatReady (empty until the DB/stream delivers rows) and just
    // replace it as updates arrive. The connecting/offline status is shown
    // inline through the composed transport projection, never as a
    // full-screen spinner, so entering the chat doesn't flicker.
    if (_activePeer == null) {
      return _bootstrapping
          ? const ChatReady(messages: [])
          : const ChatNoPeer();
    }
    return ChatReady(
      messages: _messagesWithIdentityPending(),
      streaming: _visibleStreaming,
      status: statusProjection,
      pairingRevoked: _pairingRevoked,
      peerOfflineReason: _peerOfflineReason,
      queuedText: _queuedText,
      persistenceWarning: _persistenceWarning,
    );
  }

  List<ChatMessage> _messagesWithIdentityPending() {
    if (_identityPendingMessages.isEmpty) return _messages;
    final combined = List<ChatMessage>.of(_messages);
    final ids = {for (final message in combined) message.id};
    for (final message in _identityPendingMessages) {
      if (ids.add(message.id)) combined.add(message);
    }
    return combined;
  }

  // --- Commands (writer = SyncService; lifecycle = ConnectionManager) ---

  Future<void> sendMessage(String text, {MessageImage? image}) =>
      _sync.sendMessage(
        text,
        image: image,
        streamingBehavior: isWorking
            ? UserMessageStreamingBehavior.steer
            : null,
      );

  Future<void> cancel(String targetId) => _sync.cancel(targetId);

  Future<void> approveTool(String toolCallId, ApproveDecision decision) =>
      _sync.approveTool(toolCallId, decision);

  Future<void> clearActiveSession() => _sync.clearActiveSession();

  /// Request authoritative replay after a local persistence warning.
  void retryPersistenceSync() => _sync.requestSync();

  /// Rehydrate the retained route from local storage, then request replay.
  ///
  /// Visible history is never cleared while the read or network sync is in
  /// flight. A newer generation, session switch, or disposal suppresses the
  /// completion before it can mutate state.
  Future<void> refreshOnResume() async {
    final generation = _generation;
    final ref = _activeSessionRef;
    if (ref == null || !_isCurrentRun(generation)) return;

    try {
      final rows = await _read.readMessages(ref);
      if (!_isCurrentRun(generation) || _activeSessionRef != ref) return;
      _onMessages(rows);
    } on Object {
      // Keep the last visible projection. Authoritative replay remains the
      // recovery path for a transient local-read failure.
    }
    if (!_isCurrentRun(generation) || _activeSessionRef != ref) return;
    _sync.requestSync();
  }

  Future<void> reconnect() async {
    final peer = _activePeer;
    if (peer == null) return;
    _peerOfflineReason = null;
    // No connecting spinner — keep the current messages on screen and let the
    // status update inline as the connection comes back.
    _recompute();
    await _conn.switchTo(peer);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _msgsSub?.cancel();
    _runtimeSub?.cancel();
    _streamingSub?.cancel();
    _turnViewSub?.cancel();
    _steeringSub?.cancel();
    _queuedSub?.cancel();
    _eventSub?.cancel();
    _identityPendingSub?.cancel();
    _roomChangesSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
