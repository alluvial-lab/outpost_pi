import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _peer = PeerRecord(
  remoteEpk: 'epk_projection',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [_peer];

  @override
  Future<void> savePeer(PeerRecord r) async {}

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => const [];
}

class _ControlledStorage extends PairingStorage {
  _ControlledStorage(this.peers);

  final List<PeerRecord> peers;
  final Map<String, Completer<List<PersistedRoom>>> blockedLoads = {};
  final Map<String, List<PersistedRoom>> roomLoads = {};
  final List<(String, List<PersistedRoom>)> roomWrites = [];
  final List<PeerRecord> peerWrites = [];
  int roomFailuresRemaining = 0;
  int peerFailuresRemaining = 0;

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async {
    final blocker = blockedLoads.remove(epk);
    return blocker == null ? roomLoads[epk] ?? const [] : blocker.future;
  }

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {
    if (roomFailuresRemaining > 0) {
      roomFailuresRemaining--;
      throw StateError('room write failed');
    }
    roomWrites.add((epk, List<PersistedRoom>.of(rooms)));
  }

  @override
  Future<void> savePeer(PeerRecord peer) async {
    peerWrites.add(peer);
    if (peerFailuresRemaining > 0) {
      peerFailuresRemaining--;
      throw StateError('peer write failed');
    }
  }
}

class _MemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.from(values);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RetryRaceStorage extends PairingStorage {
  _RetryRaceStorage() : super(_MemorySecureStorage());

  final Completer<void> retryStarted = Completer<void>();
  final Completer<void> releaseRetry = Completer<void>();
  final Completer<void> retryFinished = Completer<void>();
  int metadataWriteAttempts = 0;

  @override
  Future<void> savePeer(PeerRecord peer) async {
    metadataWriteAttempts += 1;
    if (metadataWriteAttempts == 1) {
      throw StateError('force legacy-room retry');
    }
    if (metadataWriteAttempts == 2) {
      retryStarted.complete();
      await releaseRetry.future;
    }
    await super.savePeer(peer);
    if (metadataWriteAttempts == 2) retryFinished.complete();
  }
}

class _RecordingDebugLog implements DebugLog {
  final List<DebugEvent> events = [];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async => events.clear();

  @override
  void dispose() {}
}

class _FakeChannel implements IChannel, IControlLink {
  final _server = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _server.stream;

  @override
  Stream<ControlInbound> get controlFrames => _control.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  void sendControl(Map<String, dynamic> json) {}

  @override
  Future<void> close() async {
    if (!_server.isClosed) await _server.close();
    if (!_control.isClosed) await _control.close();
  }

  void pushControl(ControlInbound frame) => _control.add(frame);
}

/// A room-aware channel that records active-room propagation.
class _FailingCloseChannel extends _FakeChannel {
  @override
  Future<void> close() => Future<void>.error(StateError('close failed'));
}

class _RecordingChannel extends _FakeChannel implements IActiveRoomTarget {
  final List<String> setActiveRoomCalls = <String>[];

  @override
  void setActiveRoom(String roomId) => setActiveRoomCalls.add(roomId);
}

