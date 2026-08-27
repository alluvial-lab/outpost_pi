import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/main.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> peers;
  final Map<String, List<PersistedRoom>> _roomsByEpk = {};

  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord record) async {
    peers.removeWhere((p) => p.remoteEpk == record.remoteEpk);
    peers.add(record);
  }

  @override
  Future<void> saveRooms(String remoteEpk, List<PersistedRoom> rooms) async {
    _roomsByEpk[remoteEpk] = rooms;
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String remoteEpk) async =>
      _roomsByEpk[remoteEpk] ?? const [];

  @override
  Future<void> deleteRooms(String remoteEpk) async {
    _roomsByEpk.remove(remoteEpk);
  }
}

class _TrackingChannel implements IChannel, IControlLink {
  final _server = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  final List<Map<String, dynamic>> sentControl = [];

  @override
  Stream<ServerMessage> get serverMessages => _server.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() async {
    if (!_server.isClosed) await _server.close();
    if (!_control.isClosed) await _control.close();
  }

  @override
  Stream<ControlInbound> get controlFrames => _control.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    sentControl.add(json);
  }
}

class _FakeSyncService {
  int sessionSyncCalls = 0;

  void requestSync() {
    sessionSyncCalls += 1;
  }
}

class _BootTrackingConnectionManager extends ConnectionManager {
  _BootTrackingConnectionManager({required this.bootGate})
    : super(
        factory: (_, _) async => throw StateError('not expected'),
        storage: _FakeStorage([]),
        emitDebounce: Duration.zero,
      );

  final Completer<void> bootGate;
  int bootCalls = 0;

  @override
  ConnectionStatus get status =>
      const StatusOffline(reason: 'network unavailable');

  @override
  PeerRecord? get activePeer => null;

  @override
  Future<void> boot({String? preferredEpk}) async {
    bootCalls += 1;
    await bootGate.future;
  }
}

const _peer = PeerRecord(
  remoteEpk: 'peer_A',
  sessionName: 'pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

void main() {
  test(
    'resume on online cached state replays subscriptions and requests sync',
    () async {
      final peers = <PeerRecord>[_peer];
      final channel = _TrackingChannel();
      final storage = _FakeStorage(peers);
      final connectionManager = ConnectionManager(
        factory: (_, _) async => throw StateError('not expected'),
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final sync = _FakeSyncService();

      connectionManager.adopt(channel, peers.single);

      await reconcileOnAppResume(
        connectionManager: connectionManager,
        requestSessionSync: sync.requestSync,
      );

      final controlTypes = channel.sentControl.map((m) => m['type']).toList();
      expect(controlTypes, contains('subscribe_presence'));
      expect(controlTypes, contains('subscribe_rooms'));
      expect(controlTypes, contains('presence_check'));
      expect(controlTypes, contains('rooms_check'));
      expect(sync.sessionSyncCalls, equals(1));

      connectionManager.dispose();
    },
  );

  test('resume expires a connecting attempt older than its deadline', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 8, 27, 23, 15);
      final neverCompletes = Completer<IChannel>();
      final connectionManager = ConnectionManager(
        factory: (_, _) => neverCompletes.future,
        storage: _FakeStorage([_peer]),
        emitDebounce: Duration.zero,
        clock: () => now,
      );
      final sync = _FakeSyncService();

      // ignore: discarded_futures
      connectionManager.connectTo(_peer);
      async.flushMicrotasks();
      expect(connectionManager.status, isA<StatusConnecting>());

      // Advance the injected wall clock without advancing fake timers. This
      // models a doze-suspended deadline when the app resumes much later.
      now = now.add(const Duration(seconds: 14));
      unawaited(
        reconcileOnAppResume(
          connectionManager: connectionManager,
          requestSessionSync: sync.requestSync,
        ),
      );
      async.flushMicrotasks();
      expect(connectionManager.status, isA<StatusConnecting>());

      now = now.add(const Duration(seconds: 2));
      var reconciliationCompleted = false;
      reconcileOnAppResume(
        connectionManager: connectionManager,
        requestSessionSync: sync.requestSync,
      ).whenComplete(() => reconciliationCompleted = true);
      async.flushMicrotasks();

      expect(reconciliationCompleted, isTrue);
      final retrying = connectionManager.status as StatusRetrying;
      expect(retrying.attempt, 0);
      expect(retrying.nextRetry, const Duration(seconds: 1));
      expect(sync.sessionSyncCalls, isZero);

      connectionManager.dispose();
    });
  });

  test(
    'resume while retrying reconnects the active peer without sync',
    () async {
      final lostChannel = _TrackingChannel();
      final reconnectedChannel = _TrackingChannel();
      final factoryPeers = <PeerRecord>[];
      final connectionManager = ConnectionManager(
        factory: (peer, _) async {
          factoryPeers.add(peer);
          return reconnectedChannel;
        },
        storage: _FakeStorage([_peer]),
        emitDebounce: Duration.zero,
      );
      final sync = _FakeSyncService();
      addTearDown(() async {
        connectionManager.dispose();
        await lostChannel.close();
        await reconnectedChannel.close();
      });

      connectionManager.adopt(lostChannel, _peer);
      connectionManager.debugSimulateChannelLost(lostChannel);
      expect(connectionManager.status, isA<StatusRetrying>());
      expect(connectionManager.activePeer, same(_peer));

      await reconcileOnAppResume(
        connectionManager: connectionManager,
        requestSessionSync: sync.requestSync,
      );

      expect(factoryPeers, [_peer]);
      expect(connectionManager.status, isA<StatusOnline>());
      expect(sync.sessionSyncCalls, isZero);
    },
  );

  test(
    'resume while offline without an active peer awaits boot discovery',
    () async {
      final bootGate = Completer<void>();
      final connectionManager = _BootTrackingConnectionManager(
        bootGate: bootGate,
      );
      final sync = _FakeSyncService();
      addTearDown(connectionManager.dispose);
      var reconciliationCompleted = false;

      final reconciliation = reconcileOnAppResume(
        connectionManager: connectionManager,
        requestSessionSync: sync.requestSync,
      ).whenComplete(() => reconciliationCompleted = true);

      await Future<void>.delayed(Duration.zero);
      expect(connectionManager.bootCalls, equals(1));
      expect(reconciliationCompleted, isFalse);
      expect(sync.sessionSyncCalls, isZero);

      bootGate.complete();
      await reconciliation;

      expect(reconciliationCompleted, isTrue);
      expect(connectionManager.bootCalls, equals(1));
      expect(sync.sessionSyncCalls, isZero);
    },
  );
}
