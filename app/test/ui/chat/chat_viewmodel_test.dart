// Plan/31 — ChatViewModel is a thin composer over the SSOT. A message written
// to the DB (via the channel → SyncService) must surface in ChatState.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = [];
  String defaultSessionId = '';
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Stream<ControlInbound> get controlFrames => _control.stream;
  @override
  void sendControl(Map<String, dynamic> json) {}
  @override
  Future<void> send(ClientMessage msg) async => sent.add(msg);
  @override
  Future<void> close() async {
    await _ctrl.close();
    await _control.close();
  }

  void push(ServerMessage m) => _ctrl.add(_withDefaultSession(m));
  void pushRaw(ServerMessage m) => _ctrl.add(m);
  void pushControl(ControlInbound m) => _control.add(m);

  ServerMessage _withDefaultSession(ServerMessage m) {
    final sid = defaultSessionId;
    if (sid.isEmpty) return m;
    return switch (m) {
      UserInput(:final sessionId) when sessionId.isEmpty => UserInput(
        id: m.id,
        sessionId: sid,
        text: m.text,
        streamingBehavior: m.streamingBehavior,
        image: m.image,
      ),
      AgentChunk(:final sessionId) when sessionId.isEmpty => AgentChunk(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        delta: m.delta,
      ),
      AgentDone(:final sessionId) when sessionId.isEmpty => AgentDone(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        usage: m.usage,
      ),
      Cancelled(:final sessionId) when sessionId.isEmpty => Cancelled(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        targetId: m.targetId,
      ),
      _ => m,
    };
  }
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _s = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _s[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _s.remove(key);
    } else {
      _s[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _peer = PeerRecord(
  remoteEpk: 'epk_chat',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [_peer];
  @override
  Future<PeerRecord?> loadPeer(String epk) async =>
      epk == _peer.remoteEpk ? _peer : null;
  @override
  Future<void> savePeer(PeerRecord r) async {}

  // In-memory rooms so a RoomAnnounced landing on the real ConnectionManager
  // (_persistRoomsForPeer) never touches flutter_secure_storage.
  final Map<String, List<PersistedRoom>> _rooms = {};
  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async =>
      _rooms[epk] = rooms;
  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async =>
      _rooms[epk] ?? const [];
  @override
  Future<void> deleteRooms(String epk) async => _rooms.remove(epk);
}

class _FailOnceStorage extends _FakeStorage {
  bool failNextLoad = true;

  @override
  Future<PeerRecord?> loadPeer(String epk) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    return super.loadPeer(epk);
  }
}

class _DeferredStorage extends _FakeStorage {
  final loadCompleter = Completer<PeerRecord?>();

  @override
  Future<PeerRecord?> loadPeer(String epk) => loadCompleter.future;
}

class _FailingWatchReadRepository extends SessionReadRepository {
  _FailingWatchReadRepository(super.boxes);

  bool failWatch = false;

  @override
  Stream<List<MessageRecord>> watchMessages(RemoteSessionRef ref) {
    if (failWatch) throw StateError('watch failed');
    return super.watchMessages(ref);
  }
}

class _ResumeReadRepository extends SessionReadRepository {
  _ResumeReadRepository(super.boxes);

  final messagesController = StreamController<List<MessageRecord>>.broadcast();
  List<MessageRecord> snapshot = const [];
  Completer<List<MessageRecord>>? deferredRead;
  int watchCount = 0;

  @override
  Stream<List<MessageRecord>> watchMessages(RemoteSessionRef ref) {
    watchCount += 1;
    return messagesController.stream;
  }

  @override
  Future<List<MessageRecord>> readMessages(RemoteSessionRef ref) async =>
      deferredRead?.future ?? snapshot;

  void emit(List<MessageRecord> rows) => messagesController.add(rows);

  Future<void> close() => messagesController.close();
}

class _EventSyncService extends SyncService {
  _EventSyncService(super.connectionManager, super.boxes);

  final eventController = StreamController<SessionEvent>.broadcast();

  @override
  Stream<SessionEvent> get events => eventController.stream;

  void emitEvent(SessionEvent event) => eventController.add(event);

  @override
  void dispose() {
    eventController.close();
    super.dispose();
  }
}

class _ControlledActivateSyncService extends SyncService {
  _ControlledActivateSyncService(super.connectionManager, super.boxes);

  bool failActivation = false;

  @override
  Future<void> activate(String epk, String roomId) {
    if (failActivation) {
      return Future<void>.error(StateError('activation failed'));
    }
    return super.activate(epk, roomId);
  }
}

class _ProjectionSyncService extends SyncService {
  _ProjectionSyncService(super.connectionManager, super.boxes, this.sessionRef);

  final RemoteSessionRef sessionRef;
  final streamingController = StreamController<StreamingMessage?>.broadcast();
  final turnController = StreamController<TranscriptTurnView>.broadcast();
  StreamingMessage? streamingValue;
  TranscriptTurnView turnValue = TranscriptTurnView.idle;

  @override
  RemoteSessionRef get activeSessionRef => sessionRef;

  @override
  StreamingMessage? get streaming => streamingValue;

  @override
  Stream<StreamingMessage?> get streamingStream => streamingController.stream;

  @override
  TranscriptTurnView get turnView => turnValue;

  @override
  Stream<TranscriptTurnView> get turnViewStream => turnController.stream;

  @override
  Future<void> activate(String epk, String roomId) async {}

  void emitTurn(TranscriptTurnView value) {
    turnValue = value;
    turnController.add(value);
  }

  void emitStreaming(StreamingMessage value) {
    streamingValue = value;
    streamingController.add(value);
  }

  @override
  void dispose() {
    streamingController.close();
    turnController.close();
    super.dispose();
  }
}

late Directory _dir;
int _sessionCounter = 0;

Future<void> _adoptWithSession(ConnectionManager conn, _FakeChannel ch) async {
  final sessionId = 'chat-session-${++_sessionCounter}';
  ch.defaultSessionId = sessionId;
  conn.adopt(ch, _peer);
  ch.pushRaw(
    PairOk(
      inReplyTo: 'pair-$sessionId',
      sessionName: 'Pi',
      sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
      roomId: 'main',
      sessionId: sessionId,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

void main() {
  setUpAll(() async {
    _dir = Directory.systemTemp.createTempSync('rp_v2_chatvm_');
    await LocalBoxes.initForTest(_dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _dir.delete(recursive: true);
  });

  test(
    'initialization failure is retryable through the awaited owner',
    () async {
      final ch = _FakeChannel();
      final storage = _FailOnceStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
      await _adoptWithSession(conn, ch);

      final vm = ChatViewModel(
        SessionReadRepository(boxes),
        sync,
        conn,
        prefs,
        storage,
      );
      await vm.initialize();
      expect(vm.state, isA<ChatInitializationFailed>());

      await vm.initialize();
      expect(vm.state, isA<ChatReady>());

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test('persistence degradation is visible and clears on recovery', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = _EventSyncService(conn, boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
    await _adoptWithSession(conn, ch);
    final vm = ChatViewModel(
      SessionReadRepository(boxes),
      sync,
      conn,
      prefs,
      storage,
    );
    await vm.initialize();

    sync.emitEvent(
      const SessionPersistenceDegraded('Local persistence unavailable.'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      (vm.state as ChatReady).persistenceWarning,
      'Local persistence unavailable.',
    );

    sync.emitEvent(const SessionPersistenceRecovered());
    await Future<void>.delayed(Duration.zero);
    expect((vm.state as ChatReady).persistenceWarning, isNull);

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test(
    'resume refresh repopulates retained route without duplicate subscriptions',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = _ResumeReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
      await _adoptWithSession(conn, ch);
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await vm.initialize();

      final row = MessageRecord(
        id: 'resume-user',
        seq: 0,
        role: MsgRole.user,
        text: 'still here',
        ts: DateTime.utc(2026, 1, 1),
      );
      read.snapshot = [row];
      read.emit([row]);
      await Future<void>.delayed(Duration.zero);
      expect((vm.state as ChatReady).messages, hasLength(1));

      read.emit(const []);
      await Future<void>.delayed(Duration.zero);
      expect((vm.state as ChatReady).messages, isEmpty);

      await vm.refreshOnResume();
      await vm.refreshOnResume();
      expect((vm.state as ChatReady).messages.map((message) => message.id), [
        'resume-user',
      ]);
      expect(
        read.watchCount,
        1,
        reason: 'resume reuses the retained subscription',
      );

      read.emit(const []);
      await Future<void>.delayed(Duration.zero);
      read.deferredRead = Completer<List<MessageRecord>>();
      final staleRefresh = vm.refreshOnResume();
      vm.dispose();
      read.deferredRead!.complete([row]);
      await staleRefresh;
      expect((vm.state as ChatReady).messages, isEmpty);

      await read.close();
      sync.dispose();
      conn.dispose();
    },
  );

  test('activation failure becomes ChatInitializationFailed', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
    await _adoptWithSession(conn, ch);
    final sync = _ControlledActivateSyncService(conn, boxes)
      ..failActivation = true;

    final vm = ChatViewModel(
      SessionReadRepository(boxes),
      sync,
      conn,
      prefs,
      storage,
    );
    await vm.initialize();

    expect(vm.state, isA<ChatInitializationFailed>());
    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test('dispose invalidates a deferred storage completion', () async {
    final ch = _FakeChannel();
    final storage = _DeferredStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
    await _adoptWithSession(conn, ch);

    final vm = ChatViewModel(
      SessionReadRepository(boxes),
      sync,
      conn,
      prefs,
      storage,
    );
    final initialization = vm.initialize();
    vm.dispose();
    storage.loadCompleter.complete(_peer);
    await initialization;

    expect(vm.state, isNot(isA<ChatInitializationFailed>()));
    sync.dispose();
    conn.dispose();
  });

  test('failed session rotation clears old rows and fails closed', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final read = _FailingWatchReadRepository(boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
    await _adoptWithSession(conn, ch);

    final vm = ChatViewModel(read, sync, conn, prefs, storage);
    await vm.initialize();
    ch.push(UserInput(id: 'before-rotation', text: 'old row'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((vm.state as ChatReady).messages, isNotEmpty);

    read.failWatch = true;
    ch.pushRaw(
      PairOk(
        inReplyTo: 'rotation',
        sessionName: 'Pi',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: 'main',
        sessionId: 'failed-rotation-session',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(vm.state, isA<ChatInitializationFailed>());
    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test('a message written to the DB surfaces in ChatState', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final read = SessionReadRepository(boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

    await _adoptWithSession(conn, ch);

    final vm = ChatViewModel(read, sync, conn, prefs, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The Pi rebroadcasts a user message → SyncService writes a row →
    // SessionReadRepository emits → ChatViewModel recomposes.
    ch.push(UserInput(id: 'u1', text: 'hello from db'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = vm.state;
    expect(state, isA<ChatReady>());
    final messages = (state as ChatReady).messages;
    expect(
      messages.whereType<UserMsg>().map((m) => m.text),
      contains('hello from db'),
    );

    // BUG fix (smoke): the chat "working" pill must be on for the whole turn,
    // not just the token-streaming window — and the composer locks + the send
    // button becomes "stop" (cancelTargetId points at the in-flight turn).
    expect(vm.isWorking, isTrue, reason: 'turn started → working');
    expect(vm.cancelTargetId, 'u1', reason: 'stop button cancels this turn');
    ch.push(AgentDone(inReplyTo: 'u1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm.isWorking, isFalse, reason: 'agent_done → idle');
    expect(vm.cancelTargetId, isNull, reason: 'no turn to cancel when idle');

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test('awaiting tool remains independently online and cancellable', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
    await _adoptWithSession(conn, ch);

    final vm = ChatViewModel(
      SessionReadRepository(boxes),
      sync,
      conn,
      prefs,
      storage,
    );
    await vm.initialize();
    ch.push(UserInput(id: 'tool-u1', text: 'run it'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ch.pushRaw(
      ToolRequest(
        sessionId: ch.defaultSessionId,
        toolCallId: 'tool-1',
        tool: 'bash',
        args: const {'command': 'pwd'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final status = (vm.state as ChatReady).status;
    expect(status.transport, isA<ChatTransportOnline>());
    expect(status.turn.status, AppTurnStatus.awaitingTool);
    expect(status.canCancel, isTrue);
    expect(vm.cancelTargetId, 'tool-u1');

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test(
    'cancelled clears the stop state without deleting the user row',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      await _adoptWithSession(conn, ch);
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      ch.push(UserInput(id: 'cancel-u1', text: 'please stop'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ch.push(AgentChunk(inReplyTo: 'cancel-u1', delta: 'partial'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.isWorking, isTrue);
      expect(vm.cancelTargetId, 'cancel-u1');
      expect((vm.state as ChatReady).streaming, isNotNull);

      ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'cancel-u1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = vm.state as ChatReady;
      expect(vm.isWorking, isFalse);
      expect(vm.cancelTargetId, isNull);
      expect(state.streaming, isNull);
      expect(
        state.messages.whereType<UserMsg>().map((m) => m.text),
        contains('please stop'),
      );
      expect(
        state.messages.whereType<UserMsg>().single.status,
        UserMsgStatus.confirmed,
      );

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'working send uses steer behavior and preserves current target',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      await _adoptWithSession(conn, ch);
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      ch.push(UserInput(id: 'u1', text: 'primary'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.isWorking, isTrue, reason: 'set up an active turn');
      final originalTarget = vm.cancelTargetId;
      expect(originalTarget, 'u1');

      await vm.sendMessage('steer follow-up');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final sent = ch.sent.whereType<UserMessage>().lastWhere(
        (m) => m.text == 'steer follow-up',
      );
      expect(sent.streamingBehavior, UserMessageStreamingBehavior.steer);
      expect(vm.cancelTargetId, equals(originalTarget));

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'reconnect hydrate send before session identity is visible then re-sent',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(
        conn,
        boxes,
        pendingSendTimeout: const Duration(milliseconds: 500),
      );
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      conn.adopt(ch, _peer);
      ch.pushControl(
        const RoomAnnounced(peer: 'epk_chat', roomId: 'main', startedAt: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final vm = ChatViewModel(
        SessionReadRepository(boxes),
        sync,
        conn,
        prefs,
        storage,
      );
      await vm.initialize();
      expect(sync.activeSessionRef, isNull);

      await vm.sendMessage('typed in the reconnect identity window');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      var visible = (vm.state as ChatReady).messages.whereType<UserMsg>();
      expect(visible, hasLength(1), reason: 'the send must never be absent');
      expect(visible.single.status, UserMsgStatus.pending);
      expect(ch.sent.whereType<UserMessage>(), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      visible = (vm.state as ChatReady).messages.whereType<UserMsg>();
      expect(visible.single.status, UserMsgStatus.failed);

      ch.defaultSessionId = 'hydrated-session';
      ch.pushControl(
        const RoomsSnapshot(
          peer: 'epk_chat',
          rooms: [
            RoomInfo(
              roomId: 'main',
              sessionId: 'hydrated-session',
              startedAt: 2,
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final resent = ch.sent.whereType<UserMessage>().single;
      expect(resent.text, 'typed in the reconnect identity window');
      expect(resent.sessionId, 'hydrated-session');
      ch.push(UserInput(id: resent.id, text: resent.text));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      visible = (vm.state as ChatReady).messages.whereType<UserMsg>();
      expect(visible, hasLength(1));
      expect(visible.single.id, resent.id);
      expect(visible.single.status, UserMsgStatus.confirmed);

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'send confirmation survives route disposal and re-entry without duplication',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(
        conn,
        boxes,
        pendingSendTimeout: const Duration(milliseconds: 300),
      );
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
      await _adoptWithSession(conn, ch);

      final first = ChatViewModel(read, sync, conn, prefs, storage);
      await first.initialize();
      await first.sendMessage('survive navigation');
      final sent = ch.sent.whereType<UserMessage>().last;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((first.state as ChatReady).messages.map((message) => message.id), [
        sent.id,
      ]);
      first.dispose();

      final second = ChatViewModel(read, sync, conn, prefs, storage);
      await second.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        (second.state as ChatReady).messages.map((message) => message.id),
        [sent.id],
      );

      ch.push(UserInput(id: sent.id, text: sent.text));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(sync.debugPendingSendTimerCount, 0);
      expect((second.state as ChatReady).messages, hasLength(1));
      expect(
        (second.state as ChatReady).messages.single,
        isA<UserMsg>().having(
          (message) => message.status,
          'status',
          UserMsgStatus.confirmed,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 320));
      final rows = (second.state as ChatReady).messages.whereType<UserMsg>();
      expect(rows, hasLength(1));
      expect(rows.single.id, sent.id);
      expect(rows.single.status, UserMsgStatus.confirmed);

      second.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test('session-id rotation reloads an empty canonical message box', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final read = SessionReadRepository(boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

    await _adoptWithSession(conn, ch);
    final vm = ChatViewModel(read, sync, conn, prefs, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    ch.push(UserInput(id: 'old-u1', text: 'old session row'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      (vm.state as ChatReady).messages.whereType<UserMsg>().map((m) => m.text),
      contains('old session row'),
    );

    const rotatedSession = 'chat-session-rotated';
    ch.defaultSessionId = rotatedSession;
    ch.pushRaw(
      PairOk(
        inReplyTo: 'pair-rotated',
        sessionName: 'Pi',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: 'main',
        sessionId: rotatedSession,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      (vm.state as ChatReady).messages.whereType<UserMsg>().map((m) => m.text),
      isNot(contains('old session row')),
      reason: 'new canonical session must not render previous session rows',
    );

    ch.push(UserInput(id: 'new-u1', text: 'new session row'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      (vm.state as ChatReady).messages.whereType<UserMsg>().map((m) => m.text),
      ['new session row'],
    );

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test(
    'an empty session reaches ChatReady with no messages → the chat shows the '
    'default "Nothing here" placeholder (plan/32)',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      // Message boxes are keyed by canonical session id; each test session is
      // fresh, so "empty session" starts with an empty scoped box.
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      await _adoptWithSession(conn, ch);
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = vm.state;
      expect(state, isA<ChatReady>());
      state as ChatReady;
      // Empty + nothing streaming → _buildBody renders the default Pi-icon +
      // "Nothing here" placeholder (shown whenever the body is empty).
      expect(state.messages, isEmpty);
      expect(state.streaming, isNull);

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'matching-session authoritative idle suppresses stale StreamingBubble input',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final boxes = LocalBoxes();
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
      await _adoptWithSession(conn, ch);
      final sessionId = ch.defaultSessionId;
      final sync = _ProjectionSyncService(
        conn,
        boxes,
        RemoteSessionRef(
          peerEpk: _peer.remoteEpk,
          roomId: 'main',
          sessionId: sessionId,
        ),
      );
      final vm = ChatViewModel(
        SessionReadRepository(boxes),
        sync,
        conn,
        prefs,
        storage,
      );
      await vm.initialize();

      sync.emitTurn(
        TranscriptTurnView(
          status: AppTurnStatus.streaming,
          sessionId: sessionId,
          turnId: 'stale-turn',
          replyTo: 'stale-user',
        ),
      );
      sync.emitStreaming(
        const StreamingMessage(
          inReplyTo: 'stale-user',
          buffer: 'replayed residue',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final room = conn.roomTurnProjection(_peer.remoteEpk, 'main');
      expect(room.status, AppTurnStatus.idle);
      expect(room.sessionId, sessionId);
      final ready = vm.state as ChatReady;
      expect(ready.status.turn, AppTurnProjection.idle);
      expect(
        ready.streaming,
        isNull,
        reason: 'ChatPage must not receive input for a StreamingBubble',
      );

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'older-session idle preserves replacement-session StreamingBubble input',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final boxes = LocalBoxes();
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');
      await _adoptWithSession(conn, ch);
      final oldSessionId = ch.defaultSessionId;
      const replacementSessionId = 'replacement-live-session';
      final sync = _ProjectionSyncService(
        conn,
        boxes,
        const RemoteSessionRef(
          peerEpk: 'epk_chat',
          roomId: 'main',
          sessionId: replacementSessionId,
        ),
      );
      final vm = ChatViewModel(
        SessionReadRepository(boxes),
        sync,
        conn,
        prefs,
        storage,
      );
      await vm.initialize();

      sync.emitTurn(
        const TranscriptTurnView(
          status: AppTurnStatus.streaming,
          sessionId: replacementSessionId,
          turnId: 'replacement-turn',
          replyTo: 'replacement-user',
        ),
      );
      sync.emitStreaming(
        const StreamingMessage(
          inReplyTo: 'replacement-user',
          buffer: 'live replacement delta',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final room = conn.roomTurnProjection(_peer.remoteEpk, 'main');
      expect(room.status, AppTurnStatus.idle);
      expect(room.sessionId, oldSessionId);
      final ready = vm.state as ChatReady;
      expect(ready.status.turn.status, AppTurnStatus.streaming);
      expect(
        ready.streaming,
        const StreamingMessage(
          inReplyTo: 'replacement-user',
          buffer: 'live replacement delta',
        ),
      );

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test('working pill follows the relay per-room broadcast (same mechanism as '
      'Home) and the flip rebuilds the state (plan/32)', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
      emitDebounce: Duration.zero,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final read = SessionReadRepository(boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

    await _adoptWithSession(conn, ch);
    final vm = ChatViewModel(read, sync, conn, prefs, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Room comes online idle (no local turn started in THIS chat).
    ch.pushControl(
      RoomAnnounced(
        peer: 'epk_chat',
        roomId: 'main',
        sessionId: ch.defaultSessionId,
        startedAt: 1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.isWorking, isFalse);

    // The relay broadcasts meta.working=true for this room (turn_start) —
    // no local send/echo, purely the per-room signal that also drives Home.
    ch.pushControl(
      const RoomMetaUpdated(
        peer: 'epk_chat',
        roomId: 'main',
        working: true,
        hasModel: false,
        hasThinking: false,
        hasSessionId: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      vm.isWorking,
      isTrue,
      reason: 'relay per-room working drives the pill',
    );
    expect(
      (vm.state as ChatReady).isWorking,
      isTrue,
      reason: 'state carries isWorking so the flip rebuilds the UI',
    );

    // If the app sees agent_done but the relay's meta.working=false
    // broadcast is delayed/missed, the active chat must not stay stuck on
    // the stop button. The local channel observation clears the room flag.
    ch.push(AgentDone(inReplyTo: 'u1'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.isWorking, isFalse);
    expect((vm.state as ChatReady).isWorking, isFalse);

    // A later turn_end broadcast remains idempotent.
    ch.pushControl(
      const RoomMetaUpdated(
        peer: 'epk_chat',
        roomId: 'main',
        working: false,
        hasModel: false,
        hasThinking: false,
        hasSessionId: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.isWorking, isFalse);
    expect((vm.state as ChatReady).isWorking, isFalse);

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });
}
