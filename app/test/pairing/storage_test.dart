// Tests for the PairingStorage surface that survives plan 23 (W2A):
// PeerRecord (de)serialization, nickname/roomId edges, and the new
// `wipeAll()` helper that the OwnerIdentityBridge calls on sync-reset.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/pair_request_flow.dart' show PeerTransport;
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart' show PiHarness, Ping;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  Completer<void>? _deferredWriteStarted;
  Completer<void>? _deferredWriteRelease;
  String? _deferredSendKey;
  int? _deferredSendSequence;

  void deferChannelWrite({required String sendKey, required int sendSequence}) {
    _deferredWriteStarted = Completer<void>();
    _deferredWriteRelease = Completer<void>();
    _deferredSendKey = sendKey;
    _deferredSendSequence = sendSequence;
  }

  Future<void> get deferredWriteStarted {
    final started = _deferredWriteStarted;
    if (started == null) throw StateError('no channel write is deferred');
    return started.future;
  }

  void releaseDeferredWrite() {
    final release = _deferredWriteRelease;
    if (release == null) throw StateError('no channel write is deferred');
    release.complete();
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

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
    if (value != null &&
        key.startsWith('dev.outpostpi.owner-channels:') &&
        _deferredSendKey != null) {
      final channel = jsonDecode(value) as Map<String, dynamic>;
      if (channel['send_key'] == _deferredSendKey &&
          channel['send_seq'] == _deferredSendSequence) {
        _deferredSendKey = null;
        _deferredSendSequence = null;
        _deferredWriteStarted!.complete();
        await _deferredWriteRelease!.future;
      }
    }
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
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
  }) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.from(_store);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.clear();

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RecordingTransport implements PeerTransport {
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  @override
  Future<Uint8List> receive() =>
      Future<Uint8List>.error(StateError('receive is unused'));

  @override
  Future<void> close() async {}
}

