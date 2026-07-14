import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
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

/// A _FakeChannel that records `setActiveRoom` calls so tests can assert the
/// ConnectionManager propagated the active room down to the transport.
/// `setActiveRoom` is not part of `IChannel` — `ConnectionManager` reaches
/// it via dynamic dispatch (`_propagateActiveRoom`), so this fake simply
/// declares the same method shape `PlainPeerChannel` does.
class _RecordingChannel extends _FakeChannel {
  final List<String> setActiveRoomCalls = <String>[];

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
