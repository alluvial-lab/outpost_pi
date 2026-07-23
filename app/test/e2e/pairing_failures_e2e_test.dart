import 'dart:async';
import 'dart:convert';

import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/failure_log_redaction.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/secure_storage_fixture.dart';
import 'support/toxiproxy_client.dart';

const _seededTranscriptText = 'e2e persisted transcript';

void main() {
  final endpoints = HarnessEndpoints.fromEnvironment();
  final host = PiHostClient(endpoints.piHost);

  test(
    'invalid relay auth closes before pairing and preserves the token',
    () async {
      final redaction = FailureLogRedactionCanary.start();
      addTearDown(redaction.verify);
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      await _registerPairingCanaries(redaction, pairCode);

      await redaction.register(await _attemptInvalidRelayAuth(endpoints.relay));

      final storage = PairingStorage(SecureStorageFixture());
      expect(await storage.listPeers(), isEmpty);
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      addTearDown(stack.close);
      final result = await stack.pair(deviceName: 'Valid After Bad Auth');
      expect(await storage.loadPeer(result.peer.remoteEpk), isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'single-use token reports token_consumed to a second valid proof-holder',
    () async {
      final redaction = FailureLogRedactionCanary.start();
      addTearDown(redaction.verify);
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      await _registerPairingCanaries(redaction, pairCode);
      final firstStorage = PairingStorage(SecureStorageFixture());
      final first = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: firstStorage,
      );
      addTearDown(first.close);
      final accepted = await first.pair(deviceName: 'First Owner');
      final firstRecord = await firstStorage.loadPeer(accepted.peer.remoteEpk);

      final secondStorage = PairingStorage(SecureStorageFixture());
      final second = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: secondStorage,
      );
      addTearDown(second.close);
      await expectLater(
        second.pair(deviceName: 'Second Owner'),
        throwsA(
          isA<PairingError>().having(
            (error) => error.code,
            'code',
            'token_consumed',
          ),
        ),
      );

      expect(await secondStorage.listPeers(), isEmpty);
      expect(await firstStorage.loadPeer(accepted.peer.remoteEpk), firstRecord);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'expired token reports token_expired to its valid proof-holder',
    () async {
      final redaction = FailureLogRedactionCanary.start();
      addTearDown(redaction.verify);
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host, args: 'pair --ttl 10');
      await _registerPairingCanaries(redaction, pairCode);
      final remaining = pairCode.expiresAt.difference(DateTime.now());
      if (!remaining.isNegative) {
        await Future<void>.delayed(
          remaining + const Duration(milliseconds: 100),
        );
      }

      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      addTearDown(stack.close);
      await expectLater(
        stack.pair(deviceName: 'Expired Owner'),
        throwsA(
          isA<PairingError>().having(
            (error) => error.code,
            'code',
            'token_expired',
          ),
        ),
      );
      expect(await storage.listPeers(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'relay unavailable after QR fails boundedly and saves no peer',
    () async {
      final redaction = FailureLogRedactionCanary.start();
      addTearDown(redaction.verify);
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      await _registerPairingCanaries(redaction, pairCode);
      final proxy = ToxiproxyClient(endpoints.toxiproxy);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      addTearDown(stack.close);
      await proxy.setAppRelayEnabled(false);
      addTearDown(() => proxy.setAppRelayEnabled(true));

      await expectLater(
        stack.pair(deviceName: 'Interrupted Owner'),
        throwsA(
          anyOf(isA<WsTransportError>(), isA<WebSocketChannelException>()),
        ),
      );
      expect(await storage.listPeers(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _registerPairingCanaries(
  FailureLogRedactionCanary redaction,
  PairCodeObservation pairCode,
) => redaction.register(<String, String>{
  'qr-secret': pairCode.qr.token,
  'qr-uri': pairCode.uri,
  'pi-public-key': pairCode.qr.epk,
  'transcript': _seededTranscriptText,
});

Future<Map<String, String>> _attemptInvalidRelayAuth(Uri relay) async {
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final channel = IOWebSocketChannel.connect(Uri.parse(toWsRelayUrl('$relay')));
  await channel.ready;
  final iterator = StreamIterator<dynamic>(channel.stream);
  channel.sink.add(
    jsonEncode(<String, Object>{
      'type': 'hello',
      'pubkey': base64.encode(publicKey.bytes),
      'device_id': 'pairing-e2e-invalid-auth',
      'room_id': 'main',
    }),
  );
  expect(await iterator.moveNext().timeout(const Duration(seconds: 5)), isTrue);
  final challenge =
      jsonDecode(iterator.current as String) as Map<String, dynamic>;
  expect(challenge['type'], 'challenge');
  final nonceBase64 = challenge['nonce'] as String;
  final nonce = base64.decode(nonceBase64);
  final wrongSignature = await Ed25519().sign(<int>[
    ...utf8.encode('wrong-relay-auth-context\n'),
    ...nonce,
  ], keyPair: keyPair);
  final signatureBase64 = base64.encode(wrongSignature.bytes);
  channel.sink.add(
    jsonEncode(<String, Object>{'type': 'auth', 'sig': signatureBase64}),
  );
  expect(
    await iterator.moveNext().timeout(const Duration(seconds: 5)),
    isFalse,
  );
  await iterator.cancel();
  await channel.sink.close();
  return <String, String>{
    'auth-nonce': nonceBase64,
    'auth-signature': signatureBase64,
    'auth-public-key': base64.encode(publicKey.bytes),
    'auth-private-key': base64.encode(privateKey),
  };
}
