import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/app_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

const _peer = PeerRecord(
  remoteEpk: 'boot-peer',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

final _identity = OwnerIdentity(ownerPk: Uint8List(32), ownerSk: Uint8List(32));
final _replacementIdentity = OwnerIdentity(
  ownerPk: Uint8List.fromList(List<int>.filled(32, 1)),
  ownerSk: Uint8List.fromList(List<int>.filled(32, 1)),
);

class _TransitionSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _values = {};
  String? failDeleteKey;
  int ownerFingerprintWrites = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_values);

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
    if (key == 'dev.outpostpi.owner-transition:owner-state-fingerprint') {
      ownerFingerprintWrites++;
    }
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
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
    if (key == failDeleteKey) {
      throw StateError('injected delete failure');
    }
    _values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TransitionStorage extends PairingStorage {
  _TransitionStorage(FlutterSecureStorage store) : super(store);

  bool failAfterWipe = false;
  int wipeCalls = 0;

  @override
  Future<void> wipeAll() async {
    wipeCalls++;
    await super.wipeAll();
    if (failAfterWipe) throw StateError('injected pairing wipe failure');
  }
}

class _BootStorage extends PairingStorage {
  _BootStorage({List<PeerRecord> peers = const []}) : _peers = peers;

  final List<PeerRecord> _peers;
  Object? listError;
  int wipeCalls = 0;
  final List<Completer<List<PeerRecord>>> queuedLists = [];

  @override
  Future<void> wipeAll() async {
    wipeCalls++;
  }

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
  int watcherFailuresRemaining = 0;
  Future<void> Function(OwnerIdentity)? transitionCallback;
  Future<void> Function()? beforeCompleteTransition;
  int completedTransitions = 0;

  @override
  Future<OwnerIdentityBootResult> boot() async {
    final error = bootError;
    if (error != null) throw error;
    return result;
  }

  @override
  void startWatching({
    required Future<void> Function(OwnerIdentity incoming) onTransition,
  }) {
    watcherInstalls++;
    if (watcherFailuresRemaining > 0) {
      watcherFailuresRemaining--;
      throw StateError('watcher install failed');
    }
    transitionCallback = onTransition;
  }

  @override
  Future<void> completePendingTransition(OwnerIdentity identity) async {
    await beforeCompleteTransition?.call();
    completedTransitions++;
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
  int resetVersionCalls = 0;

  @override
  Future<bool> pullOnDemand() async {
    final error = pullError;
    if (error != null) throw error;
    return false;
  }

  @override
  void startPolling({Duration interval = const Duration(seconds: 60)}) {}

  @override
  void stopPolling() {}

  @override
  void resetVersionWatermark() {
    resetVersionCalls++;
    super.resetVersionWatermark();
  }
}

class _BootConnectionManager extends ConnectionManager {
  _BootConnectionManager(PairingStorage storage)
    : super(
        factory: (_, _) async => throw StateError('unused'),
        storage: storage,
      );

  Completer<void>? bootGate;
  Completer<void>? disconnectGate;
  Completer<void>? disconnectStarted;
  Object? bootError;
  Object? disconnectError;
  int bootCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<void> boot({String? preferredEpk}) async {
    bootCalls++;
    final gate = bootGate;
    if (gate != null) await gate.future;
    final error = bootError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    final started = disconnectStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = disconnectGate;
    if (gate != null) await gate.future;
    final error = disconnectError;
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

Future<void> _waitForState(BootState state, bool Function() condition) {
  if (condition()) return Future<void>.value();
  final completer = Completer<void>();
  void listener() {
    if (!condition() || completer.isCompleted) return;
    state.removeListener(listener);
    completer.complete();
  }

  state.addListener(listener);
  return completer.future.timeout(
    const Duration(seconds: 2),
    onTimeout: () {
      state.removeListener(listener);
      throw StateError('timed out waiting for boot state');
    },
  );
}

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

  test(
    'router owner retries a synchronous watcher installation failure',
    () async {
      final storage = _BootStorage();
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage)
        ..watcherFailuresRemaining = 1;
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      final owner = buildRouter(storage, connection, prefs, identity, mesh);

      await _waitUntil(
        () => owner.bootState.failure?.stage == BootFailureStage.identity,
        reason: 'the first watcher installation failure',
      );
      expect(identity.watcherInstalls, 1);

      owner.retryBoot();
      await _waitUntil(
        () => owner.bootState.ready,
        reason: 'boot retry after watcher installation failure',
      );
      expect(identity.watcherInstalls, 2);
      expect(identity.transitionCallback, isNotNull);

      owner.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
    },
  );

