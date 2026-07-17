import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

const _peer = PeerRecord(
  remoteEpk: 'boot-peer',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

final _identity = OwnerIdentity(ownerPk: Uint8List(32), ownerSk: Uint8List(32));

class _BootStorage extends PairingStorage {
  _BootStorage({List<PeerRecord> peers = const []}) : _peers = peers;

  final List<PeerRecord> _peers;
  Object? listError;
  final List<Completer<List<PeerRecord>>> queuedLists = [];

  @override
  Future<List<PeerRecord>> listPeers() async {
    if (queuedLists.isNotEmpty) return queuedLists.removeAt(0).future;
    final error = listError;
    if (error != null) throw error;
    return _peers;
  }

  @override
  Future<void> savePeer(PeerRecord peer) async {}

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => const [];

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}
}

class _BootPreferences extends Preferences {
  Object? loadError;
  Completer<void>? loadGate;
  String? selected;
  bool onboarded = true;

  @override
  String? get selectedPeerEpk => selected;

  @override
  bool get onboardingCompleted => onboarded;

  @override
  Future<void> load() async {
    final gate = loadGate;
    if (gate != null) await gate.future;
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<void> setSelectedPeerEpk(String? value) async {
    selected = value;
  }

  @override
  Future<void> setOnboardingCompleted(bool value) async {
    onboarded = value;
  }
}

class _BootIdentityBridge extends OwnerIdentityBridge {
  _BootIdentityBridge(PairingStorage storage)
    : super(InMemoryOwnerIdentityStore(initial: _identity), storage);

  OwnerIdentityBootResult result = IdentityReady(_identity, generated: false);
  Object? bootError;
  int watcherInstalls = 0;

  @override
  Future<OwnerIdentityBootResult> boot() async {
    final error = bootError;
    if (error != null) throw error;
    return result;
  }

  @override
  void startWatching({required Future<void> Function() onReset}) {
    watcherInstalls++;
  }
}

class _BootMeshSync extends MeshSyncService {
  _BootMeshSync(OwnerIdentityBridge owner, PairingStorage storage)
    : super(
        MeshClient(baseUrlProvider: () => 'http://localhost'),
        owner,
        storage,
      );

  Object? pullError;

  @override
  Future<bool> pullOnDemand() async {
    final error = pullError;
    if (error != null) throw error;
    return false;
  }

  @override
  void startPolling({Duration interval = const Duration(seconds: 60)}) {}
}

class _BootConnectionManager extends ConnectionManager {
  _BootConnectionManager(PairingStorage storage)
    : super(
        factory: (_, _) async => throw StateError('unused'),
        storage: storage,
      );

  Completer<void>? bootGate;
  Object? bootError;
  int bootCalls = 0;

  @override
  Future<void> boot({String? preferredEpk}) async {
    bootCalls++;
    final gate = bootGate;
    if (gate != null) await gate.future;
    final error = bootError;
    if (error != null) throw error;
  }
}

Future<void> _load(
  BootState state,
  _BootStorage storage,
  _BootConnectionManager connection,
  _BootPreferences preferences,
  _BootIdentityBridge identity,
  _BootMeshSync mesh, {
  void Function()? installWatcher,
}) => state.load(
  storage,
  connection,
  preferences,
  identity,
  mesh,
  installWatcherAfterBoot: installWatcher,
);

void main() {
  test(
    'readiness waits for the initial connection attempt to settle',
    () async {
      final storage = _BootStorage(peers: const [_peer]);
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage)
        ..bootGate = Completer<void>();
      final state = BootState();

      final loading = _load(
        state,
        storage,
        connection,
        prefs,
        identity,
        mesh,
        installWatcher: () => identity.watcherInstalls++,
      );
      await Future<void>.delayed(Duration.zero);

      expect(state.loading, isTrue);
      expect(state.ready, isFalse);
      expect(identity.watcherInstalls, 0);

      connection.bootGate!.complete();
      await loading;
      expect(state.ready, isTrue);
      expect(connection.bootCalls, 1);
      expect(identity.watcherInstalls, 1);

      state.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
    },
  );