void main() {
  group('PeerRecord — minimal post-rollback shape', () {
    test('serializes and deserializes the 4 retained fields', () {
      const record = PeerRecord(
        remoteEpk: 'pk_ed25519',
        sessionName: 'test',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      );

      final json = record.toJson();
      expect(json['remote_epk'], 'pk_ed25519');
      expect(json['session_name'], 'test');
      expect(json['relay_url'], 'ws://localhost');
      expect(json['paired_at'], '2026-01-01T00:00:00Z');
      expect(json['nickname'], isNull);

      final restored = PeerRecord.fromJson(json);
      expect(restored.remoteEpk, 'pk_ed25519');
      expect(restored.sessionName, 'test');
      expect(restored.nickname, isNull);
    });

    test('nickname round-trips through toJson/fromJson', () {
      const record = PeerRecord(
        remoteEpk: 'pk1',
        sessionName: 'outpost_pi · main',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
        nickname: 'Mac de casa',
      );
      final restored = PeerRecord.fromJson(record.toJson());
      expect(restored.nickname, 'Mac de casa');
      expect(restored.sessionName, 'outpost_pi · main');
    });

    test('legacy record without nickname field → fromJson returns null', () {
      final restored = PeerRecord.fromJson({
        'remote_epk': 'pk1',
        'session_name': 'name',
        'relay_url': 'ws://x',
        'paired_at': '2026-01-01T00:00:00Z',
      });
      expect(restored.nickname, isNull);
    });

    test('copyWith(nickname: null) clears the nickname', () {
      const record = PeerRecord(
        remoteEpk: 'pk1',
        sessionName: 'n',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
        nickname: 'old',
      );
      final cleared = record.copyWith(nickname: null);
      expect(cleared.nickname, isNull);

      final preserved = record.copyWith(sessionName: 'new');
      expect(preserved.nickname, 'old');
      expect(preserved.sessionName, 'new');
    });

    test('harness round-trips through toJson/fromJson (plan/27 Wave A)', () {
      const record = PeerRecord(
        remoteEpk: 'pk1',
        sessionName: 'name',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
        harness: PiHarness(name: 'Pi coding agent', version: '0.4.2'),
      );
      final json = record.toJson();
      expect(json['harness'], {'name': 'Pi coding agent', 'version': '0.4.2'});
      final restored = PeerRecord.fromJson(json);
      expect(restored.harness, isNotNull);
      expect(restored.harness!.name, 'Pi coding agent');
      expect(restored.harness!.version, '0.4.2');
    });

    test('legacy record without harness field → fromJson keeps null', () {
      final restored = PeerRecord.fromJson({
        'remote_epk': 'pk1',
        'session_name': 'name',
        'relay_url': 'ws://x',
        'paired_at': '2026-01-01T00:00:00Z',
      });
      expect(restored.harness, isNull);
    });

    test('copyWith(harness: ...) updates while preserving other fields', () {
      const record = PeerRecord(
        remoteEpk: 'pk1',
        sessionName: 'n',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
        nickname: 'Macbook',
        harness: PiHarness(name: 'Pi coding agent', version: '0.4.0'),
      );
      final updated = record.copyWith(
        harness: const PiHarness(name: 'Claude Code', version: '0.7.1'),
      );
      expect(updated.harness!.name, 'Claude Code');
      expect(updated.nickname, 'Macbook');
      // Sentinel default: omitting harness preserves it.
      final preserved = record.copyWith(nickname: 'mac');
      expect(preserved.harness!.version, '0.4.0');
    });

    test(
      'channel keys and sequence counters survive storage re-open',
      () async {
        final backingStore = _FakeSecureStorage();
        final first = PairingStorage(backingStore);
        final channel = OwnerChannelState(
          sendKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          receiveKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          sendSequence: 42,
          receiveSequence: 37,
        );
        await first.savePairedPeer(
          PeerRecord(
            remoteEpk: 'secure-peer',
            sessionName: 'Pi',
            relayUrl: 'wss://relay',
            pairedAt: '2026-07-23T00:00:00Z',
            channel: channel,
          ),
        );

        final reopened = PairingStorage(backingStore);
        final restored = await reopened.loadPeer('secure-peer');
        expect(restored?.channel, channel);

        final advanced = channel.copyWith(
          sendSequence: 43,
          receiveSequence: 38,
        );
        await reopened.saveChannelState('secure-peer', advanced);
        final reopenedAgain = PairingStorage(backingStore);
        expect((await reopenedAgain.listPeers()).single.channel, advanced);
      },
    );

    test(
      'pending old-channel save cannot overwrite concurrently re-paired keys',
      () async {
        const oldSendKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
        const oldReceiveKey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
        const newSendKey = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';
        const newReceiveKey = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=';
        final oldState = OwnerChannelState(
          sendKey: oldSendKey,
          receiveKey: oldReceiveKey,
        );
        final newState = OwnerChannelState(
          sendKey: newSendKey,
          receiveKey: newReceiveKey,
        );
        final oldPeer = PeerRecord(
          remoteEpk: 're-paired-peer',
          sessionName: 'Old Pi',
          relayUrl: 'wss://relay',
          pairedAt: '2026-07-23T00:00:00Z',
          channel: oldState,
        );
        final newPeer = PeerRecord(
          remoteEpk: oldPeer.remoteEpk,
          sessionName: 'New Pi',
          relayUrl: oldPeer.relayUrl,
          pairedAt: '2026-07-23T00:01:00Z',
          channel: newState,
        );
        final backingStore = _FakeSecureStorage();
        final storage = PairingStorage(backingStore);
        await storage.savePairedPeer(oldPeer);

        backingStore.deferChannelWrite(sendKey: oldSendKey, sendSequence: 1);
        final transport = _RecordingTransport();
        final oldChannel = SecurePeerChannel(
          transport: transport,
          storage: storage,
          peer: oldPeer,
        );
        final staleSave = oldChannel.send(const Ping(id: 'old-channel-send'));
        await backingStore.deferredWriteStarted;

        final rePair = storage.savePairedPeer(newPeer);
        backingStore.releaseDeferredWrite();
        await Future.wait<void>(<Future<void>>[staleSave, rePair]);

        await expectLater(
          oldChannel.send(const Ping(id: 'late-old-channel-send')),
          throwsA(isA<StateError>()),
        );
        await oldChannel.close();

        expect(transport.sent, hasLength(1));
        expect((await storage.loadPeer(oldPeer.remoteEpk))?.channel, newState);
      },
    );

    test('list/save/load round-trips through fake storage', () async {
      final storage = PairingStorage(_FakeSecureStorage());
      const r = PeerRecord(
        remoteEpk: 'epk1',
        sessionName: 'sess',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
      );
      await storage.savePairedPeer(r);

      final loaded = await storage.loadPeer('epk1');
      expect(loaded?.sessionName, 'sess');

      final all = await storage.listPeers();
      expect(all, hasLength(1));

      await storage.deletePeer('epk1');
      expect(await storage.listPeers(), isEmpty);
    });
  });

  group('PairingStorage peer mutation hook', () {
    const peer = PeerRecord(
      remoteEpk: 'epk-hook',
      sessionName: 'hook',
      relayUrl: 'ws://x',
      pairedAt: '2026-01-01T00:00:00Z',
    );

    test('save and delete emit typed mutation intent after commit', () async {
      final storage = PairingStorage(_FakeSecureStorage());
      final mutations = <PeerMutationKind>[];
      storage.attachPeerMutationHook(mutations.add);

      await storage.savePairedPeer(peer);
      expect(await storage.loadPeer(peer.remoteEpk), peer);
      await storage.deletePeer(peer.remoteEpk);
      expect(await storage.loadPeer(peer.remoteEpk), isNull);

      expect(mutations, [PeerMutationKind.upsert, PeerMutationKind.delete]);
    });

    test('silent mesh-apply methods never emit mutation intent', () async {
      final storage = PairingStorage(_FakeSecureStorage());
      final mutations = <PeerMutationKind>[];
      storage.attachPeerMutationHook(mutations.add);

      await storage.savePeerSilent(peer);

      expect(await storage.loadPeer(peer.remoteEpk), isNull);
      expect(mutations, isEmpty);
    });
  });

  group('PairingStorage.wipeAll (plan 23 sync-reset)', () {
    test('clears every peer + every persisted rooms entry', () async {
      final fake = _FakeSecureStorage();
      final storage = PairingStorage(fake);
      const a = PeerRecord(
        remoteEpk: 'epk-a',
        sessionName: 'A',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
      );
      const b = PeerRecord(
        remoteEpk: 'epk-b',
        sessionName: 'B',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
      );
      await storage.savePairedPeer(a);
      await storage.savePairedPeer(b);
      await storage.saveRooms('epk-a', const [
        PersistedRoom(roomId: 'main', startedAt: 1700000000000),
      ]);

      expect(await storage.listPeers(), hasLength(2));
      expect(await storage.loadRooms('epk-a'), hasLength(1));

      await storage.wipeAll();

      expect(await storage.listPeers(), isEmpty);
      expect(await storage.loadRooms('epk-a'), isEmpty);
    });

    test('notifies listeners exactly once', () async {
      final storage = PairingStorage(_FakeSecureStorage());
      var notifications = 0;
      storage.addListener(() => notifications++);

      await storage.wipeAll();

      expect(notifications, 1);
    });
  });
}
