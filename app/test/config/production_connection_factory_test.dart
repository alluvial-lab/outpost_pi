import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/config/production_connection_factory.dart';
import 'package:app/data/identity/device_id.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

const _configuredRelay = 'https://configured.example';
const _pairedRelay = 'http://paired.example';

void main() {
  test(
    'configured primary failure closes its attempt before paired alternate connects',
    () async {
      final events = <String>[];
      final attempts = <String>[];
      final primaryClosed = Completer<void>();
      final alternateTransport = _FakeTransport();
      final composition = await _buildComposition(
        connectTransport:
            ({
              required relayUrl,
              required peerPubkey,
              required ed25519Key,
              required deviceId,
              required activeRoom,
              required debugLog,
              required cancellation,
            }) {
              attempts.add(relayUrl);
              events.add('start:$relayUrl');
              if (relayUrl == _configuredRelay) {
                cancellation.addCancellationListener(() async {
                  events.add('closed:$relayUrl');
                  if (!primaryClosed.isCompleted) primaryClosed.complete();
                });
                return Future<PeerTransport>.error(
                  const _FakeAttemptError('configured relay unavailable'),
                );
              }

              expect(
                primaryClosed.isCompleted,
                isTrue,
                reason: 'the failed candidate must be drained before failover',
              );
              return Future<PeerTransport>.value(alternateTransport);
            },
      );
      addTearDown(composition.dispose);

      await composition.manager.connectTo(composition.peer);

      expect(attempts, [_configuredRelay, _pairedRelay]);
      expect(events, [
        'start:$_configuredRelay',
        'closed:$_configuredRelay',
        'start:$_pairedRelay',
      ]);
      expect(composition.manager.status, isA<StatusOnline>());
      expect(composition.manager.channel, isA<SecurePeerChannel>());
    },
  );

  test(
    'parent cancellation during primary attempt closes it and never starts paired alternate',
    () async {
      final attempts = <String>[];
      final primaryStarted = Completer<void>();
      final primaryClosed = Completer<void>();
      final pendingPrimary = Completer<PeerTransport>();
      final composition = await _buildComposition(
        connectTransport:
            ({
              required relayUrl,
              required peerPubkey,
              required ed25519Key,
              required deviceId,
              required activeRoom,
              required debugLog,
              required cancellation,
            }) {
              attempts.add(relayUrl);
              expect(relayUrl, _configuredRelay);
              primaryStarted.complete();
              cancellation.addCancellationListener(() async {
                if (!primaryClosed.isCompleted) primaryClosed.complete();
                if (!pendingPrimary.isCompleted) {
                  pendingPrimary.completeError(
                    const _FakeAttemptError('primary cancelled'),
                  );
                }
              });
              return pendingPrimary.future;
            },
      );
      addTearDown(composition.dispose);

      final connect = composition.manager.connectTo(composition.peer);
      await primaryStarted.future;
      await composition.manager.disconnect();
      await connect;
      await primaryClosed.future;

      expect(attempts, [_configuredRelay]);
      expect(composition.manager.status, isA<StatusNoPeer>());
      expect(composition.manager.channel, isNull);
    },
  );
}

Future<_Composition> _buildComposition({
  required ProductionTransportConnector connectTransport,
}) async {
  final peer = PeerRecord(
    remoteEpk: 'peer-for-production-seam',
    sessionName: 'Test Pi',
    relayUrl: _pairedRelay,
    pairedAt: '2026-08-26T00:00:00Z',
    channel: OwnerChannelState(
      sendKey: base64Encode(List<int>.filled(32, 1)),
      receiveKey: base64Encode(List<int>.filled(32, 2)),
    ),
  );
  final storage = _FakePairingStorage(peer);
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final ownerIdentity = OwnerIdentityBridge(
    InMemoryOwnerIdentityStore(
      initial: OwnerIdentity(
        ownerPk: Uint8List.fromList(publicKey.bytes),
        ownerSk: Uint8List.fromList(privateKey),
      ),
    ),
    storage,
    restoreGracePeriod: Duration.zero,
  );
  await ownerIdentity.boot();

  // Keep this graph aligned with setupDependencies(): the production factory
  // is the ConnectionManager factory, rather than a test-only wrapper around
  // the candidate loop.
  final factory = ProductionConnectionFactory(
    relayResolution: () => const ConfiguredRelay(_configuredRelay),
    storage: storage,
    ownerIdentity: ownerIdentity,
    deviceId: _FakeDeviceId(),
    debugLog: null,
    connectTransport: connectTransport,
  );
  return _Composition(
    peer: peer,
    manager: ConnectionManager(
      factory: factory.call,
      storage: storage,
      debugLog: null,
      emitDebounce: Duration.zero,
    ),
    ownerIdentity: ownerIdentity,
  );
}

class _Composition {
  final PeerRecord peer;
  final ConnectionManager manager;
  final OwnerIdentityBridge ownerIdentity;

  _Composition({
    required this.peer,
    required this.manager,
    required this.ownerIdentity,
  });

  void dispose() {
    manager.dispose();
    ownerIdentity.dispose();
  }
}

class _FakePairingStorage extends PairingStorage {
  final PeerRecord peer;

  _FakePairingStorage(this.peer);

  @override
  Future<PeerRecord?> loadPeer(String remoteEpk) async =>
      remoteEpk == peer.remoteEpk ? peer : null;

  @override
  Future<bool> hasPendingOwnerTransition() async => false;

  @override
  Future<String?> loadOwnerStateFingerprint() async => null;

  @override
  Future<String> initializeOwnerStateFingerprint(String fingerprint) async =>
      fingerprint;
}

class _FakeDeviceId extends DeviceId {
  @override
  Future<String> get() async => 'production-seam-test-device';
}

class _FakeTransport implements PeerTransport {
  final _receive = Completer<Uint8List>();
  int closeCalls = 0;

  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<Uint8List> receive() => _receive.future;

  @override
  Future<void> close() async {
    closeCalls++;
    if (!_receive.isCompleted) {
      _receive.completeError(const _FakeAttemptError('transport closed'));
    }
  }
}

class _FakeAttemptError implements Exception {
  final String message;
  const _FakeAttemptError(this.message);
}