  test(
    'confirmed Owner reset disconnects before wiping transcripts and rebooting',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'router_owner_reset_',
      );
      await LocalBoxes.initForTest(directory.path);
      const ref = RemoteSessionRef(
        peerEpk: 'same-peer',
        roomId: 'same-room',
        sessionId: 'same-session',
      );
      await (await LocalBoxes().msgsBox(ref)).put(0, {'text': 'prior owner'});

      final storage = _BootStorage();
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      final owner = buildRouter(storage, connection, prefs, identity, mesh);

      await _waitUntil(
        () => owner.bootState.ready && identity.transitionCallback != null,
        reason: 'the initial boot and watcher installation',
      );
      await identity.transitionCallback!(_identity);

      expect(connection.disconnectCalls, 1);
      expect((await LocalBoxes().msgsBox(ref)), isEmpty);
      expect(mesh.resetVersionCalls, 1);

      owner.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'boot resumes a pending Owner transition before committing its identity',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'router_pending_owner_transition_',
      );
      await LocalBoxes.initForTest(directory.path);
      const ref = RemoteSessionRef(
        peerEpk: 'pending-peer',
        roomId: 'pending-room',
        sessionId: 'pending-session',
      );
      await (await LocalBoxes().msgsBox(ref)).put(0, {'text': 'old owner'});