  test('retryable network failure completes boot in StatusRetrying', () async {
    final storage = _BootStorage(peers: const [_peer]);
    final prefs = _BootPreferences();
    final identity = _BootIdentityBridge(storage);
    final mesh = _BootMeshSync(identity, storage);
    final connection = ConnectionManager(
      factory: (_, _) async => throw StateError('relay unavailable'),
      storage: storage,
    );
    final state = BootState();

    await state.load(storage, connection, prefs, identity, mesh);

    expect(state.ready, isTrue);
    expect(state.failure, isNull);
    expect(connection.status, isA<StatusRetrying>());

    state.dispose();
    connection.dispose();
    identity.dispose();
    mesh.dispose();
  });

  test('sync unavailable remains a completed typed boot branch', () async {
    final storage = _BootStorage();
    final prefs = _BootPreferences();
    final identity = _BootIdentityBridge(storage)
      ..result = const SyncUnavailableResult();
    final mesh = _BootMeshSync(identity, storage);
    final connection = _BootConnectionManager(storage);
    final state = BootState();

    await _load(state, storage, connection, prefs, identity, mesh);

    expect(state.ready, isTrue);
    expect(state.syncAvailable, isFalse);
    expect(state.failure, isNull);

    state.dispose();
    connection.dispose();
    identity.dispose();
    mesh.dispose();
  });

  test('boot phase exceptions retain a retryable typed failure', () async {
    Future<BootFailure> run({required BootFailureStage stage}) async {
      final storage = _BootStorage(peers: const [_peer]);
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      switch (stage) {
        case BootFailureStage.preferences:
          prefs.loadError = StateError('prefs');
        case BootFailureStage.identity:
          identity.bootError = StateError('identity');
        case BootFailureStage.storage:
          storage.listError = StateError('storage');
        case BootFailureStage.connection:
          connection.bootError = StateError('connection');
      }
      final state = BootState();
      await _load(state, storage, connection, prefs, identity, mesh);
      final failure = state.failure!;
      expect(state.ready, isFalse);
      expect(state.loading, isFalse);
      state.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
      return failure;
    }

    for (final stage in BootFailureStage.values) {
      final failure = await run(stage: stage);
      expect(failure.stage, stage);
      expect(failure.message, isNot(contains('StateError')));
    }
  });

  test(
    'retry invalidates a stale run before it can install a watcher',
    () async {
      final firstList = Completer<List<PeerRecord>>();
      final secondList = Completer<List<PeerRecord>>()..complete(const []);
      final storage = _BootStorage()
        ..queuedLists.addAll([firstList, secondList]);
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      final state = BootState();
      var watcherInstalls = 0;

      final stale = _load(
        state,
        storage,
        connection,
        prefs,
        identity,
        mesh,
        installWatcher: () => watcherInstalls++,
      );
      await Future<void>.delayed(Duration.zero);
      state.invalidate();
      await _load(
        state,
        storage,
        connection,
        prefs,
        identity,
        mesh,
        installWatcher: () => watcherInstalls++,
      );
      firstList.complete(const [_peer]);
      await stale;

      expect(state.ready, isTrue);
      expect(state.hasPeer, isFalse);
      expect(watcherInstalls, 1);

      state.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
    },
  );

  test('dispose invalidates completion and watcher installation', () async {
    final storage = _BootStorage();
    final prefs = _BootPreferences()..loadGate = Completer<void>();
    final identity = _BootIdentityBridge(storage);
    final mesh = _BootMeshSync(identity, storage);
    final connection = _BootConnectionManager(storage);
    final state = BootState();
    var watcherInstalls = 0;

    final loading = _load(
      state,
      storage,
      connection,
      prefs,
      identity,
      mesh,
      installWatcher: () => watcherInstalls++,
    );
    state.dispose();
    prefs.loadGate!.complete();
    await loading;

    expect(state.ready, isFalse);
    expect(watcherInstalls, 0);

    connection.dispose();
    identity.dispose();
    mesh.dispose();
  });
}
