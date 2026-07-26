import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/mesh/mesh_blob.dart';
import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_envelope.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool failReads = false;
  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (failReads) throw StateError('secure storage unavailable');
    return _store[key];
  }
  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }
  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async => _store.remove(key);
  @override
  Future<Map<String, String>> readAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async => Map.of(_store);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _BlockingWatermarkStorage extends PairingStorage {
  _BlockingWatermarkStorage(super.store);

  final blockedSaveStarted = Completer<void>();
  final releaseBlockedSave = Completer<void>();

  @override
  Future<void> saveMeshHighWatermark(String ownerPkHash, int version) async {
    if (version == 6) {
      if (!blockedSaveStarted.isCompleted) blockedSaveStarted.complete();
      await releaseBlockedSave.future;
    }
    await super.saveMeshHighWatermark(ownerPkHash, version);
  }
}

class _OwnerLoadRaceStorage extends PairingStorage {
  _OwnerLoadRaceStorage(super.store, this.blockedOwnerHash);

  final String blockedOwnerHash;
  final blockedLoadStarted = Completer<void>();
  final releaseBlockedLoad = Completer<void>();
  final persisted = <({String ownerHash, int version})>[];

  @override
  Future<int> loadMeshHighWatermark(String ownerPkHash) async {
    if (ownerPkHash == blockedOwnerHash &&
        !releaseBlockedLoad.isCompleted) {
      if (!blockedLoadStarted.isCompleted) blockedLoadStarted.complete();
      await releaseBlockedLoad.future;
    }
    return super.loadMeshHighWatermark(ownerPkHash);
  }

  @override
  Future<void> saveMeshHighWatermark(String ownerPkHash, int version) async {
    persisted.add((ownerHash: ownerPkHash, version: version));
    await super.saveMeshHighWatermark(ownerPkHash, version);
  }
}

class _RestoreSchedulingStorage extends PairingStorage {
  _RestoreSchedulingStorage(super.store);

  final restoreScheduled = Completer<void>();
  void Function(PeerRecord peer)? onRestoreScheduled;
  int restoreCalls = 0;

  @override
  Future<bool> restorePeerSnapshotSilent(
    PeerRecord record, {
    required bool Function() stillCurrent,
  }) {
    restoreCalls += 1;
    if (!restoreScheduled.isCompleted) restoreScheduled.complete();
    onRestoreScheduled?.call(record);
    return super.restorePeerSnapshotSilent(record, stillCurrent: stillCurrent);
  }
}

class _StubAdapter implements HttpClientAdapter {
  final Map<String, _Reply> replies = {};
  RequestOptions? lastOptions;
  String? lastBody;
  int postCount = 0;
  int getCount = 0;
  void on(String method, String pathSuffix, _Reply reply) {
    replies['$method $pathSuffix'] = reply;
  }
  @override void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastOptions = options;
    if (options.method == 'POST') postCount++;
    if (options.method == 'GET') getCount++;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      lastBody = utf8.decode(bytes);
    } else {
      lastBody = null;
    }
    final key = '${options.method} ${options.uri.path}';
    final reply = replies[key];
    if (reply == null) {
      throw StateError('No stub for $key — registered: ${replies.keys.toList()}');
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(reply.body)),
      reply.status,
      headers: const {Headers.contentTypeHeader: ['application/json']},
    );
  }
}

class _Reply {
  final int status;
  final String body;
  const _Reply(this.status, this.body);
}

class _FakeDebugLog implements DebugLog {
  final events = <DebugEvent>[];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async => events.clear();

  @override
  void dispose() {}
}

class _ScriptedMeshClient extends MeshClient {
  _ScriptedMeshClient({
    required List<Future<MeshPublishResult> Function()> publishScripts,
    List<Future<MeshFetchResult> Function()> fetchScripts = const [],
  }) : _publishScripts = publishScripts,
       _fetchScripts = fetchScripts,
       super(baseUrlProvider: () => 'https://relay.example');

  final List<Future<MeshPublishResult> Function()> _publishScripts;
  final List<Future<MeshFetchResult> Function()> _fetchScripts;
  final publishedEnvelopes = <MeshEnvelope>[];
  final Map<int, Completer<void>> _publishWaiters = {};
  final Map<int, Completer<void>> _fetchWaiters = {};
  int publishCalls = 0;
  int fetchCalls = 0;

  Future<void> waitForPublishCount(int count) {
    if (publishCalls >= count) return Future.value();
    return (_publishWaiters[count] ??= Completer<void>()).future;
  }

  Future<void> waitForFetchCount(int count) {
    if (fetchCalls >= count) return Future.value();
    return (_fetchWaiters[count] ??= Completer<void>()).future;
  }

  @override
  Future<MeshPublishResult> publish(
    String hash,
    MeshEnvelope envelope,
  ) async {
    publishedEnvelopes.add(envelope);
    publishCalls += 1;
    _publishWaiters.remove(publishCalls)?.complete();
    final index = publishCalls - 1;
    if (index >= _publishScripts.length) {
      throw StateError('unexpected publish call $publishCalls');
    }
    return _publishScripts[index]();
  }

  @override
  Future<MeshFetchResult> fetch(String hash, {int? since}) async {
    fetchCalls += 1;
    _fetchWaiters.remove(fetchCalls)?.complete();
    final index = fetchCalls - 1;
    if (index >= _fetchScripts.length) return const MeshFetchNotFound();
    return _fetchScripts[index]();
  }
}

const _testPeer = PeerRecord(
  remoteEpk: 'ZXBrLW1lc2g=',
  sessionName: 'mesh',
  relayUrl: 'https://relay.example',
  pairedAt: '2026-07-17T00:00:00Z',
);

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<({SimpleKeyPair keyPair, Uint8List ownerPk})> _newOwner() async {
  final ed = Ed25519();
  final kp = await ed.newKeyPair();
  final pub = await kp.extractPublicKey();
  return (keyPair: kp, ownerPk: Uint8List.fromList(pub.bytes));
}