Future<({ConnectionManager conn, _FakeChannel channel})> _connected() async {
  final channel = _FakeChannel();
  final conn = ConnectionManager(
    factory: (_, _) async => channel,
    storage: _FakeStorage(),
    emitDebounce: Duration.zero,
  );
  conn.adopt(channel, _peer);
  await Future<void>.delayed(Duration.zero);
  return (conn: conn, channel: channel);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('ConnectionManager room turn projection', () {
    test('projects working only for a fresh live room', () async {
      final s = await _connected();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();

      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.working,
      );
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);
      s.conn.dispose();
    });

    test(
      'local working correction is fenced by room session identity',
      () async {
        final s = await _connected();
        s.channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'main',
            sessionId: 'session-current',
            startedAt: 1,
            working: false,
          ),
        );
        await _settle();

        s.conn.markRoomWorking(
          'epk_projection',
          'main',
          true,
          sessionId: 'session-old',
          turnId: 'old-turn',
        );
        expect(s.conn.isRoomWorking('epk_projection', 'main'), isFalse);

        s.conn.markRoomWorking(
          'epk_projection',
          'main',
          true,
          sessionId: 'session-current',
          turnId: 'current-turn',
        );
        expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);
        expect(
          s.conn.roomTurnProjection('epk_projection', 'main').sessionId,
          'session-current',
        );
        s.conn.dispose();
      },
    );

    test('room_ended clears working and projects stale/not working', () async {
      final s = await _connected();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);

      s.channel.pushControl(
        const RoomEnded(peer: 'epk_projection', roomId: 'main', sinceTs: 2),
      );
      await _settle();

      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.stale,
      );
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isFalse);
      expect(s.conn.roomsFor('epk_projection').single.working, isFalse);
      s.conn.dispose();
    });

    test('room absent from a fresh RoomsSnapshot is not working', () async {
      final s = await _connected();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);

      s.channel.pushControl(
        const RoomsSnapshot(
          peer: 'epk_projection',
          rooms: [RoomInfo(roomId: 'other', startedAt: 2, working: false)],
        ),
      );
      await _settle();

      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.stale,
      );
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isFalse);
      expect(
        s.conn
            .roomsFor('epk_projection')
            .singleWhere((r) => r.roomId == 'main')
            .working,
        isFalse,
      );
      s.conn.dispose();
    });

    test('non-online connection projects stale/not working', () async {
      final s = await _connected();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);

      await s.conn.disconnect();

      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.stale,
      );
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isFalse);
      expect(s.conn.roomsFor('epk_projection').single.working, isFalse);
      s.conn.dispose();
    });

    test(
      'disconnect projects stale once without repeated idle corrections',
      () async {
        final log = _RecordingDebugLog();
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => _FakeChannel(),
          storage: _FakeStorage(),
          debugLog: log,
          emitDebounce: Duration.zero,
        );
        conn.adopt(channel, _peer);
        channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'main',
            sessionId: 'session-current',
            startedAt: 1,
            working: true,
          ),
        );
        await _settle();

        conn.debugSimulateChannelLost(channel);
        for (var tick = 0; tick < 3; tick++) {
          conn.markRoomWorking(
            'epk_projection',
            'main',
            false,
            sessionId: 'session-current',
            turnId: null,
          );
        }

        expect(
          conn.roomTurnProjection('epk_projection', 'main').status,
          AppTurnStatus.stale,
          reason: 'disconnect/retry is distinct from authoritative idle',
        );
        expect(
          conn.roomsFor('epk_projection').single.working,
          isTrue,
          reason: 'offline ticks must not overwrite cached snapshot truth',
        );
        expect(
          log.events.whereType<WorkingConvEvent>().where(
            (event) => event.reason == 'inactive_or_not_live',
          ),
          hasLength(1),
          reason: 'the disconnect edge emits once; level ticks stay quiet',
        );

        final reconnect = _FakeChannel();
        conn.adopt(reconnect, _peer);
        reconnect.pushControl(
          const RoomsSnapshot(
            peer: 'epk_projection',
            rooms: [
              RoomInfo(
                roomId: 'main',
                sessionId: 'session-current',
                startedAt: 2,
                working: false,
              ),
            ],
          ),
        );
        await _settle();

        expect(
          conn.roomTurnProjection('epk_projection', 'main').status,
          AppTurnStatus.idle,
        );
        expect(conn.roomsFor('epk_projection').single.working, isFalse);
        conn.dispose();
      },
    );

    test('reconnect hydration with working false projects idle', () async {
      final s = await _connected();
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
          working: true,
        ),
      );
      await _settle();
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isTrue);

      await s.conn.disconnect();
      final reconnect = _FakeChannel();
      s.conn.adopt(reconnect, _peer);
      reconnect.pushControl(
        const RoomsSnapshot(
          peer: 'epk_projection',
          rooms: [RoomInfo(roomId: 'main', startedAt: 2, working: false)],
        ),
      );
      await _settle();

      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.idle,
      );
      expect(s.conn.isRoomWorking('epk_projection', 'main'), isFalse);
      s.conn.dispose();
    });

    test('reconnect keeps cached room stale until a fresh snapshot', () async {
      final s = await _connected();
      final initiallyLive = s.conn.roomsStream.firstWhere(
        (_) => s.conn.isRoomLive('epk_projection', 'main'),
      );
      s.channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'main',
          startedAt: 1,
        ),
      );
      await initiallyLive.timeout(const Duration(seconds: 1));

      await s.conn.disconnect();
      final reconnect = _FakeChannel();
      final staleReconnect = s.conn.roomsStream.firstWhere(
        (_) =>
            s.conn.status is StatusOnline &&
            !s.conn.isRoomLive('epk_projection', 'main'),
      );
      s.conn.adopt(reconnect, _peer);
      await staleReconnect.timeout(const Duration(seconds: 1));

      expect(s.conn.isRoomLive('epk_projection', 'main'), isFalse);
      expect(
        s.conn.roomTurnProjection('epk_projection', 'main').status,
        AppTurnStatus.stale,
      );

      final freshlyConfirmed = s.conn.roomsStream.firstWhere(
        (_) => s.conn.isRoomLive('epk_projection', 'main'),
      );
      reconnect.pushControl(
        const RoomsSnapshot(
          peer: 'epk_projection',
          rooms: [RoomInfo(roomId: 'main', startedAt: 2)],
        ),
      );
      await freshlyConfirmed.timeout(const Duration(seconds: 1));

      expect(s.conn.isRoomLive('epk_projection', 'main'), isTrue);
      s.conn.dispose();
    });
  });

  group('ConnectionManager reconnect hydration', () {
    test(
      'restores the cached canonical session identity before relay hydrate',
      () async {
        final peer = _peer.copyWith(roomId: 'main');
        final storage = _ControlledStorage([peer]);
        storage.roomLoads[peer.remoteEpk] = [
          PersistedRoom.fromJson(const {
            'room_id': 'main',
            'session_id': 'cached-session',
            'started_at': 1,
          }),
        ];
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: storage,
          emitDebounce: Duration.zero,
        );

        await conn.boot(preferredEpk: peer.remoteEpk);

        expect(conn.status, isA<StatusOnline>());
        expect(conn.activeRoomId, 'main');
        expect(conn.activeSessionId, 'cached-session');
        conn.dispose();
      },
    );
  });

  group('ConnectionManager room persistence ownership', () {
    test('coalesces one peer to the latest snapshot before writing', () async {
      final peer = _peer.copyWith(roomId: 'main');
      final storage = _ControlledStorage([peer]);
      final firstLoad = Completer<List<PersistedRoom>>();
      storage.blockedLoads[peer.remoteEpk] = firstLoad;
      final channel = _FakeChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => channel,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      conn.adopt(channel, peer);

      channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'old-room',
          startedAt: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      channel.pushControl(
        const RoomsSnapshot(
          peer: 'epk_projection',
          rooms: [
            RoomInfo(
              roomId: 'new-room',
              sessionId: 'new-session',
              startedAt: 2,
            ),
          ],
        ),
      );
      firstLoad.complete(const []);
      await _settle();

      expect(storage.roomWrites, hasLength(1));
      expect(storage.roomWrites.single.$2.map((room) => room.roomId), [
        'old-room',
        'new-room',
      ]);
      expect(
        storage.roomWrites.single.$2
            .singleWhere((room) => room.roomId == 'new-room')
            .sessionId,
        'new-session',
      );
      conn.dispose();
    });

    test('a blocked peer does not delay another peer drain', () async {
      final peerA = _peer.copyWith(roomId: 'main');
      const peerB = PeerRecord(
        remoteEpk: 'peer-b',
        sessionName: 'Pi B',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
        roomId: 'main',
      );
      final storage = _ControlledStorage([peerA, peerB]);
      final blockedA = Completer<List<PersistedRoom>>();
      storage.blockedLoads[peerA.remoteEpk] = blockedA;
      final channel = _FakeChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => channel,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      conn.adopt(channel, peerA);

      channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'a-room',
          startedAt: 1,
        ),
      );
      channel.pushControl(
        const RoomAnnounced(peer: 'peer-b', roomId: 'b-room', startedAt: 1),
      );
      await _settle();

      expect(storage.roomWrites.map((write) => write.$1), ['peer-b']);
      blockedA.complete(const []);
      await _settle();
      expect(storage.roomWrites.map((write) => write.$1), [
        'peer-b',
        'epk_projection',
      ]);
      conn.dispose();
    });

    test('diagnoses one failure and retries on the next mutation', () async {
      final peer = _peer.copyWith(roomId: 'main');
      final storage = _ControlledStorage([peer])..roomFailuresRemaining = 1;
      final log = _RecordingDebugLog();
      final channel = _FakeChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => channel,
        storage: storage,
        debugLog: log,
        emitDebounce: Duration.zero,
      );
      conn.adopt(channel, peer);

      channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'first',
          startedAt: 1,
        ),
      );
      await _settle();
      expect(storage.roomWrites, isEmpty);
      expect(
        log.events.whereType<LifecycleFailureEvent>().single.operation,
        LifecycleOperation.roomCachePersist,
      );

      channel.pushControl(
        const RoomAnnounced(
          peer: 'epk_projection',
          roomId: 'second',
          startedAt: 2,
        ),
      );
      await _settle();
      expect(storage.roomWrites, hasLength(1));
      expect(
        storage.roomWrites.single.$2.map((room) => room.roomId),
        containsAll(['first', 'second']),
      );
      conn.dispose();
    });

    test(
      'dispose prevents a blocked drain from starting its final write',
      () async {
        final peer = _peer.copyWith(roomId: 'main');
        final storage = _ControlledStorage([peer]);
        final blocked = Completer<List<PersistedRoom>>();
        storage.blockedLoads[peer.remoteEpk] = blocked;
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: storage,
          emitDebounce: Duration.zero,
        );
        conn.adopt(channel, peer);
        channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'blocked',
            startedAt: 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        conn.dispose();
        blocked.complete(const []);
        await _settle();

        expect(storage.roomWrites, isEmpty);
      },
    );

    test(
      'legacy-room persistence retries once and diagnoses both failures',
      () async {
        final storage = _ControlledStorage(const [_peer])
          ..peerFailuresRemaining = 2;
        final log = _RecordingDebugLog();
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: storage,
          debugLog: log,
          emitDebounce: Duration.zero,
        );
        conn.adopt(channel, _peer);
        channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'discovered',
            startedAt: 1,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 320));

        expect(storage.peerWrites, hasLength(2));
        final failures = log.events
            .whereType<LifecycleFailureEvent>()
            .where(
              (event) =>
                  event.operation == LifecycleOperation.legacyRoomPersist,
            )
            .toList();
        expect(failures, hasLength(2));
        expect(failures.map((event) => event.retryScheduled), [true, false]);
        conn.dispose();
      },
    );

    test(
      'delayed legacy-room retry after re-pair preserves replacement keys',
      () async {
        final oldChannel = OwnerChannelState(
          sendKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          receiveKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          sendSequence: 8,
          receiveSequence: 5,
        );
        final newChannel = OwnerChannelState(
          sendKey: 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
          receiveKey: 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=',
        );
        final oldPeer = PeerRecord(
          remoteEpk: 'epk_projection',
          sessionName: 'Old Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
          channel: oldChannel,
        );
        final repairedPeer = PeerRecord(
          remoteEpk: 'epk_projection',
          sessionName: 'Repaired Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-02T00:00:00Z',
          roomId: 'discovered',
          channel: newChannel,
        );
        final storage = _RetryRaceStorage();
        await storage.savePairedPeer(oldPeer);
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: storage,
          emitDebounce: Duration.zero,
          legacyRoomRetryDelay: Duration.zero,
        );
        conn.adopt(channel, oldPeer);
        channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'discovered',
            startedAt: 1,
          ),
        );
        await storage.retryStarted.future;

        await storage.savePairedPeer(repairedPeer);
        storage.releaseRetry.complete();
        await storage.retryFinished.future;

        expect(
          (await storage.loadPeer(oldPeer.remoteEpk))?.channel,
          newChannel,
        );
        conn.dispose();
      },
    );

    test(
      'delayed legacy-room retry after delete cannot recreate peer',
      () async {
        final oldPeer = PeerRecord(
          remoteEpk: 'epk_projection',
          sessionName: 'Old Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
          channel: OwnerChannelState(
            sendKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            receiveKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          ),
        );
        final storage = _RetryRaceStorage();
        await storage.savePairedPeer(oldPeer);
        final channel = _FakeChannel();
        final conn = ConnectionManager(
          factory: (_, _) async => channel,
          storage: storage,
          emitDebounce: Duration.zero,
          legacyRoomRetryDelay: Duration.zero,
        );
        conn.adopt(channel, oldPeer);
        channel.pushControl(
          const RoomAnnounced(
            peer: 'epk_projection',
            roomId: 'discovered',
            startedAt: 1,
          ),
        );
        await storage.retryStarted.future;

        await storage.deletePeer(oldPeer.remoteEpk);
        storage.releaseRetry.complete();
        await storage.retryFinished.future;

        expect(await storage.loadPeer(oldPeer.remoteEpk), isNull);
        conn.dispose();
      },
    );
  });

  group('ConnectionManager unconfigured relay', () {
    test(
      'emits non-retryable offline and the watchdog does not retry',
      () async {
        var factoryCalls = 0;
        final conn = ConnectionManager(
          factory: (_, _) async {
            factoryCalls++;
            throw const RelayNotConfiguredException();
          },
          storage: _FakeStorage(),
          emitDebounce: Duration.zero,
        );

        await conn.connectTo(_peer);

        expect(conn.status, isA<StatusOffline>());
        final status = conn.status as StatusOffline;
        expect(status.canRetry, isFalse);
        expect(status.reason, kRelayNotConfiguredMessage);
        expect(factoryCalls, 1);

        conn.debugRunWatchdog();
        await Future<void>.delayed(Duration.zero);
        expect(factoryCalls, 1);
        expect(conn.status, same(status));
        conn.dispose();
      },
    );
  });

  // Regression for `story-fix-transport-active-room-reestablishment-on-reconnect`.
  // `adopt` previously did NOT set `_activeRoomId` from `peer.roomId` nor
  // propagate it to the channel, so a freshly-paired channel could demux
  // post-auth frames against the stale `'main'` default and drop real-room
  // envelopes as `room-mismatch`. It must now mirror `_connect`.
  group('ConnectionManager best-effort close', () {
    test('a replaced channel close failure does not abort adoption', () async {
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
        emitDebounce: Duration.zero,
      );
      conn.adopt(_FailingCloseChannel(), _peer);

      final replacement = _FakeChannel();
      conn.adopt(replacement, _peer);
      await Future<void>.delayed(Duration.zero);

      expect(conn.channel, same(replacement));
      conn.dispose();
    });
  });

  group('ConnectionManager adopt binds the active room', () {
    test('adopt sets activeRoomId from peer.roomId and propagates it', () {
      const peer = PeerRecord(
        remoteEpk: 'epk_projection',
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
        roomId: '7ADky8889NJy',
      );
      final channel = _RecordingChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
        emitDebounce: Duration.zero,
      );
      conn.adopt(channel, peer);
      expect(conn.activeRoomId, '7ADky8889NJy');
      expect(channel.setActiveRoomCalls, contains('7ADky8889NJy'));
      conn.dispose();
    });

    test('adopt falls back to main when peer.roomId is null', () {
      const peer = PeerRecord(
        remoteEpk: 'epk_projection',
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
        roomId: null,
      );
      final channel = _RecordingChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
        emitDebounce: Duration.zero,
      );
      conn.adopt(channel, peer);
      expect(conn.activeRoomId, 'main');
      expect(channel.setActiveRoomCalls, contains('main'));
      conn.dispose();
    });
  });
}
