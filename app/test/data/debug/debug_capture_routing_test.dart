import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _peerEpk = 'debug-peer-0001';

const _peer = PeerRecord(
  remoteEpk: _peerEpk,
  sessionName: 'Debug Pi',
  relayUrl: 'http://127.0.0.1:1',
  pairedAt: '2026-01-01T00:00:00Z',
  roomId: 'main',
);

final Set<DebugTag> _assertedRoutingTags = <DebugTag>{};

/// Every event ever asserted by _assertEvent, for the site-coverage registry
/// test to confirm each required capture site's discriminant actually matched
/// a recorded event (not just a tag mention).
final List<DebugEvent> _assertedSiteEvents = <DebugEvent>[];

class _FakeDebugLog implements DebugLog {
  final List<DebugEvent> events = <DebugEvent>[];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async => events.clear();

  @override
  void dispose() {}
}

class _FakeStorage extends PairingStorage {
  _FakeStorage([this.peers = const [_peer]]);

  final List<PeerRecord> peers;
  final Map<String, List<PersistedRoom>> savedRooms =
      <String, List<PersistedRoom>>{};

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord r) async {}

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {
    savedRooms[epk] = rooms;
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async =>
      savedRooms[epk] ?? const <PersistedRoom>[];
}

class _FakePeerTransport implements PeerTransport {
  final _frames = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  @override
  Future<Uint8List> receive() => _frames.stream.first;

  void push(Uint8List bytes) => _frames.add(bytes);

  @override
  Future<void> close() async {
    if (!_frames.isClosed) await _frames.close();
  }
}

class _FakeChannel implements IChannel, IControlLink {
  final _server = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = <ClientMessage>[];
  final List<Map<String, dynamic>> controls = <Map<String, dynamic>>[];
  Object? sendFailure;
  String defaultSessionId = '';

  @override
  Stream<ServerMessage> get serverMessages => _server.stream;

  @override
  Stream<ControlInbound> get controlFrames => _control.stream;

  @override
  Future<void> send(ClientMessage msg) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    sent.add(msg);
  }

  @override
  void sendControl(Map<String, dynamic> json) => controls.add(json);

  @override
  Future<void> close() async {
    if (!_server.isClosed) await _server.close();
    if (!_control.isClosed) await _control.close();
  }

  void push(ServerMessage m) => _server.add(_withDefaultSession(m));
  void pushRaw(ServerMessage m) => _server.add(m);
  void pushControl(ControlInbound frame) => _control.add(frame);

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
      SessionHistory(:final sessionId) when sessionId.isEmpty => SessionHistory(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        sessionStartedAt: m.sessionStartedAt,
        events: m.events,
        eos: m.eos,
        truncated: m.truncated,
      ),
      _ => m,
    };
  }
}

class _FailingCloseChannel extends _FakeChannel {
  @override
  Future<void> close() => Future<void>.error(StateError('close failed'));
}

late Directory _boxesDir;

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

T _assertEvent<T extends DebugEvent>(
  Iterable<DebugEvent> events,
  DebugTag tag, {
  bool Function(T event)? where,
}) {
  final event = events.whereType<T>().firstWhere(
    (event) => where?.call(event) ?? true,
    orElse: () => throw TestFailure('No $T event found for $tag'),
  );
  expect(event.tag, tag);
  _assertedRoutingTags.add(tag);
  _assertedSiteEvents.add(event);
  return event;
}

List<DebugTag> _tags(Iterable<DebugEvent> events) =>
    events.map((event) => event.tag).toList(growable: false);

Future<({ConnectionManager conn, _FakeChannel channel, _FakeDebugLog log})>
_connectedManager() async {
  final log = _FakeDebugLog();
  final channel = _FakeChannel();
  final conn = ConnectionManager(
    factory: (_, _) async => channel,
    storage: _FakeStorage(),
    debugLog: log,
    emitDebounce: Duration.zero,
  );
  conn.subscribeToPeers(const [_peerEpk]);
  await conn.boot(preferredEpk: _peerEpk);
  await _settle();
  return (conn: conn, channel: channel, log: log);
}

Future<
  ({
    ConnectionManager conn,
    _FakeChannel channel,
    SyncService sync,
    _FakeDebugLog log,
    String sessionId,
  })
>
_syncHarness({
  Duration pendingSendTimeout = const Duration(seconds: 20),
  Duration emitDebounce = Duration.zero,
}) async {
  final log = _FakeDebugLog();
  final channel = _FakeChannel();
  const sessionId = 'debug-session-0001';
  channel.defaultSessionId = sessionId;
  final conn = ConnectionManager(
    factory: (_, _) async => channel,
    storage: _FakeStorage(),
    debugLog: log,
    emitDebounce: emitDebounce,
  );
  final sync = SyncService(
    conn,
    LocalBoxes(),
    debugLog: log,
    pendingSendTimeout: pendingSendTimeout,
  );
  conn.adopt(channel, _peer);
  channel.pushRaw(
    PairOk(
      inReplyTo: 'pair-debug',
      sessionName: 'Debug Pi',
      sessionStartedAt: 1,
      roomId: 'main',
      sessionId: sessionId,
    ),
  );
  await _settle();
  await sync.activate(_peerEpk, 'main');
  await _settle();
  final routeEvents = log.events.whereType<RouteEvent>().toList();
  log.events
    ..clear()
    ..addAll(routeEvents);
  return (
    conn: conn,
    channel: channel,
    sync: sync,
    log: log,
    sessionId: sessionId,
  );
}