/// Bridge backed by an in-memory plugin store, pre-seeded with the
/// supplied keypair so `currentOwnerPk` + `requireKeyPair` work without
/// touching the platform channel.
Future<OwnerIdentityBridge> _bootedBridge(
  PairingStorage storage,
  SimpleKeyPair keyPair,
  Uint8List ownerPk,
) async {
  final seed = await keyPair.extractPrivateKeyBytes();
  final id = OwnerIdentity(
    ownerPk: ownerPk,
    ownerSk: Uint8List.fromList(seed),
  );
  final store = InMemoryOwnerIdentityStore(initial: id);
  final bridge = OwnerIdentityBridge(store, storage);
  await bridge.boot();
  return bridge;
}

({Dio dio, _StubAdapter adapter}) _stubDio() {
  final adapter = _StubAdapter();
  final dio = Dio(BaseOptions(
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
  ))
    ..httpClientAdapter = adapter;
  return (dio: dio, adapter: adapter);
}

void main() {
  group('MeshSyncService.pullOnDemand', () {
    test('404 → keeps cache, returns true', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      s.adapter.on('GET', '/mesh/$hash', const _Reply(404, ''));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final ok = await svc.pullOnDemand();
      expect(ok, isTrue);
      expect(svc.lastVersion, 0);
    });

    test('200 with verified envelope hydrates PairingStorage', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      final blob = MeshBlob(
        version: 3,
        issuedAt: 1700000000000,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(
            remoteEpk: 'epk-a',
            relayUrl: 'wss://r',
            pairedAt: '2026-05-15T10:30:00Z',
            nickname: 'Work mac',
          ),
        ],
      );
      final env = await blob.signWith(owner.keyPair);
      final body = jsonEncode({
        'blob': base64.encode(env.blob),
        'sig': base64.encode(env.sig),
        'version': 3,
        'updated_at': 1700000000000,
      });
      final s = _stubDio();
      s.adapter.on('GET', '/mesh/$hash', _Reply(200, body));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final ok = await svc.pullOnDemand();
      expect(ok, isTrue);
      expect(svc.lastVersion, 3);
      final peers = await storage.listPeers();
      expect(peers, hasLength(1));
      expect(peers.first.remoteEpk, 'epk-a');
      expect(peers.first.nickname, 'Work mac');
    });

    test('overlapping v6 then v7 apply cannot leave the cache at v6', () async {
      final owner = await _newOwner();
      final backingStore = _FakeSecureStorage();
      final storage = _BlockingWatermarkStorage(backingStore);
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final stale = MeshBlob(
        version: 6,
        issuedAt: 6,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-stale', relayUrl: 'wss://r', pairedAt: '2026-07-22T00:00:00Z'),
        ],
      );
      final current = MeshBlob(
        version: 7,
        issuedAt: 7,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-current', relayUrl: 'wss://r', pairedAt: '2026-07-23T00:00:00Z'),
        ],
      );
      final staleEnvelope = await stale.signWith(owner.keyPair);
      final currentEnvelope = await current.signWith(owner.keyPair);
      final client = _ScriptedMeshClient(
        publishScripts: const [],
        fetchScripts: [
          () async => MeshFetchOk(envelope: staleEnvelope, version: 6, updatedAt: 6),
          () async => MeshFetchOk(envelope: currentEnvelope, version: 7, updatedAt: 7),
        ],
      );
      final service = MeshSyncService(client, bridge, storage);

      final stalePull = service.pullOnDemand();
      await storage.blockedSaveStarted.future;
      final currentPull = service.pullOnDemand();
      await client.waitForFetchCount(2);
      storage.releaseBlockedSave.complete();

      expect(await Future.wait([stalePull, currentPull]), [isTrue, isTrue]);
      expect((await storage.listPeers()).map((peer) => peer.remoteEpk), ['epk-current']);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      expect(await storage.loadMeshHighWatermark(hash), 7);
      service.dispose();
      bridge.dispose();
    });

    test('late Owner-A watermark load cannot clobber Owner B context', () async {
      final ownerA = await _newOwner();
      final ownerB = await _newOwner();
      final hashA = await MeshClient.ownerPkHash(ownerA.ownerPk);
      final hashB = await MeshClient.ownerPkHash(ownerB.ownerPk);
      final backingStore = _FakeSecureStorage();
      final storage = _OwnerLoadRaceStorage(backingStore, hashA);
      final identityA = OwnerIdentity(
        ownerPk: ownerA.ownerPk,
        ownerSk: Uint8List.fromList(await ownerA.keyPair.extractPrivateKeyBytes()),
      );
      final identityB = OwnerIdentity(
        ownerPk: ownerB.ownerPk,
        ownerSk: Uint8List.fromList(await ownerB.keyPair.extractPrivateKeyBytes()),
      );
      final ownerStore = InMemoryOwnerIdentityStore(initial: identityA);
      final bridge = OwnerIdentityBridge(ownerStore, storage);
      await bridge.boot();
      final reset = Completer<void>();
      bridge.startWatching(onTransition: (incoming) async {
        await storage.wipeAll();
        await bridge.completePendingTransition(incoming);
        if (!reset.isCompleted) reset.complete();
      });
      final blobB = MeshBlob(
        version: 4,
        issuedAt: 4,
        ownerPk: ownerB.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-owner-b', relayUrl: 'wss://r', pairedAt: '2026-07-23T00:00:00Z'),
        ],
      );
      final envelopeB = await blobB.signWith(ownerB.keyPair);
      final fetchB = Completer<MeshFetchResult>();
      final client = _ScriptedMeshClient(
        publishScripts: const [],
        fetchScripts: [() => fetchB.future],
      );
      final service = MeshSyncService(client, bridge, storage);

      final lateA = service.pullOnDemand();
      await storage.blockedLoadStarted.future;
      await ownerStore.save(identityB);
      await reset.future;
      final pullB = service.pullOnDemand();
      await client.waitForFetchCount(1);
      storage.releaseBlockedLoad.complete();
      expect(await lateA, isFalse);
      fetchB.complete(MeshFetchOk(envelope: envelopeB, version: 4, updatedAt: 4));

      expect(await pullB, isTrue);
      expect((await storage.listPeers()).map((peer) => peer.remoteEpk), ['epk-owner-b']);
      expect(await storage.loadMeshHighWatermark(hashA), 0);
      expect(await storage.loadMeshHighWatermark(hashB), 4);
      expect(storage.persisted, [(ownerHash: hashB, version: 4)]);
      service.dispose();
      bridge.dispose();
      await ownerStore.dispose();
    });

    test('durable watermark rejects a validly-signed rollback after cold start', () async {
      final owner = await _newOwner();
      final backingStore = _FakeSecureStorage();
      final storage = PairingStorage(backingStore);
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final newest = MeshBlob(
        version: 7,
        issuedAt: 7,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-current', relayUrl: 'wss://r', pairedAt: '2026-07-23T00:00:00Z'),
        ],
      );
      final newestEnvelope = await newest.signWith(owner.keyPair);
      final firstDio = _stubDio();
      firstDio.adapter.on('GET', '/mesh/$hash', _Reply(200, jsonEncode({
        'blob': base64.encode(newestEnvelope.blob),
        'sig': base64.encode(newestEnvelope.sig),
        'version': 7,
        'updated_at': 7,
      })));
      final first = MeshSyncService(
        MeshClient(baseUrlProvider: () => 'https://r', dio: firstDio.dio),
        bridge,
        storage,
      );
      expect(await first.pullOnDemand(), isTrue);
      expect(await storage.loadMeshHighWatermark(hash), 7);

      final rollback = MeshBlob(
        version: 6,
        issuedAt: 6,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-revoked', relayUrl: 'wss://r', pairedAt: '2026-07-22T00:00:00Z'),
        ],
      );
      final rollbackEnvelope = await rollback.signWith(owner.keyPair);
      final secondDio = _stubDio();
      secondDio.adapter.on('GET', '/mesh/$hash', _Reply(200, jsonEncode({
        'blob': base64.encode(rollbackEnvelope.blob),
        'sig': base64.encode(rollbackEnvelope.sig),
        'version': 6,
        'updated_at': 6,
      })));
      final log = _FakeDebugLog();
      final coldStart = MeshSyncService(
        MeshClient(baseUrlProvider: () => 'https://r', dio: secondDio.dio),
        bridge,
        storage,
        debugLog: log,
      );

      expect(await coldStart.pullOnDemand(), isFalse);
      expect(
        (await storage.listPeers()).map((peer) => peer.remoteEpk),
        ['epk-current'],
        reason: 'a rollback must not overwrite the hydrated local cache',
      );
      final failure = log.events.whereType<LifecycleFailureEvent>().single;
      expect(failure.reason, 'mesh_rollback_rejected');
    });

    test('200 with bad signature is dropped (cache untouched)', () async {
      final owner = await _newOwner();
      final other = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      // Blob signed by the WRONG key — verify must fail.
      final blob = MeshBlob(
        version: 1,
        issuedAt: 1,
        ownerPk: owner.ownerPk,
      );
      final envFromOther = await blob.signWith(other.keyPair);
      final body = jsonEncode({
        'blob': base64.encode(envFromOther.blob),
        'sig': base64.encode(envFromOther.sig),
        'version': 1,
        'updated_at': 1,
      });
      final s = _stubDio();
      s.adapter.on('GET', '/mesh/$hash', _Reply(200, body));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final ok = await svc.pullOnDemand();
      expect(ok, isFalse);
      expect(svc.lastVersion, 0);
    });

    test('200 verified blob removes peers absent from members', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      // Pre-existing peer that the relay no longer knows about.
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: 'epk-removed',
        sessionName: 'old',
        relayUrl: 'wss://r',
        pairedAt: '2026-05-01T00:00:00Z',
      ));
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      final blob = MeshBlob(
        version: 1,
        issuedAt: 1,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(
            remoteEpk: 'epk-kept',
            relayUrl: 'wss://r',
            pairedAt: '2026-05-15T10:30:00Z',
          ),
        ],
      );
      final env = await blob.signWith(owner.keyPair);
      final body = jsonEncode({
        'blob': base64.encode(env.blob),
        'sig': base64.encode(env.sig),
        'version': 1,
        'updated_at': 1,
      });
      final s = _stubDio();
      s.adapter.on('GET', '/mesh/$hash', _Reply(200, body));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      await svc.pullOnDemand();
      final peers = await storage.listPeers();
      expect(peers.map((p) => p.remoteEpk), ['epk-kept']);
    });
  });

  group('MeshSyncService durable watermark', () {
    test('applied mark floors a fresh service publish version', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final hydrated = MeshBlob(
        version: 4,
        issuedAt: 4,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(remoteEpk: 'epk-existing', relayUrl: 'wss://r', pairedAt: '2026-07-23T00:00:00Z'),
        ],
      );
      final envelope = await hydrated.signWith(owner.keyPair);
      final dio = _stubDio();
      dio.adapter.on('GET', '/mesh/$hash', _Reply(200, jsonEncode({
        'blob': base64.encode(envelope.blob),
        'sig': base64.encode(envelope.sig),
        'version': 4,
        'updated_at': 4,
      })));
      final first = MeshSyncService(
        MeshClient(baseUrlProvider: () => 'https://r', dio: dio.dio),
        bridge,
        storage,
      );
      expect(await first.pullOnDemand(), isTrue);

      final publisher = _ScriptedMeshClient(
        publishScripts: [() async => const MeshPublishOk(version: 5, updatedAt: 5)],
      );
      final coldStart = MeshSyncService(publisher, bridge, storage);
      expect(await coldStart.publish(), isA<MeshPublishOk>());
      expect(MeshBlob.fromCanonicalBytes(publisher.publishedEnvelopes.single.blob).version, 5);
      expect(await storage.loadMeshHighWatermark(hash), 5);
    });

    test('unavailable watermark storage fails pulls and publishes closed', () async {
      final owner = await _newOwner();
      final backingStore = _FakeSecureStorage();
      final storage = PairingStorage(backingStore);
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      backingStore.failReads = true;
      final client = _ScriptedMeshClient(
        publishScripts: [() async => const MeshPublishOk(version: 1, updatedAt: 1)],
      );
      final service = MeshSyncService(client, bridge, storage);

      expect(await service.pullOnDemand(), isFalse);
      expect(client.fetchCalls, 0);
      final published = await service.publish();
      expect(published, const MeshPublishFailure('watermark_unavailable'));
      expect(client.publishCalls, 0);
    });
  });

  group('MeshSyncService.publish', () {
    test('200 → MeshPublishOk and lastVersion bumps', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 1,
        'updated_at': 1700000000000,
      })));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final r = await svc.publish();
      expect(r, isA<MeshPublishOk>());
      expect(svc.lastVersion, 1);
    });

    test('409 conflict triggers one refetch + retry', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      // Need a peer in storage so the post-refetch publish doesn't hit
      // the empty-on-existing safety net (which is exactly the bug
      // fix that landed alongside this test — see the "publish race
      // fix" group below).
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: 'epk-local',
        sessionName: 'local',
        relayUrl: 'wss://r',
        pairedAt: '2026-05-15T10:30:00Z',
      ));
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      // Relay state: someone else published v5 already — same peer,
      // so the refetch+apply leaves the local cache populated.
      final newer = MeshBlob(
        version: 5,
        issuedAt: 1,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(
            remoteEpk: 'epk-local',
            relayUrl: 'wss://r',
            pairedAt: '2026-05-15T10:30:00Z',
          ),
        ],
      );
      final newerEnv = await newer.signWith(owner.keyPair);
      final s = _stubDio();
      // First POST: 409. Second POST (after refetch bumps to v6): 200.
      var postReplies = [
        _Reply(409, ''),
        _Reply(200, jsonEncode({'version': 6, 'updated_at': 1})),
      ];
      s.adapter.replies['POST /mesh/$hash'] = postReplies.first;
      // GET in between returns v5.
      s.adapter.on('GET', '/mesh/$hash', _Reply(200, jsonEncode({
        'blob': base64.encode(newerEnv.blob),
        'sig': base64.encode(newerEnv.sig),
        'version': 5,
        'updated_at': 1,
      })));

      // Hook to swap POST reply after first call.
      final client = MeshClient(
        baseUrlProvider: () => 'https://r',
        dio: Dio(BaseOptions(
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ))
          ..httpClientAdapter = _SequencingAdapter(
            postPath: '/mesh/$hash',
            postSequence: postReplies,
            others: s.adapter.replies,
          ),
      );
      final svc = MeshSyncService(client, bridge, storage);

      final r = await svc.publish();
      expect(r, isA<MeshPublishOk>());
      expect((r as MeshPublishOk).version, 6);
      expect(svc.lastVersion, 6);
    });

    test('publish failure leaves lastVersion untouched', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      s.adapter.on('POST', '/mesh/$hash', const _Reply(500, ''));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final r = await svc.publish();
      expect(r, isA<MeshPublishFailure>());
      expect(svc.lastVersion, 0);
    });
  });

  group('MeshSyncService.resetVersionWatermark', () {
    test('drops lastVersion + lastUpdatedAt', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final s = _stubDio();
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 4,
        'updated_at': 1700000000000,
      })));
      await svc.publish();
      expect(svc.lastVersion, 4);
      expect(svc.lastUpdatedAt, isNotNull);

      svc.resetVersionWatermark();
      expect(svc.lastVersion, 0);
      expect(svc.lastUpdatedAt, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Plan/24-fix-app-publish-race: pull-and-apply must NOT loop back into
  // publish, and publish must refuse to overwrite an existing membership
  // with an empty members list (which would trigger pi-extension
  // self-revoke for every paired Pi).
  // ---------------------------------------------------------------------------

  group('MeshSyncService — publish race fix', () {
    test('pullOnDemand hydrates PairingStorage WITHOUT calling publish',
        () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      // Seed local cache with a peer the relay doesn't know about so
      // apply() has to mutate (delete + maybe save).
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: 'epk-stale',
        sessionName: 'old',
        relayUrl: 'wss://r',
        pairedAt: '2026-04-01T00:00:00Z',
      ));
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      final blob = MeshBlob(
        version: 7,
        issuedAt: 1,
        ownerPk: owner.ownerPk,
        members: const [
          MeshMember(
            remoteEpk: 'epk-new',
            relayUrl: 'wss://r',
            pairedAt: '2026-05-15T10:30:00Z',
          ),
        ],
      );
      final env = await blob.signWith(owner.keyPair);
      final body = jsonEncode({
        'blob': base64.encode(env.blob),
        'sig': base64.encode(env.sig),
        'version': 7,
        'updated_at': 1,
      });
      final s = _stubDio();
      s.adapter.on('GET', '/mesh/$hash', _Reply(200, body));
      // Intentionally no POST stub registered — if the apply loop
      // accidentally triggers publish, _StubAdapter will throw.
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      // Wire the production hook on the storage so this test exercises
      // the real ciclo-pull-apply-savePeer-hook path.
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await svc.pullOnDemand();

      // Apply rewrote the cache (epk-stale gone, epk-new in).
      final peers = await storage.listPeers();
      expect(peers.map((p) => p.remoteEpk), ['epk-new']);
      // And no POST was issued — proving the silent variants broke the
      // pull→apply→publish loop.
      expect(s.adapter.postCount, 0,
          reason: 'pull-and-apply must not call publish via the hook');
    });

    test('publish refuses empty-on-existing (safety net)', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      // Pretend a previous version was already published.
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 1,
        'updated_at': 1,
      })));
      // Bootstrap _lastVersion to 1 by seeding a peer + publishing once.
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: 'epk-seed',
        sessionName: 'seed',
        relayUrl: 'wss://r',
        pairedAt: '2026-05-01T00:00:00Z',
      ));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);
      final first = await svc.publish();
      expect(first, isA<MeshPublishOk>());
      expect(svc.lastVersion, 1);
      final postCountAfterSeed = s.adapter.postCount;

      // Race window: peer disappeared from storage (apply mid-flight,
      // wipeAll, etc) — publish() must refuse rather than overwrite v1
      // with members=[].
      await storage.deletePeerSilent('epk-seed');
      final result = await svc.publish();
      expect(result, isA<MeshPublishFailure>());
      expect((result as MeshPublishFailure).reason, contains('empty-on-existing'));
      expect(svc.lastVersion, 1, reason: 'watermark stays at 1');
      expect(s.adapter.postCount, postCountAfterSeed,
          reason: 'no extra POST was issued');
    });

    test(
      'publish(allowEmpty: true) bypasses the empty-on-existing safety '
      'net — drives the legitimate "revoke last peer" flow so the '
      'relay forgets the lone member instead of holding stale state '
      'that the next pullOnDemand would resurrect locally',
      () async {
        final owner = await _newOwner();
        final storage = PairingStorage(_FakeSecureStorage());
        final bridge =
            await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
        final hash = await MeshClient.ownerPkHash(owner.ownerPk);
        final s = _stubDio();
        s.adapter.on(
          'POST',
          '/mesh/$hash',
          _Reply(200, jsonEncode({'version': 1, 'updated_at': 1})),
        );
        await storage.savePairedPeer(const PeerRecord(
          remoteEpk: 'epk-only',
          sessionName: 'only',
          relayUrl: 'wss://r',
          pairedAt: '2026-05-01T00:00:00Z',
        ));
        final client =
            MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
        final svc = MeshSyncService(client, bridge, storage);
        final first = await svc.publish();
        expect(first, isA<MeshPublishOk>());
        expect(svc.lastVersion, 1);

        // The legitimate last-peer revoke: storage is empty AND watermark
        // is non-zero, but the caller explicitly opted in.
        await storage.deletePeerSilent('epk-only');
        s.adapter.on(
          'POST',
          '/mesh/$hash',
          _Reply(200, jsonEncode({'version': 2, 'updated_at': 2})),
        );
        final result = await svc.publish(allowEmpty: true);
        expect(result, isA<MeshPublishOk>(),
            reason: 'allowEmpty:true must bypass the safety net');
        expect(svc.lastVersion, 2);
        expect(
          await storage.loadMeshHighWatermark(hash),
          2,
          reason: 'legitimate empty revocation still advances the rollback floor',
        );
      },
    );

    test('publishing empty members at v=0 is allowed (edge case)', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 1,
        'updated_at': 1,
      })));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);
      // Storage is empty + lastVersion is 0 → publish proceeds (no
      // membership to clobber).
      final r = await svc.publish();
      expect(r, isA<MeshPublishOk>());
      expect(svc.lastVersion, 1);
    });

    test(
        'remote_epk is normalised to base64 standard in the published '
        'blob (url-safe input → standard output, idempotent on standard)',
        () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      // Seed a peer with the historical url-safe encoding (no padding,
      // `_` / `-` alphabet) — that's what PairingStorage receives from
      // QR / pair_ok today.
      const urlSafeEpk =
          'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO_oMQ6yyQE';
      const expectedStandard =
          'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO/oMQ6yyQE=';
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: urlSafeEpk,
        sessionName: 'pi',
        relayUrl: 'https://r',
        pairedAt: '2026-05-15T10:30:00Z',
      ));
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);

      // Capture the request body so we can inspect the blob bytes.
      final s = _stubDio();
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 1,
        'updated_at': 1,
      })));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      final r = await svc.publish();
      expect(r, isA<MeshPublishOk>());

      // Pull the blob out of the POST body, parse it, assert the
      // member's remote_epk is the standard form.
      final body = jsonDecode(s.adapter.lastBody!) as Map<String, Object?>;
      final blobBytes = base64.decode(body['blob']! as String);
      final blob = MeshBlob.fromCanonicalBytes(blobBytes);
      expect(blob.members, hasLength(1));
      expect(blob.members.single.remoteEpk, expectedStandard,
          reason: 'url-safe input must be re-encoded to standard');

      // Idempotence: a second publish (same peer, now stored
      // post-mesh) — re-emit with standard input, output is standard.
      await storage.saveMeshPeerMetadata(PeerRecord(
        remoteEpk: expectedStandard,
        sessionName: 'pi',
        relayUrl: 'https://r',
        pairedAt: '2026-05-15T10:30:00Z',
      ));
      // Wipe the prior key so listPeers returns ONLY the standard
      // form (the previous key was the url-safe one).
      await storage.deletePeerSilent(urlSafeEpk);
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 2,
        'updated_at': 2,
      })));
      await svc.publish();
      final body2 = jsonDecode(s.adapter.lastBody!) as Map<String, Object?>;
      final blob2 = MeshBlob.fromCanonicalBytes(
        base64.decode(body2['blob']! as String),
      );
      expect(blob2.members.single.remoteEpk, expectedStandard,
          reason: 'toStandardB64 must be idempotent');
    });

    test('explicit savePeer (local mutation) DOES fire the hook', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final hash = await MeshClient.ownerPkHash(owner.ownerPk);
      final s = _stubDio();
      s.adapter.on('POST', '/mesh/$hash', _Reply(200, jsonEncode({
        'version': 1,
        'updated_at': 1,
      })));
      final client = MeshClient(baseUrlProvider: () => 'https://r', dio: s.dio);
      final svc = MeshSyncService(client, bridge, storage);

      var hookCalls = 0;
      storage.attachPeerMutationHook((kind) {
        hookCalls++;
        svc.publishAfterPeerMutation(kind);
      });

      // Simulate a real local mutation (e.g. PairingViewModel saving a
      // newly-paired peer). Non-silent variant → hook fires.
      await storage.savePairedPeer(const PeerRecord(
        remoteEpk: 'epk-fresh',
        sessionName: 'fresh',
        relayUrl: 'wss://r',
        pairedAt: '2026-05-15T10:30:00Z',
      ));

      // Hook fired exactly once; publish was kicked off in the
      // background. Give it a microtask to land.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hookCalls, 1);
      expect(s.adapter.postCount, greaterThanOrEqualTo(1));
    });
  });

  group('MeshSyncService mutation publication ownership', () {
    test('mutations during publish coalesce into one latest follow-up', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final firstResult = Completer<MeshPublishResult>();
      final client = _ScriptedMeshClient(
        publishScripts: [
          () => firstResult.future,
          () async => const MeshPublishOk(version: 2, updatedAt: 2),
        ],
      );
      final svc = MeshSyncService(client, bridge, storage);
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(1);
      await storage.savePeer(_testPeer.copyWith(sessionName: 'newer'));
      await storage.savePeer(
        _testPeer.copyWith(sessionName: 'newest', nickname: 'latest'),
      );

      firstResult.complete(const MeshPublishOk(version: 1, updatedAt: 1));
      await client.waitForPublishCount(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.publishCalls, 2);
      final followUp = MeshBlob.fromCanonicalBytes(
        client.publishedEnvelopes[1].blob,
      );
      expect(followUp.members.single.nickname, 'latest');
      svc.dispose();
    });

    test('transient failure retries once and diagnoses owned retry', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final log = _FakeDebugLog();
      final client = _ScriptedMeshClient(
        publishScripts: [
          () async => const MeshPublishFailure('sensitive network detail'),
          () async => const MeshPublishOk(version: 1, updatedAt: 1),
        ],
      );
      final svc = MeshSyncService(
        client,
        bridge,
        storage,
        debugLog: log,
        mutationRetryDelay: const Duration(milliseconds: 1),
      );
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.publishCalls, 2);
      final failure = log.events.whereType<LifecycleFailureEvent>().single;
      expect(failure.operation, LifecycleOperation.meshPublish);
      expect(failure.retryScheduled, isTrue);
      expect(failure.reason, isNot(contains('sensitive')));
      svc.dispose();
    });

    test('permanent typed outcomes diagnose and never retry', () async {
      final outcomes = <MeshPublishResult>[
        const MeshPublishBadRequest('untrusted relay body'),
        const MeshPublishForbidden(),
        const MeshPublishTooLarge(),
      ];

      for (final outcome in outcomes) {
        final owner = await _newOwner();
        final storage = PairingStorage(_FakeSecureStorage());
        final bridge = await _bootedBridge(
          storage,
          owner.keyPair,
          owner.ownerPk,
        );
        final log = _FakeDebugLog();
        final client = _ScriptedMeshClient(
          publishScripts: [() async => outcome],
        );
        final svc = MeshSyncService(
          client,
          bridge,
          storage,
          debugLog: log,
          mutationRetryDelay: const Duration(milliseconds: 1),
        );
        storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

        await storage.savePairedPeer(_testPeer);
        await client.waitForPublishCount(1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(client.publishCalls, 1, reason: '$outcome must be permanent');
        final failure = log.events.whereType<LifecycleFailureEvent>().single;
        expect(failure.operation, LifecycleOperation.meshPublish);
        expect(failure.retryScheduled, isFalse);
        expect(failure.reason, isNot(contains('untrusted')));
        svc.dispose();
      }
    });

    test('second conflict remains pending after private rebase pull', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final log = _FakeDebugLog();
      final client = _ScriptedMeshClient(
        publishScripts: [
          () async => const MeshPublishConflict(),
          () async => const MeshPublishConflict(),
        ],
      );
      final svc = MeshSyncService(
        client,
        bridge,
        storage,
        debugLog: log,
        mutationRetryDelay: const Duration(days: 1),
      );
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.fetchCalls, 1, reason: 'conflict rebase pull stays allowed');
      expect(client.publishCalls, 2);
      expect(
        log.events.whereType<LifecycleFailureEvent>().single.retryScheduled,
        isTrue,
      );
      svc.dispose();
    });

    test('unexpected throw is transient and privacy-safe', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final log = _FakeDebugLog();
      final client = _ScriptedMeshClient(
        publishScripts: [
          () => Future<MeshPublishResult>.error(
            StateError('must-not-log-full-owner-key'),
          ),
          () async => const MeshPublishOk(version: 1, updatedAt: 1),
        ],
      );
      final svc = MeshSyncService(
        client,
        bridge,
        storage,
        debugLog: log,
        mutationRetryDelay: const Duration(milliseconds: 1),
      );
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final failure = log.events.whereType<LifecycleFailureEvent>().single;
      expect(failure.retryScheduled, isTrue);
      expect(failure.reason, isNot(contains('owner-key')));
      svc.dispose();
    });

    test(
      'conflict snapshot restore keeps protected channel when still current',
      () async {
        final owner = await _newOwner();
        final storage = _RestoreSchedulingStorage(_FakeSecureStorage());
        final protectedPeer = _testPeer.copyWith(
          channel: OwnerChannelState(
            sendKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            receiveKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            sendSequence: 7,
            receiveSequence: 9,
          ),
        );
        await storage.savePairedPeer(protectedPeer);
        final bridge = await _bootedBridge(
          storage,
          owner.keyPair,
          owner.ownerPk,
        );
        final relayBlob = MeshBlob(
          version: 2,
          issuedAt: 2,
          ownerPk: owner.ownerPk,
          members: const [
            MeshMember(
              remoteEpk: 'ZXBrLW1lc2g=',
              relayUrl: 'https://relay.changed',
              pairedAt: '2026-07-17T00:00:00Z',
              nickname: 'relay metadata',
            ),
          ],
        );
        final relayEnvelope = await relayBlob.signWith(owner.keyPair);
        final client = _ScriptedMeshClient(
          publishScripts: [
            () async => const MeshPublishConflict(),
            () async => const MeshPublishOk(version: 3, updatedAt: 3),
          ],
          fetchScripts: [
            () async => MeshFetchOk(
              envelope: relayEnvelope,
              version: 2,
              updatedAt: 2,
            ),
          ],
        );
        final svc = MeshSyncService(client, bridge, storage);

        final result = await svc.publish();

        expect(result, isA<MeshPublishOk>());
        expect(storage.restoreCalls, 1);
        expect(await storage.loadPeer(protectedPeer.remoteEpk), protectedPeer);
        final retry = MeshBlob.fromCanonicalBytes(
          client.publishedEnvelopes[1].blob,
        );
        expect(retry.members.single.relayUrl, protectedPeer.relayUrl);
        expect(retry.members.single.nickname, protectedPeer.nickname);
        svc.dispose();
      },
    );

    test(
      'queued revoke aborts conflict snapshot restore without resurrecting keys',
      () async {
        final owner = await _newOwner();
        final backingStore = _FakeSecureStorage();
        final storage = _RestoreSchedulingStorage(backingStore);
        final protectedPeer = _testPeer.copyWith(
          channel: OwnerChannelState(
            sendKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            receiveKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            sendSequence: 7,
            receiveSequence: 9,
          ),
        );
        await storage.savePairedPeer(protectedPeer);
        final bridge = await _bootedBridge(
          storage,
          owner.keyPair,
          owner.ownerPk,
        );
        final relayBlob = MeshBlob(
          version: 2,
          issuedAt: 2,
          ownerPk: owner.ownerPk,
          members: const [
            MeshMember(
              remoteEpk: 'ZXBrLW1lc2g=',
              relayUrl: 'https://relay.changed',
              pairedAt: '2026-07-17T00:00:00Z',
              nickname: 'relay metadata',
            ),
          ],
        );
        final relayEnvelope = await relayBlob.signWith(owner.keyPair);
        final client = _ScriptedMeshClient(
          publishScripts: [
            () async => const MeshPublishConflict(),
            () async => const MeshPublishOk(version: 3, updatedAt: 3),
          ],
          fetchScripts: [
            () async => MeshFetchOk(
              envelope: relayEnvelope,
              version: 2,
              updatedAt: 2,
            ),
          ],
        );
        final svc = MeshSyncService(client, bridge, storage);
        storage.attachPeerMutationHook(svc.publishAfterPeerMutation);
        Future<void>? revoke;
        storage.onRestoreScheduled = (peer) {
          revoke = storage.deletePeer(peer.remoteEpk);
        };

        final result = await svc.publish();
        await storage.restoreScheduled.future;
        await revoke;

        expect(result, isA<MeshPublishConflict>());
        expect(storage.restoreCalls, 1);
        expect(await storage.loadPeer(protectedPeer.remoteEpk), isNull);
        expect(
          backingStore._store.keys,
          isNot(
            contains('dev.outpostpi.owner-channels:${protectedPeer.remoteEpk}'),
          ),
          reason: 'the stale snapshot must not restore revoked channel keys',
        );
        svc.dispose();
      },
    );

    test(
      'normal pull aborts when a local mutation becomes pending during fetch',
      () async {
        final owner = await _newOwner();
        final storage = PairingStorage(_FakeSecureStorage());
        final bridge = await _bootedBridge(
          storage,
          owner.keyPair,
          owner.ownerPk,
        );
        final relayBlob = MeshBlob(
          version: 1,
          issuedAt: 1,
          ownerPk: owner.ownerPk,
        );
        final relayEnvelope = await relayBlob.signWith(owner.keyPair);
        final fetchResult = Completer<MeshFetchResult>();
        final publishResult = Completer<MeshPublishResult>();
        final client = _ScriptedMeshClient(
          publishScripts: [() => publishResult.future],
          fetchScripts: [() => fetchResult.future],
        );
        final svc = MeshSyncService(client, bridge, storage);
        storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

        final pulling = svc.pullOnDemand();
        await client.waitForFetchCount(1);
        await storage.savePairedPeer(_testPeer);
        fetchResult.complete(
          MeshFetchOk(
            envelope: relayEnvelope,
            version: 1,
            updatedAt: 1,
          ),
        );

        expect(await pulling, isFalse);
        expect(
          (await storage.listPeers()).map((peer) => peer.remoteEpk),
          [_testPeer.remoteEpk],
          reason: 'the fetched empty snapshot must not erase the new peer',
        );

        svc.dispose();
        if (!publishResult.isCompleted) {
          publishResult.complete(const MeshPublishFailure('disposed'));
        }
      },
    );

    test(
      'last-peer deletion survives conflict pull and retries as members=[]',
      () async {
        final owner = await _newOwner();
        final storage = PairingStorage(_FakeSecureStorage());
        final bridge = await _bootedBridge(
          storage,
          owner.keyPair,
          owner.ownerPk,
        );
        final relayBlob = MeshBlob(
          version: 2,
          issuedAt: 2,
          ownerPk: owner.ownerPk,
          members: const [
            MeshMember(
              remoteEpk: 'ZXBrLW1lc2g=',
              relayUrl: 'https://relay.example',
              pairedAt: '2026-07-17T00:00:00Z',
            ),
          ],
        );
        final relayEnvelope = await relayBlob.signWith(owner.keyPair);
        final client = _ScriptedMeshClient(
          publishScripts: [
            () async => const MeshPublishOk(version: 1, updatedAt: 1),
            () async => const MeshPublishConflict(),
            () async => const MeshPublishOk(version: 3, updatedAt: 3),
          ],
          fetchScripts: [
            () async => MeshFetchOk(
              envelope: relayEnvelope,
              version: 2,
              updatedAt: 2,
            ),
          ],
        );
        final svc = MeshSyncService(client, bridge, storage);
        storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

        await storage.savePairedPeer(_testPeer);
        await client.waitForPublishCount(1);
        await _waitUntil(
          () => svc.lastVersion == 1,
          reason: 'the initial peer publication',
        );

        await storage.deletePeer(_testPeer.remoteEpk);
        await client.waitForPublishCount(3);
        await _waitUntil(
          () => svc.lastVersion == 3,
          reason: 'the rebased deletion retry',
        );

        expect(client.fetchCalls, 1);
        expect(await storage.listPeers(), isEmpty);
        final retry = MeshBlob.fromCanonicalBytes(
          client.publishedEnvelopes[2].blob,
        );
        expect(
          retry.members,
          isEmpty,
          reason: 'the conflict pull must not resurrect the deleted last peer',
        );
        svc.dispose();
      },
    );

    test('normal pull defers while a local publication remains pending', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final client = _ScriptedMeshClient(
        publishScripts: [
          () async => const MeshPublishFailure('offline'),
        ],
      );
      final svc = MeshSyncService(
        client,
        bridge,
        storage,
        mutationRetryDelay: const Duration(days: 1),
      );
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await svc.pullOnDemand(), isFalse);
      expect(client.fetchCalls, 0);
      expect(client.publishCalls, 1);
      svc.dispose();
    });

    test('last-peer delete publishes members=[] exactly once', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final client = _ScriptedMeshClient(
        publishScripts: [
          () async => const MeshPublishOk(version: 1, updatedAt: 1),
          () async => const MeshPublishOk(version: 2, updatedAt: 2),
        ],
      );
      final svc = MeshSyncService(client, bridge, storage);
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await storage.deletePeer(_testPeer.remoteEpk);
      await client.waitForPublishCount(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.publishCalls, 2);
      final deletion = MeshBlob.fromCanonicalBytes(
        client.publishedEnvelopes[1].blob,
      );
      expect(deletion.members, isEmpty);
      svc.dispose();
    });

    test('dispose suppresses an in-flight drain follow-up and notification', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final firstResult = Completer<MeshPublishResult>();
      final client = _ScriptedMeshClient(
        publishScripts: [() => firstResult.future],
      );
      final svc = MeshSyncService(client, bridge, storage);
      var notifications = 0;
      svc.addListener(() => notifications += 1);
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(1);
      await storage.savePeer(_testPeer.copyWith(sessionName: 'newer'));
      svc.dispose();
      firstResult.complete(const MeshPublishOk(version: 1, updatedAt: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.publishCalls, 1);
      expect(notifications, 0);
      expect(svc.lastVersion, 0);
    });

    test('dispose cancels a pending publication retry', () async {
      final owner = await _newOwner();
      final storage = PairingStorage(_FakeSecureStorage());
      final bridge = await _bootedBridge(storage, owner.keyPair, owner.ownerPk);
      final client = _ScriptedMeshClient(
        publishScripts: [
          () async => const MeshPublishFailure('offline'),
        ],
      );
      final svc = MeshSyncService(
        client,
        bridge,
        storage,
        mutationRetryDelay: const Duration(milliseconds: 5),
      );
      storage.attachPeerMutationHook(svc.publishAfterPeerMutation);

      await storage.savePairedPeer(_testPeer);
      await client.waitForPublishCount(1);
      svc.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.publishCalls, 1);
    });
  });
}

/// HttpClientAdapter that returns POSTs in declared sequence, GETs by
/// path. Used to script the 409-then-200 conflict path.
class _SequencingAdapter implements HttpClientAdapter {
  final String postPath;
  final List<_Reply> postSequence;
  final Map<String, _Reply> others;
  int postCalls = 0;
  _SequencingAdapter({
    required this.postPath,
    required this.postSequence,
    required this.others,
  });
  @override void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
    if (stream != null) {
      await stream.fold<List<int>>(<int>[], (acc, chunk) {
        acc.addAll(chunk);
        return acc;
      });
    }
    _Reply reply;
    if (options.method == 'POST' && options.uri.path == postPath) {
      reply = postSequence[postCalls < postSequence.length ? postCalls : postSequence.length - 1];
      postCalls++;
    } else {
      final key = '${options.method} ${options.uri.path}';
      reply = others[key] ?? (throw StateError('No stub for $key'));
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(reply.body)),
      reply.status,
      headers: const {Headers.contentTypeHeader: ['application/json']},
    );
  }
}
