// Regression tests for OwnerIdentityBridge's watch listener — see
// plan/24-fix-app-publish-race (follow-up). The platform plugins
// emit their current blob the moment we subscribe, which used to
// race against boot()'s population of `_current` and trigger a
// spurious `wipeAll` of the freshly-loaded peer set.

import 'dart:async';
import 'dart:typed_data';

import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

final class _FailingLoadStore implements OwnerIdentityStore {
  _FailingLoadStore(this.failure);

  final Object failure;
  int saveCalls = 0;

  @override
  Future<bool> isSyncAvailable() async => true;

  @override
  Future<OwnerIdentity?> load() => Future<OwnerIdentity?>.error(failure);

  @override
  Future<void> save(OwnerIdentity identity) async => saveCalls++;

  @override
  Stream<OwnerIdentity> watch() => const Stream.empty();

  @override
  Future<void> delete() async {}
}

final class _SecondLoadSyncUnavailableStore implements OwnerIdentityStore {
  int _loads = 0;
  int saveCalls = 0;

  @override
  Future<bool> isSyncAvailable() async => true;

  @override
  Future<OwnerIdentity?> load() async {
    if (_loads++ == 0) return null;
    throw const SyncUnavailable('sync disabled during first-run creation');
  }

  @override
  Future<void> save(OwnerIdentity identity) async => saveCalls++;

  @override
  Stream<OwnerIdentity> watch() => const Stream.empty();

  @override
  Future<void> delete() async {}
}

final class _RestoringStore implements OwnerIdentityStore {
  _RestoringStore(this.restored);

  final OwnerIdentity restored;
  int _loads = 0;
  int saveCalls = 0;

  @override
  Future<bool> isSyncAvailable() async => true;

  @override
  Future<OwnerIdentity?> load() async {
    _loads++;
    return _loads == 1 ? null : restored;
  }

  @override
  Future<void> save(OwnerIdentity identity) async => saveCalls++;

  @override
  Stream<OwnerIdentity> watch() => const Stream.empty();

  @override
  Future<void> delete() async {}
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  int failDeletesRemaining = 0;
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
  }) async {
    if (failDeletesRemaining > 0) {
      failDeletesRemaining--;
      throw StateError('injected secure-storage delete failure');
    }
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_store);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<OwnerIdentity> _freshIdentity() async {
  final kp = await Ed25519().newKeyPair();
  final pub = await kp.extractPublicKey();
  final sk = await kp.extractPrivateKeyBytes();
  return OwnerIdentity(
    ownerPk: Uint8List.fromList(pub.bytes),
    ownerSk: Uint8List.fromList(sk),
  );
}