Future<({HttpServer server, Uri uri})> _startRelayProbeServer({
  required List<String> postAuthFrames,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    var count = 0;
    socket.listen((raw) {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      count += 1;
      if (count == 1 && frame['type'] == 'hello') {
        socket.add(
          jsonEncode({
            'type': 'challenge',
            'nonce': base64.encode(List<int>.generate(32, (index) => index)),
          }),
        );
        return;
      }
      if (count == 2 && frame['type'] == 'auth') {
        for (final out in postAuthFrames) {
          socket.add(out);
        }
      }
    });
  });
  return (server: server, uri: Uri.parse('http://127.0.0.1:${server.port}'));
}

void main() {
  setUpAll(() async {
    _boxesDir = Directory.systemTemp.createTempSync('rp_debug_capture_');
    await LocalBoxes.initForTest(_boxesDir.path);
  });

  setUp(() async {
    await LocalBoxes().ownerDeliveryOutboxBox().clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await _boxesDir.delete(recursive: true);
  });

  test('WsTransport routes inbound frame probes through DebugLog', () async {
    final log = _FakeDebugLog();
    final payload = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final relay = await _startRelayProbeServer(
      postAuthFrames: <String>[
        jsonEncode({
          'peer': 'peer-a',
          'room': 'main',
          'ct': base64.encode(payload),
        }),
      ],
    );
    final keyPair = await Ed25519().newKeyPair();

    final transport = await WsTransport.connect(
      relayUrl: relay.uri.toString(),
      peerPubkey: 'peer-a',
      ed25519Key: keyPair,
      deviceId: 'test-device',
      debugLog: log,
    );
    expect(await transport.receive(), payload);
    await _settle();

    final preauth = _assertEvent<WsInEvent>(
      log.events,
      DebugTag.wsIn,
      where: (event) => event.stage == 'preauth' && event.bytes != null,
    );
    expect(preauth.kind, 'preauth');
    final envelope = _assertEvent<WsInEvent>(
      log.events,
      DebugTag.wsIn,
      where: (event) => event.kind == 'envelope' && event.stage == 'enqueue',
    );
    expect(envelope.bytes, payload.length);

    await transport.close();
    await relay.server.close(force: true);
  });

  test(
    'WsTransport routes every ws-in dropped/control branch through DebugLog',
    () async {
      final log = _FakeDebugLog();
      // Active room is 'main' — frames targeting other rooms or missing a
      // room hit the drop branches; unrecognized frames hit malformed.
      final relay = await _startRelayProbeServer(
        postAuthFrames: <String>[
          // dropMissingRoom — envelope without a room field.
          jsonEncode({
            'peer': 'peer-a',
            'ct': base64.encode(Uint8List.fromList([9, 9, 9])),
          }),
          // dropRoomMismatch — envelope with a non-active room.
          jsonEncode({
            'peer': 'peer-a',
            'room': 'other-room',
            'ct': base64.encode(Uint8List.fromList([8, 8, 8])),
          }),
          // control accepted — a real control frame (peer_online).
          jsonEncode({'type': 'peer_online', 'peer': 'peer-a'}),
          // control dropped malformed — a control-typed frame whose body
          // ControlInbound.tryFromJson rejects (presence requires `states`).
          jsonEncode({'type': 'presence', 'peer': 'peer-a'}),
          // envelope dropped malformed — has peer+ct but ct is not valid
          // base64, so _b64Decode throws inside demux.
          jsonEncode({'peer': 'peer-a', 'room': 'main', 'ct': '!!!notb64'}),
          // malformed — no peer/ct and not a control frame.
          jsonEncode({'type': 'unknown_garbage', 'foo': 'bar'}),
        ],
      );
      final keyPair = await Ed25519().newKeyPair();

      final transport = await WsTransport.connect(
        relayUrl: relay.uri.toString(),
        peerPubkey: 'peer-a',
        ed25519Key: keyPair,
        deviceId: 'test-device',
        debugLog: log,
      );
      // Receive the one enqueueable frame — there is none in this batch
      // (all are dropped/control/malformed), so drain briefly.
      await _settle();
      await _settle();

      _assertEvent<WsInEvent>(
        log.events,
        DebugTag.wsIn,
        where: (event) =>
            event.kind == 'envelope' && event.stage == 'missing-room',
      );
      _assertEvent<WsInEvent>(
        log.events,
        DebugTag.wsIn,
        where: (event) =>
            event.kind == 'envelope' &&
            event.stage == 'room-mismatch' &&
            event.senderRoom == 'other-room',
      );
      _assertEvent<WsInEvent>(
        log.events,
        DebugTag.wsIn,
        where: (event) => event.kind == 'control' && event.stage == 'accepted',
      );
      // The control-typed-but-malformed frame (presence without states) and
      // the bad-base64 envelope both throw inside demux → dropMalformed →
      // the `malformed` kind/stage=dropped path (NOT a control/envelope
      // dropped_malformed branch — those were unreachable dead code, removed
      // during review). Assert at least two malformed events land.
      final malformed = log.events.whereType<WsInEvent>().where(
        (event) => event.kind == 'malformed' && event.stage == 'dropped',
      );
      expect(
        malformed.length,
        greaterThanOrEqualTo(2),
        reason:
            'Expected ≥2 malformed events (bad control + bad envelope); '
            'got ${malformed.length}',
      );
      _assertEvent<WsInEvent>(
        log.events,
        DebugTag.wsIn,
        where: (event) => event.kind == 'malformed' && event.stage == 'dropped',
      );

      await transport.close();
      await relay.server.close(force: true);
    },
  );

  // Regression for `story-fix-transport-active-room-reestablishment-on-reconnect`.
  // The relay may push envelopes immediately after auth, before the caller
  // can call `setActiveRoom`. Previously the transport defaulted to 'main'
  // and demuxed those frames against 'main', dropping any targeting the
  // real room as `room-mismatch`. Constructing the transport with the real
  // `activeRoom` from `connect` eliminates that race from frame 1.
  test(
    'WsTransport demuxes post-auth frames against the construction activeRoom',
    () async {
      final log = _FakeDebugLog();
      const realRoom = '7ADky8889NJy';
      final payload = Uint8List.fromList(<int>[5, 6, 7, 8]);
      final relay = await _startRelayProbeServer(
        postAuthFrames: <String>[
          jsonEncode({
            'peer': 'peer-a',
            'room': realRoom,
            'ct': base64.encode(payload),
          }),
        ],
      );
      final keyPair = await Ed25519().newKeyPair();

      final transport = await WsTransport.connect(
        relayUrl: relay.uri.toString(),
        peerPubkey: 'peer-a',
        ed25519Key: keyPair,
        deviceId: 'test-device',
        activeRoom: realRoom,
        debugLog: log,
      );
      // The first post-auth frame targets `realRoom`; under the old
      // default-'main' it would be dropped as room-mismatch. With the
      // construction room it must enqueue and be receivable.
      expect(await transport.receive(), payload);

      final envelope = _assertEvent<WsInEvent>(
        log.events,
        DebugTag.wsIn,
        where: (event) => event.kind == 'envelope' && event.stage == 'enqueue',
      );
      expect(envelope.bytes, payload.length);
      final mismatch = log.events.whereType<WsInEvent>().where(
        (event) => event.kind == 'envelope' && event.stage == 'room-mismatch',
      );
      expect(
        mismatch,
        isEmpty,
        reason:
            'A frame targeting the construction activeRoom must not be '
            'dropped as room-mismatch. This is the reconnect reorder bug: '
            'the transport defaulted to \'main\' and dropped real-room '
            'envelopes pushed before setActiveRoom could run.',
      );

      await transport.close();
      await relay.server.close(force: true);
    },
  );

  test(
    'ConnectionManager marks the active room offline after 3 missed pings',
    () {
      fakeAsync((async) {
        final log = _FakeDebugLog();
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: _FakeStorage(),
          debugLog: log,
          emitDebounce: Duration.zero,
          // Short interval so the missed-ping → _markActiveRoomOffline path
          // is exercisable inside FakeAsync without real-time waits. This
          // tests the real _startPing timer + missedPings counter +
          // _markActiveRoomOffline emission, not a test-only seam.
          pingInterval: const Duration(milliseconds: 50),
        );
        conn.subscribeToPeers(const [_peerEpk]);
        // boot drives an async connect; flush microtasks so it completes.
        // ignore: discarded_futures
        conn.boot(preferredEpk: _peerEpk);
        async.flushMicrotasks();
        async.flushMicrotasks();

        // Bring the room live so _markActiveRoomOffline actually fires its
        // event (it early-returns when the room isn't live).
        channel.pushControl(
          const RoomAnnounced(
            peer: _peerEpk,
            roomId: 'main',
            sessionId: 'debug-session-0001',
            startedAt: 1,
            working: true,
          ),
        );
        async.flushMicrotasks();
        log.events.clear();

        // Three ping cycles, each advancing past the 50ms interval and
        // flushing the async ping callback (which calls onPingMissed and,
        // on the 3rd, _markActiveRoomOffline). The channel never sends a
        // Pong, so missedPings climbs to 3.
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();

        final offline = _assertEvent<WorkingConvEvent>(
          log.events,
          DebugTag.workingConv,
          where: (event) =>
              event.room == 'main' &&
              event.working == false &&
              event.reason == 'ping_missed_room_offline',
        );
        expect(offline.room, 'main');

        conn.dispose();
      });
    },
  );

  test(
    'ConnectionManager emits reconnect, hydrate, room snapshot, and working convergence events',
    () async {
      final s = await _connectedManager();

      // Connection lifecycle events fired during _connectedManager setup
      // (connecting → online → hydrate). Assert them against the full event
      // log before clearing for the per-phase room-snapshot assertions below.
      expect(_tags(s.log.events).take(3), <DebugTag>[
        DebugTag.connStatus,
        DebugTag.connStatus,
        DebugTag.connHydrate,
      ]);
      final connecting = _assertEvent<ConnStatusEvent>(
        s.log.events,
        DebugTag.connStatus,
        where: (event) => event.status == 'connecting',
      );
      expect(connecting.room, 'main');
      _assertEvent<ConnStatusEvent>(
        s.log.events,
        DebugTag.connStatus,
        where: (event) => event.status == 'online',
      );
      final hydrate = _assertEvent<ConnHydrateEvent>(
        s.log.events,
        DebugTag.connHydrate,
      );
      expect(hydrate.action, 'replay_subscriptions');
      expect(hydrate.snapshotCount, 1);

      // Phase 1 — RoomAnnounced brings the room live with working=true.
      s.log.events.clear();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: _peerEpk,
          roomId: 'main',
          sessionId: 'debug-session-0001',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();
      _assertEvent<RoomSnapshotEvent>(
        s.log.events,
        DebugTag.roomSnapshot,
        where: (event) =>
            event.room == 'main' &&
            event.working == true &&
            event.presenceCount == null,
      );

      // Phase 2 — markRoomWorking(false) flips the dot (mark_room_working).
      s.log.events.clear();
      s.conn.markRoomWorking(
        _peerEpk,
        'main',
        false,
        sessionId: 'debug-session-0001',
        turnId: null,
      );
      await _settle();
      final working = _assertEvent<WorkingConvEvent>(
        s.log.events,
        DebugTag.workingConv,
        where: (event) => event.room == 'main' && event.working == false,
      );
      expect(working.reason, 'mark_room_working');

      // Phase 3 — RoomMetaUpdated flips working back to true. This is a real
      // change (current is false), so the case emits rather than dedup-
      // breaking on the nothing-changed branch.
      s.log.events.clear();
      s.channel.pushControl(
        const RoomMetaUpdated(
          peer: _peerEpk,
          roomId: 'main',
          working: true,
          hasModel: false,
          hasThinking: false,
          hasSessionId: false,
        ),
      );
      await _settle();
      _assertEvent<RoomSnapshotEvent>(
        s.log.events,
        DebugTag.roomSnapshot,
        where: (event) =>
            event.room == 'main' &&
            event.working == true &&
            event.presenceCount == null,
      );

      // Phase 4 — RoomsSnapshot carries presenceCount for the batch entry.
      s.log.events.clear();
      s.channel.pushControl(
        const RoomsSnapshot(
          peer: _peerEpk,
          rooms: <RoomInfo>[
            RoomInfo(roomId: 'main', startedAt: 2, working: false),
          ],
        ),
      );
      await _settle();
      _assertEvent<RoomSnapshotEvent>(
        s.log.events,
        DebugTag.roomSnapshot,
        where: (event) =>
            event.room == 'main' &&
            event.presenceCount == 1 &&
            event.working == false,
      );

      s.conn.dispose();
    },
  );

  test(
    'ConnectionManager routes close failure through lifecycle diagnostics',
    () async {
      final log = _FakeDebugLog();
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
        debugLog: log,
      );
      conn.adopt(_FailingCloseChannel(), _peer);
      conn.adopt(_FakeChannel(), _peer);
      await _settle();

      final failure = _assertEvent<LifecycleFailureEvent>(
        log.events,
        DebugTag.lifecycleFailure,
        where: (event) => event.operation == LifecycleOperation.channelClose,
      );
      expect(failure.reason, 'StateError');
      expect(failure.retryScheduled, isFalse);

      conn.dispose();
    },
  );

  test(
    'ConnectionManager distinguishes stale takeover close from real channel loss',
    () async {
      final s = await _connectedManager();
      final current = s.channel;
      final stale = _FakeChannel();

      s.conn.debugSimulateChannelLost(stale);
      await _settle();

      final staleEvent = _assertEvent<ConnChannelLostEvent>(
        s.log.events,
        DebugTag.connChannelLost,
        where: (event) => event.stale == true,
      );
      expect(staleEvent.room, 'main');
      expect(s.conn.status, isA<StatusOnline>());
      expect(
        s.log.events.whereType<ConnStatusEvent>().where(
          (event) => event.status == 'retrying',
        ),
        isEmpty,
        reason: 'stale replaced-channel close must not start retry',
      );

      final fresh = _FakeChannel();
      s.conn.adopt(fresh, _peer);
      await _settle();
      _assertEvent<ConnStatusEvent>(
        s.log.events,
        DebugTag.connStatus,
        where: (event) => event.status == 'online',
      );

      s.conn.debugSimulateChannelLost(fresh);
      await _settle();

      final realLoss = _assertEvent<ConnChannelLostEvent>(
        s.log.events,
        DebugTag.connChannelLost,
        where: (event) => event.stale == false,
      );
      expect(realLoss.room, 'main');
      final retry = _assertEvent<ConnStatusEvent>(
        s.log.events,
        DebugTag.connStatus,
        where: (event) => event.status == 'retrying',
      );
      expect(retry.attempt, greaterThanOrEqualTo(0));
      expect(retry.delayMs, greaterThan(0));

      expect(current, isNot(s.conn.channel));
      s.conn.dispose();
    },
  );

  test(
    'SyncService emits send preview, echo, gate, failure, session-sync, and replay-dedup events',
    () async {
      final s = await _syncHarness(
        pendingSendTimeout: const Duration(seconds: 5),
      );
      _assertEvent<RouteEvent>(
        s.log.events,
        DebugTag.route,
        where: (event) => event.phase == RoutePhase.entry,
      );
      _assertEvent<RouteEvent>(
        s.log.events,
        DebugTag.route,
        where: (event) => event.phase == RoutePhase.projectionEmpty,
      );
      final longText = '${'x' * 90} trailing body that must not be persisted';

      await s.sync.sendMessage(longText);
      await _settle();
      final sent = s.channel.sent.whereType<UserMessage>().single;
      s.channel.push(UserInput(id: sent.id, text: longText));
      await _settle();

      final msgSend = _assertEvent<MsgSendEvent>(
        s.log.events,
        DebugTag.msgSend,
        where: (event) => event.id == sent.id,
      );
      expect(msgSend.blocked, isFalse);
      // The diagnostic MsgSendEvent carries no user-text preview (redaction
      // contract): the event records only id + blocked, never the message body.
      expect(msgSend.toJson(), isNot(contains('preview')));
      expect(msgSend.toJson().values, isNot(contains(longText)));
      final echo = _assertEvent<MsgEchoEvent>(
        s.log.events,
        DebugTag.msgEcho,
        where: (event) => event.id == sent.id,
      );
      expect(echo.id, sent.id);

      s.channel.pushRaw(
        const AgentChunk(
          sessionId: 'foreign-session-9999',
          inReplyTo: 'u1',
          delta: 'drop',
        ),
      );
      await _settle();
      final gate = _assertEvent<SessionGateEvent>(
        s.log.events,
        DebugTag.sessionGate,
        where: (event) => event.reason == 'session_mismatch',
      );
      expect(gate.messageType, 'agent_chunk');
      expect(gate.sessionIdTail, 'ion-9999');

      s.channel.sendFailure = StateError(
        'socket write refused with verbose detail ${'z' * 200}',
      );
      await s.sync.sendMessage('will fail');
      await _settle();
      final failed = _assertEvent<MsgFailedEvent>(
        s.log.events,
        DebugTag.msgFailed,
      );
      expect(failed.code, 'send_error');
      expect(failed.toJson().keys, isNot(contains('detail')));
      _assertEvent<SendQueueEvent>(
        s.log.events,
        DebugTag.sendQueue,
        where: (event) =>
            event.id == failed.id && event.phase == SendQueuePhase.visibleFail,
      );

      s.sync.requestSync();
      await _settle();
      final sync = _assertEvent<SessionSyncEvent>(
        s.log.events,
        DebugTag.sessionSync,
      );
      expect(sync.toJson().keys, isNot(contains('err')));

      s.channel.sendFailure = null;
      final history = SessionHistory(
        sessionId: s.sessionId,
        inReplyTo: 'history-1',
        sessionStartedAt: 10,
        events: const <SessionHistoryEvent>[
          UserInputEvt(ts: 1, id: 'replay-u1', text: 'hello'),
        ],
        eos: true,
      );
      s.channel.pushRaw(history);
      await _settle();
      s.channel.pushRaw(history);
      await _settle();
      _assertEvent<ReplayDedupEvent>(
        s.log.events,
        DebugTag.replayDedup,
        where: (event) =>
            event.sessionId == s.sessionId && event.dropped == false,
      );
      _assertEvent<ReplayDedupEvent>(
        s.log.events,
        DebugTag.replayDedup,
        where: (event) =>
            event.sessionId == s.sessionId && event.dropped == true,
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'SyncService disarms resumed-session echoes rejected by the transcript gate',
    () async {
      final s = await _syncHarness(
        pendingSendTimeout: const Duration(milliseconds: 500),
        emitDebounce: const Duration(milliseconds: 200),
      );

      await s.sync.sendMessage('resume race');
      await _settle();
      final sent = s.channel.sent.whereType<UserMessage>().single;
      final staleRef = s.sync.activeSessionRef!;
      expect(s.sync.debugPendingSendTimerCount, 1, reason: 'timer armed');

      const resumedSessionId = 'debug-session-0002';
      s.channel.pushControl(
        const RoomMetaUpdated(
          peer: _peerEpk,
          roomId: 'main',
          sessionId: resumedSessionId,
          hasModel: false,
          hasThinking: false,
          hasSessionId: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      s.channel.pushRaw(
        UserInput(
          id: sent.id,
          sessionId: resumedSessionId,
          text: 'resume race',
        ),
      );
      await _settle();

      final gate = _assertEvent<SessionGateEvent>(
        s.log.events,
        DebugTag.sessionGate,
        where: (event) =>
            event.messageType == 'user_input' &&
            event.reason == 'session_mismatch',
      );
      expect(gate.sessionIdTail, 'ion-0002');
      _assertEvent<MsgEchoEvent>(
        s.log.events,
        DebugTag.msgEcho,
        where: (event) => event.id == sent.id,
      );
      expect(
        s.sync.debugPendingSendTimerCount,
        0,
        reason: 'gate-rejected echo still proves delivery and disarms timer',
      );

      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _settle();
      expect(
        s.log.events.whereType<MsgFailedEvent>().where(
          (event) => event.id == sent.id && event.code == 'send_timeout',
        ),
        isEmpty,
        reason: 'the disarmed no-echo timer must not create a failure badge',
      );

      final box = LocalBoxes().openMsgsBox(staleRef);
      final rows =
          ([
                for (final value in box.values)
                  MessageRecord.fromJson(
                    (value as Map).cast<String, dynamic>(),
                  ),
              ]..sort((a, b) => a.seq.compareTo(b.seq)))
              .where((row) => row.id == sent.id)
              .toList(growable: false);
      expect(rows, hasLength(1));
      expect(rows.single.role, MsgRole.user);
      expect(
        rows.single.status,
        isNot(UserMsgStatus.failed),
        reason: 'the user bubble must not show the not-delivered badge',
      );
      expect(
        rows.single.pending,
        isTrue,
        reason:
            'the gate still rejects transcript acceptance; the stale-session '
            'echo is not appended as a confirmed row',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'SyncService replay-dedup reports within-batch duplicate eventIds as dropped',
    () async {
      // Regression test for the [I1] bug: the OLD dropped derivation
      // checked only against IDs that pre-existed in the store before
      // appendAll. A SessionHistory containing the SAME eventId twice would
      // log dropped:false for BOTH occurrences (since neither pre-existed),
      // even though appendAll skips the second. The fix tracks a mutable
      // seenEventIds set across the batch so the second occurrence logs
      // dropped:true. This test would pass under the old logic (both false)
      // only if the bug were present; it asserts the second is true, so it
      // FAILS under the old logic — that's the teeth.
      final s = await _syncHarness(
        pendingSendTimeout: const Duration(seconds: 5),
      );
      const dupId = 'replay-dup-1';
      const dupTs = 5;
      // Both facts share the SDK timestamp identity used across Pi process
      // replacement, so durable admission derives one event id for both.
      final history = SessionHistory(
        sessionId: s.sessionId,
        inReplyTo: 'history-dup',
        sessionStartedAt: 20,
        events: const <SessionHistoryEvent>[
          // Same id AND same ts → serverReplayEventId produces the SAME
          // eventId for both, so appendAll skips the second (box.containsKey).
          UserInputEvt(ts: dupTs, id: dupId, text: 'first'),
          UserInputEvt(ts: dupTs, id: dupId, text: 'second (duplicate)'),
        ],
        eos: true,
      );
      s.log.events.clear();
      s.channel.pushRaw(history);
      await _settle();

      final dupEvents = s.log.events.whereType<ReplayDedupEvent>().toList();
      expect(
        dupEvents.length,
        2,
        reason: 'Both within-batch duplicates must emit a ReplayDedupEvent.',
      );
      expect(
        dupEvents.first.dropped,
        isFalse,
        reason: 'First occurrence is new → not dropped.',
      );
      expect(
        dupEvents.last.dropped,
        isTrue,
        reason:
            'Second occurrence is a within-batch duplicate → must be dropped. '
            'Under the OLD logic this was false (the bug).',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'SyncService emits offline held-pending msg-send when channel is unavailable',
    () async {
      final s = await _syncHarness();

      final retrying = s.conn.statusStream.firstWhere(
        (status) => status is StatusRetrying,
      );
      await s.channel.close();
      await retrying;
      await _settle();
      s.log.events.clear();
      await s.sync.sendMessage('held while offline');
      await _settle();

      final blocked = _assertEvent<MsgSendEvent>(
        s.log.events,
        DebugTag.msgSend,
        where: (event) => event.blocked == true,
      );
      expect(blocked.id, startsWith('cli_'));
      // No preview field on the diagnostic event (redaction contract).
      expect(blocked.toJson(), isNot(contains('preview')));
      _assertEvent<SendQueueEvent>(
        s.log.events,
        DebugTag.sendQueue,
        where: (event) =>
            event.id == blocked.id && event.phase == SendQueuePhase.held,
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'SyncService emits blocked msg-send when session identity is unavailable',
    () async {
      final log = _FakeDebugLog();
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(const <PeerRecord>[]),
        debugLog: log,
      );
      final sync = SyncService(conn, LocalBoxes(), debugLog: log);

      await sync.sendMessage('blocked');
      await _settle();

      final blocked = _assertEvent<MsgSendEvent>(
        log.events,
        DebugTag.msgSend,
        where: (event) => event.blocked == true,
      );
      // No preview field on the diagnostic event (redaction contract).
      expect(blocked.toJson(), isNot(contains('preview')));

      conn.dispose();
      sync.dispose();
    },
  );

  test(
    'PeerChannel logs unsupported server frame types without payload',
    () async {
      final log = _FakeDebugLog();
      final transport = _FakePeerTransport();
      final channel = PlainPeerChannel(transport: transport, debugLog: log);
      final received = channel.serverMessages.first;
      await Future<void>.delayed(Duration.zero);

      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'type': 'future_server_type',
            'body': 'full payload must not be logged',
            'ct': 'ciphertext must not be logged',
          }),
        ),
      );
      transport.push(bytes);

      final msg = await received;
      expect(msg, isA<ErrorMessage>());
      final event = _assertEvent<PeerFrameEvent>(
        log.events,
        DebugTag.peerFrame,
        where: (event) => event.kind == 'unsupported_type',
      );
      expect(event.bytes, bytes.length);
      expect(event.error, isNull);
      final json = event.toJson();
      expect(json['kind'], 'unsupported_type');
      expect(json['bytes'], bytes.length);
      expect(json.keys, isNot(contains('body')));
      expect(json.keys, isNot(contains('ct')));
      expect(json.keys, isNot(contains('message')));
      expect(json.keys, isNot(contains('data')));

      await channel.close();
    },
  );

  test('PeerChannel logs malformed frames without payload', () async {
    final log = _FakeDebugLog();
    final transport = _FakePeerTransport();
    final channel = PlainPeerChannel(transport: transport, debugLog: log);
    final sub = channel.serverMessages.listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final bytes = Uint8List.fromList(utf8.encode('{"type":'));
    transport.push(bytes);
    await _settle();

    final event = _assertEvent<PeerFrameEvent>(
      log.events,
      DebugTag.peerFrame,
      where: (event) => event.kind == 'malformed',
    );
    expect(event.bytes, bytes.length);
    expect(event.error, isNotNull);
    expect(event.error!.length, lessThanOrEqualTo(120));
    expect(event.error, isNot(contains('{"type"')));
    final json = event.toJson();
    expect(json['kind'], 'malformed');
    expect(json['bytes'], bytes.length);
    expect(json.keys, isNot(contains('body')));
    expect(json.keys, isNot(contains('ct')));
    expect(json.keys, isNot(contains('message')));
    expect(json.keys, isNot(contains('data')));

    await sub.cancel();
    await channel.close();
  });

  test('every required capture site has an asserted routing test', () {
    // Tag coverage is necessary but not sufficient: a single assertion per
    // tag can pass even if several distinct capture sites (ws-in dropped
    // branches, RoomMetaUpdated, RoomsSnapshot, _markActiveRoomOffline)
    // silently stop emitting. This guard tracks the specific sites the
    // feature design (Unit 4) requires, each asserted via a real
    // _assertEvent emission above. Deleting any required emission above
    // must fail its corresponding site here.
    //
    // Each entry is (tag, siteName, discriminant) where the discriminant
    // identifies THAT capture site's emitted event shape and was asserted
    // by a real _assertEvent call in the tests above. The tag is enforced
    // separately: a discriminant match against an event of the wrong tag
    // does not count. For the one case where two branches emit the same
    // shape (RoomAnnounced + RoomMetaUpdated), the per-phase test with
    // events.clear() between phases is the real proof both fired; the
    // registry backstops that the shape was seen at all.
    final requiredSites = <(DebugTag, String, bool Function(DebugEvent))>[
      // ws-in branches (Unit 4a) — preauth + enqueue asserted in the probe
      // test; the dropped branches (missing-room/room-mismatch/control/
      // malformed) are asserted in the dedicated dropped-frames test.
      (DebugTag.wsIn, 'preauth', (e) => e is WsInEvent && e.stage == 'preauth'),
      (
        DebugTag.wsIn,
        'envelope-enqueue',
        (e) => e is WsInEvent && e.kind == 'envelope' && e.stage == 'enqueue',
      ),
      (
        DebugTag.wsIn,
        'drop-missing-room',
        (e) =>
            e is WsInEvent && e.stage == 'missing-room' && e.kind == 'envelope',
      ),
      (
        DebugTag.wsIn,
        'drop-room-mismatch',
        (e) =>
            e is WsInEvent &&
            e.stage == 'room-mismatch' &&
            e.kind == 'envelope',
      ),
      (
        DebugTag.wsIn,
        'control-accepted',
        (e) => e is WsInEvent && e.kind == 'control' && e.stage == 'accepted',
      ),
      (
        DebugTag.wsIn,
        'malformed',
        (e) => e is WsInEvent && e.kind == 'malformed' && e.stage == 'dropped',
      ),
      // peer-channel inner frame drops (Unit 6).
      (
        DebugTag.peerFrame,
        'unsupported-type',
        (e) => e is PeerFrameEvent && e.kind == 'unsupported_type',
      ),
      (
        DebugTag.peerFrame,
        'malformed',
        (e) => e is PeerFrameEvent && e.kind == 'malformed',
      ),
      // conn-status branches (Unit 4b).
      (
        DebugTag.connStatus,
        'connecting',
        (e) => e is ConnStatusEvent && e.status == 'connecting',
      ),
      (
        DebugTag.connStatus,
        'online',
        (e) => e is ConnStatusEvent && e.status == 'online',
      ),
      (
        DebugTag.connStatus,
        'retrying',
        (e) => e is ConnStatusEvent && e.status == 'retrying',
      ),
      // conn-channel-lost both branches (the takeover proof).
      (
        DebugTag.connChannelLost,
        'stale-true',
        (e) => e is ConnChannelLostEvent && e.stale == true,
      ),
      (
        DebugTag.connChannelLost,
        'stale-false',
        (e) => e is ConnChannelLostEvent && e.stale == false,
      ),
      // conn-hydrate — discriminant on the real action field.
      (
        DebugTag.connHydrate,
        'replay-subscriptions',
        (e) => e is ConnHydrateEvent && e.action == 'replay_subscriptions',
      ),
      // room-snapshot: RoomAnnounced and RoomMetaUpdated emit the same
      // RoomSnapshotEvent shape, so a single discriminant can't distinguish
      // them. The per-phase reconnect test (with events.clear() between
      // phases) is the real proof both branches fired; this registry entry
      // backstops that the shape was seen at all. RoomsSnapshot is
      // distinguishable by presenceCount.
      (
        DebugTag.roomSnapshot,
        'room-announced-or-meta-updated',
        (e) =>
            e is RoomSnapshotEvent &&
            e.presenceCount == null &&
            e.working == true,
      ),
      (
        DebugTag.roomSnapshot,
        'rooms-snapshot',
        (e) => e is RoomSnapshotEvent && e.presenceCount == 1,
      ),
      // working-conv both branches (markRoomWorking + _markActiveRoomOffline).
      (
        DebugTag.workingConv,
        'mark-room-working',
        (e) => e is WorkingConvEvent && e.reason == 'mark_room_working',
      ),
      (
        DebugTag.workingConv,
        'ping-missed-room-offline',
        (e) => e is WorkingConvEvent && e.reason == 'ping_missed_room_offline',
      ),
      // sync_service sites.
      (
        DebugTag.msgSend,
        'send-with-preview',
        (e) => e is MsgSendEvent && e.blocked == false,
      ),
      (
        DebugTag.msgSend,
        'blocked-offline',
        (e) => e is MsgSendEvent && e.blocked == true,
      ),
      (
        DebugTag.msgSend,
        'blocked-no-session',
        (e) => e is MsgSendEvent && e.blocked == true,
      ),
      (DebugTag.msgEcho, 'echo', (e) => e is MsgEchoEvent && e.id.isNotEmpty),
      (
        DebugTag.msgFailed,
        'send-error',
        (e) => e is MsgFailedEvent && e.code == 'send_error',
      ),
      (
        DebugTag.sendQueue,
        'held',
        (e) => e is SendQueueEvent && e.phase == SendQueuePhase.held,
      ),
      (
        DebugTag.sendQueue,
        'visible-fail',
        (e) => e is SendQueueEvent && e.phase == SendQueuePhase.visibleFail,
      ),
      (
        DebugTag.route,
        'entry',
        (e) => e is RouteEvent && e.phase == RoutePhase.entry,
      ),
      (
        DebugTag.route,
        'projection-empty',
        (e) => e is RouteEvent && e.phase == RoutePhase.projectionEmpty,
      ),
      (
        DebugTag.sessionGate,
        'session-mismatch',
        (e) => e is SessionGateEvent && e.reason == 'session_mismatch',
      ),
      (DebugTag.sessionSync, 'request-failed', (e) => e is SessionSyncEvent),
      (
        DebugTag.lifecycleFailure,
        'channel-close',
        (e) =>
            e is LifecycleFailureEvent &&
            e.operation == LifecycleOperation.channelClose,
      ),
      // replay-dedup both dropped=false (new) and dropped=true (dedup).
      (
        DebugTag.replayDedup,
        'new',
        (e) => e is ReplayDedupEvent && e.dropped == false,
      ),
      (
        DebugTag.replayDedup,
        'dropped',
        (e) => e is ReplayDedupEvent && e.dropped == true,
      ),
    ];

    // Every required site must have an event that was asserted by a real
    // _assertEvent call (recorded in _assertedSiteEvents) AND whose
    // discriminant matches an event of the correct tag. Requiring the
    // discriminant to match a *recorded* event of the right tag — not just
    // a tag mention — means deleting any required emission above fails the
    // registry. (For RoomAnnounced/RoomMetaUpdated which share a shape, the
    // per-phase reconnect test with events.clear() is the real proof both
    // fired; the registry backstops that the shape was seen.)
    final recordedEvents = _assertedSiteEvents;
    for (final (tag, siteName, matches) in requiredSites) {
      final matching = recordedEvents.where((e) => e.tag == tag && matches(e));
      expect(
        matching,
        isNotEmpty,
        reason:
            'Required capture site $tag/$siteName has no recorded event '
            'of the right tag matching its discriminant — a required '
            'emission may be missing or the test is wrong.',
      );
    }
    // Backstop: every DebugTag must still appear (catches a tag with no
    // required sites at all).
    expect(
      requiredSites.map((s) => s.$1).toSet(),
      containsAll(DebugTag.values),
      reason: 'Every DebugTag must have at least one required capture site.',
    );
  });
}