      final storage = _BootStorage();
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage)
        ..result = OwnerTransitionPending(_identity);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      identity.beforeCompleteTransition = () async {
        expect(storage.wipeCalls, 1);
        expect(connection.disconnectCalls, 1);
        expect(await LocalBoxes().msgsBox(ref), isEmpty);
        expect(mesh.resetVersionCalls, 1);
      };

      final owner = buildRouter(storage, connection, prefs, identity, mesh);
      await _waitUntil(
        () => owner.bootState.ready,
        reason: 'pending Owner cleanup and boot completion',
      );

      expect(identity.completedTransitions, 1);
      expect(owner.bootState.failure, isNull);
      owner.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'boot retry converges a latched transcript wipe after reset failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'router_owner_reset_retry_',
      );
      await LocalBoxes.initForTest(directory.path);
      const ref = RemoteSessionRef(
        peerEpk: 'retry-peer',
        roomId: 'retry-room',
        sessionId: 'retry-session',
      );
      final boxName = LocalBoxes.msgsBoxName(ref);
      await (await LocalBoxes().msgsBox(ref)).put(0, {'text': 'prior owner'});

      final storage = _BootStorage();
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final connection = _BootConnectionManager(storage);
      final owner = buildRouter(storage, connection, prefs, identity, mesh);

      await _waitUntil(
        () => owner.bootState.ready && identity.transitionCallback != null,
        reason: 'the initial boot and watcher installation',
      );
      LocalBoxes.beforeOwnerTransitionCommonClearForTesting = () async {
        throw StateError('injected reset wipe failure');
      };
      await expectLater(
        identity.transitionCallback!(_identity),
        throwsA(isA<StateError>()),
      );
      expect(owner.bootState.failure, isNotNull);

      LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
      owner.retryBoot();
      await _waitUntil(
        () => owner.bootState.ready,
        reason: 'the latched wipe and boot retry',
      );

      expect(await Hive.boxExists(boxName), isFalse);
      expect(owner.bootState.failure, isNull);
      owner.dispose();
      connection.dispose();
      identity.dispose();
      mesh.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'router owner disposal invalidates an Owner reset blocked in disconnect',
    () async {
      final storage = _BootStorage(peers: const [_peer]);
      final prefs = _BootPreferences();
      final identity = _BootIdentityBridge(storage);
      final mesh = _BootMeshSync(identity, storage);
      final disconnectGate = Completer<void>();
      final disconnectStarted = Completer<void>();
      final connection = _BootConnectionManager(storage)
        ..disconnectGate = disconnectGate
        ..disconnectStarted = disconnectStarted;
      final owner = buildRouter(storage, connection, prefs, identity, mesh);

      await _waitUntil(
        () => owner.bootState.ready && identity.transitionCallback != null,
        reason: 'the initial boot and watcher installation',
      );
      expect(connection.bootCalls, 1);

      final resetting = identity.transitionCallback!(_identity);
      await disconnectStarted.future.timeout(const Duration(seconds: 1));
      owner.dispose();
      disconnectGate.complete();
      await resetting;

      expect(mesh.resetVersionCalls, 0);
      expect(connection.bootCalls, 1);
      expect(owner.bootState.ready, isFalse);

      connection.dispose();
      identity.dispose();
      mesh.dispose();
    },
  );

  test(
    'router retains the real Owner marker and identity gate through each cleanup failure',
    () async {
      for (final failureStep in [
        'pairing wipe',
        'disconnect',
        'transcript wipe',
        'marker deletion',
      ]) {
        final directory = Directory.systemTemp.createTempSync(
          'router_owner_transition_failure_',
        );
        await LocalBoxes.initForTest(directory.path);
        final secureStorage = _TransitionSecureStorage();
        final storage = _TransitionStorage(secureStorage);
        final original = OwnerIdentityBridge(
          InMemoryOwnerIdentityStore(initial: _identity),
          storage,
        );
        final replacement = OwnerIdentityBridge(
          InMemoryOwnerIdentityStore(initial: _replacementIdentity),
          storage,
        );
        final prefs = _BootPreferences();
        final mesh = _BootMeshSync(replacement, storage);
        final connection = _BootConnectionManager(storage);
        AppRouterOwner? owner;
        try {
          await original.boot();
          await storage.savePairedPeer(_peer);
          const ref = RemoteSessionRef(
            peerEpk: 'old-peer',
            roomId: 'old-room',
            sessionId: 'old-session',
          );
          await (await LocalBoxes().msgsBox(ref)).put(0, {'text': 'old owner'});

          switch (failureStep) {
            case 'pairing wipe':
              storage.failAfterWipe = true;
            case 'disconnect':
              connection.disconnectError = StateError('injected disconnect');
            case 'transcript wipe':
              LocalBoxes.beforeOwnerTransitionCommonClearForTesting = () async {
                throw StateError('injected transcript wipe');
              };
            case 'marker deletion':
              secureStorage.failDeleteKey =
                  'dev.outpostpi.owner-transition:pending';
          }

          owner = buildRouter(storage, connection, prefs, replacement, mesh);
          await _waitForState(
            owner.bootState,
            () => owner!.bootState.failure != null,
          );

          expect(
            owner.bootState.failure!.stage,
            BootFailureStage.storage,
            reason: failureStep,
          );
          expect(await storage.hasPendingOwnerTransition(), isTrue);
          expect(replacement.currentIdentity, isNull);
          expect(replacement.currentOwnerPk, isNull);
          await expectLater(
            replacement.requireKeyPair(),
            throwsA(isA<StateError>()),
          );

          storage.failAfterWipe = false;
          connection.disconnectError = null;
          LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
          secureStorage.failDeleteKey = null;
          owner.retryBoot();
          await _waitForState(owner.bootState, () => owner!.bootState.ready);

          expect(await storage.hasPendingOwnerTransition(), isFalse);
          expect(
            replacement.currentOwnerPk,
            orderedEquals(_replacementIdentity.ownerPk),
          );
          expect(
            secureStorage.ownerFingerprintWrites,
            2,
            reason:
                '$failureStep must commit exactly one replacement fingerprint',
          );
        } finally {
          LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
          owner?.dispose();
          connection.dispose();
          original.dispose();
          replacement.dispose();
          mesh.dispose();
          await Hive.close();
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