void main() {
  group('OwnerIdentityBridge.startWatching — initial emit race fix', () {
    test('subscribing BEFORE boot() does NOT wipe peers (initial emit adopted '
        'silently)', () async {
      // Reproduce the production race: router calls startWatching
      // fire-and-forget before boot() has populated _current. The
      // store emits the existing blob immediately; without the fix
      // this would clear peers + trigger onReset.
      final id = await _freshIdentity();
      final store = InMemoryOwnerIdentityStore(initial: id);
      final storage = PairingStorage(_FakeSecureStorage());
      await storage.savePairedPeer(
        const PeerRecord(
          remoteEpk: 'epk-precious',
          sessionName: 'pi',
          relayUrl: 'https://r',
          pairedAt: '2026-05-15T10:30:00Z',
        ),
      );
      final bridge = OwnerIdentityBridge(store, storage);

      var resetCalls = 0;
      bridge.startWatching(onTransition: (_) async => resetCalls++);

      // Force the initial-emit through the in-memory store. The
      // production iOS/Android plugins do this from onListen; the
      // in-memory fake exposes the same shape via a save() that
      // echoes through the broadcast controller.
      await store.save(id);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The peer survives — no wipe happened.
      final peers = await storage.listPeers();
      expect(peers, hasLength(1));
      expect(peers.single.remoteEpk, 'epk-precious');
      // No reset callback was invoked.
      expect(resetCalls, 0);
    });

    test('after the initial emit was adopted, a *different* owner_pk DOES '
        'wipe + reset', () async {
      // Confirm the regression fix didn't soften the legitimate
      // "Owner key rotated via sync" path.
      final first = await _freshIdentity();
      final second = await _freshIdentity();
      final store = InMemoryOwnerIdentityStore(initial: first);
      final storage = PairingStorage(_FakeSecureStorage());
      await storage.savePairedPeer(
        const PeerRecord(
          remoteEpk: 'epk-old',
          sessionName: 'pi',
          relayUrl: 'https://r',
          pairedAt: '2026-05-15T10:30:00Z',
        ),
      );
      final bridge = OwnerIdentityBridge(store, storage);

      final resetCompleter = Completer<void>();
      bridge.startWatching(
        onTransition: (incoming) async {
          await storage.wipeAll();
          await bridge.completePendingTransition(incoming);
          if (!resetCompleter.isCompleted) resetCompleter.complete();
        },
      );

      // First emit (initial) — adopted silently.
      await store.save(first);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        await storage.listPeers(),
        hasLength(1),
        reason: 'initial emit must not wipe',
      );

      // Now a real key rotation — different bytes. wipeAll fires.
      await store.save(second);
      await resetCompleter.future.timeout(const Duration(seconds: 1));
      expect(
        await storage.listPeers(),
        isEmpty,
        reason: 'real key rotation must wipe',
      );
    });

    test(
      'same-pk re-emit after adoption is a noop (no wipe, no reset)',
      () async {
        final id = await _freshIdentity();
        final store = InMemoryOwnerIdentityStore(initial: id);
        final storage = PairingStorage(_FakeSecureStorage());
        await storage.savePairedPeer(
          const PeerRecord(
            remoteEpk: 'epk-stable',
            sessionName: 'pi',
            relayUrl: 'https://r',
            pairedAt: '2026-05-15T10:30:00Z',
          ),
        );
        final bridge = OwnerIdentityBridge(store, storage);
        var resets = 0;
        bridge.startWatching(onTransition: (_) async => resets++);

        await store.save(id); // initial-emit adoption
        await store.save(id); // same-pk echo — must be ignored
        await store.save(id);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(await storage.listPeers(), hasLength(1));
        expect(resets, 0);
      },
    );
  });

  group('OwnerIdentityBridge owner-transition recovery', () {
    test(
      'keeps the old identity gated when pairing cleanup partially fails',
      () async {
        final first = await _freshIdentity();
        final incoming = await _freshIdentity();
        final store = InMemoryOwnerIdentityStore(initial: first);
        final secureStorage = _FakeSecureStorage();
        final storage = PairingStorage(secureStorage);
        await storage.savePairedPeer(
          const PeerRecord(
            remoteEpk: 'old-peer',
            sessionName: 'Pi',
            relayUrl: 'https://relay',
            pairedAt: '2026-07-24T00:00:00Z',
          ),
        );
        final bridge = OwnerIdentityBridge(store, storage);
        await bridge.boot();
        final cleanupFailed = Completer<void>();
        bridge.startWatching(
          onTransition: (identity) async {
            try {
              await storage.wipeAll();
              await bridge.completePendingTransition(identity);
            } on Object {
              cleanupFailed.complete();
            }
          },
        );

        secureStorage.failDeletesRemaining = 1;
        await store.save(incoming);
        await cleanupFailed.future.timeout(const Duration(seconds: 1));

        expect(bridge.isTransitionPending, isTrue);
        expect(bridge.currentIdentity, isNull);
        expect(bridge.currentOwnerPk, isNull);
        await expectLater(bridge.requireKeyPair(), throwsA(isA<StateError>()));
        expect(await storage.hasPendingOwnerTransition(), isTrue);

        bridge.dispose();
      },
    );

    test(
      'boot retries a pending transition before activating the incoming key',
      () async {
        final incoming = await _freshIdentity();
        final store = InMemoryOwnerIdentityStore(initial: incoming);
        final storage = PairingStorage(_FakeSecureStorage());
        await storage.savePairedPeer(
          const PeerRecord(
            remoteEpk: 'stale-peer',
            sessionName: 'Pi',
            relayUrl: 'https://relay',
            pairedAt: '2026-07-24T00:00:00Z',
          ),
        );
        await storage.beginOwnerTransition();
        final restarted = OwnerIdentityBridge(store, storage);

        final result = await restarted.boot();

        expect(result, isA<OwnerTransitionPending>());
        expect(restarted.currentIdentity, isNull);
        expect(restarted.isTransitionPending, isTrue);
        expect(await storage.listPeers(), hasLength(1));

        final pending = result as OwnerTransitionPending;
        await storage.wipeAll();
        await restarted.completePendingTransition(pending.identity);

        expect(restarted.currentOwnerPk, orderedEquals(incoming.ownerPk));
        expect(await storage.listPeers(), isEmpty);
        expect(await storage.hasPendingOwnerTransition(), isFalse);

        restarted.dispose();
      },
    );
  });

  group('OwnerIdentityBridge.boot', () {
    test(
      'propagates a fatal identity-store read without saving a replacement',
      () async {
        final store = _FailingLoadStore(
          const PlatformFailure('keychain_corrupt', 'cannot read identity'),
        );
        final bridge = OwnerIdentityBridge(
          store,
          PairingStorage(_FakeSecureStorage()),
        );

        await expectLater(bridge.boot(), throwsA(isA<PlatformFailure>()));
        expect(store.saveCalls, 0);
        expect(bridge.currentIdentity, isNull);

        bridge.dispose();
      },
    );

    test(
      'returns sync-required when the load reports sync unavailable',
      () async {
        final store = _FailingLoadStore(const SyncUnavailable('sync disabled'));
        final bridge = OwnerIdentityBridge(
          store,
          PairingStorage(_FakeSecureStorage()),
        );

        expect(await bridge.boot(), isA<SyncUnavailableResult>());
        expect(store.saveCalls, 0);

        bridge.dispose();
      },
    );

    test(
      'returns sync-required when the creation recheck loses sync',
      () async {
        final store = _SecondLoadSyncUnavailableStore();
        final bridge = OwnerIdentityBridge(
          store,
          PairingStorage(_FakeSecureStorage()),
        );

        expect(await bridge.boot(), isA<SyncUnavailableResult>());
        expect(store.saveCalls, 0);

        bridge.dispose();
      },
    );

    test(
      'does not overwrite an identity restored between first-run reads',
      () async {
        final restored = await _freshIdentity();
        final store = _RestoringStore(restored);
        final bridge = OwnerIdentityBridge(
          store,
          PairingStorage(_FakeSecureStorage()),
        );

        final result = await bridge.boot();

        expect(result, isA<IdentityReady>());
        final ready = result as IdentityReady;
        expect(ready.identity, same(restored));
        expect(ready.generated, isFalse);
        expect(store.saveCalls, 0);
        expect(bridge.currentIdentity, same(restored));

        bridge.dispose();
      },
    );
  });
}
