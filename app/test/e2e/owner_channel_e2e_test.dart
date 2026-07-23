import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/pi_host_inspector.dart';
import 'support/raw_owner_relay_client.dart';
import 'support/secure_storage_fixture.dart';
import 'support/toxiproxy_client.dart';

const _seededTranscriptText = 'e2e persisted transcript';

void main() {
  final endpoints = HarnessEndpoints.fromEnvironment();
  final host = PiHostClient(endpoints.piHost);
  final inspector = PiHostInspector.fromEnvironment();

  test(
    'pairing establishes a protected channel with a sealed round-trip',
    () async {
      final hiveDirectory = await _openHive('owner_channel_establishment');
      final status = await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final ownerPeer = await _ownerPublicKey(stack.ownerKey);
      final plaintextAuditBefore = await _auditCount(
        inspector,
        peer: ownerPeer,
        reason: 'plaintext_post_key',
      );
      final paired = await stack.pair(deviceName: 'Protected Channel Phone');
      final session = await stack.adoptAndHydrate(paired);
      addTearDown(() => _closeSession(session, stack, hiveDirectory));

      await session.ping();

      expect(session.protectedOutboundFrames, isNotEmpty);
      for (final frame in session.protectedOutboundFrames) {
        expect(frame.first, 0x01);
        expect(
          () => jsonDecode(utf8.decode(frame)),
          throwsA(anything),
          reason: 'protected ct bytes must not decode as plaintext JSON',
        );
      }
      final persisted = await session.persistedChannelState();
      expect(persisted.sendSequence, greaterThan(0));
      expect(persisted.receiveSequence, greaterThan(0));
      expect((await host.status()).state, 'paired');
      expect(status.roomId, paired.peer.roomId);
      expect(
        await _auditCount(
          inspector,
          peer: ownerPeer,
          reason: 'plaintext_post_key',
        ),
        plaintextAuditBefore,
        reason: 'a successful pairing must not produce a plaintext audit',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'forged sealed ct is dropped without dispatch and is audited',
    () async {
      final hiveDirectory = await _openHive('owner_channel_forgery');
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'Forged CT Phone');
      final session = await stack.adoptAndHydrate(paired);
      addTearDown(() => _closeSession(session, stack, hiveDirectory));
      await session.ping();

      final raw = await stack.openRawOwnerRelayClient();
      addTearDown(raw.close);
      final beforeEnvelopes = raw.deliveredEnvelopeCount;
      final ownerPeer = await _ownerPublicKey(stack.ownerKey);
      final auditBefore = await _auditCount(
        inspector,
        peer: ownerPeer,
        reason: 'open_failed',
      );
      final state = await session.persistedChannelState();
      final forged = await sealOwnerChannelFrame(
        key: Uint8List(32),
        sequence: state.sendSequence + 100,
        json: jsonEncode(<String, Object>{
          'type': 'user_message',
          'id': uuid7(),
          'session_id': session.sessionId,
          'text': 'must never dispatch',
        }),
      );
      raw.inject(
        piPublicKey: pairCode.qr.epk,
        piRoomId: pairCode.qr.roomId!,
        payload: forged,
      );

      expect(
        await _waitForNewAudit(
          inspector,
          peer: ownerPeer,
          reason: 'open_failed',
          afterCount: auditBefore,
        ),
        auditBefore + 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        raw.deliveredEnvelopeCount,
        beforeEnvelopes,
        reason: 'a forged user_message must not produce an echo or other reply',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'tampered dh_sig is rejected before token consumption or persistence',
    () async {
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      addTearDown(stack.close);

      final dh = await generateOwnerChannelKeyPair();
      try {
        final transcript = buildAppOwnerChannelTranscript(
          token: pairCode.qr.token,
          appDhPublicKey: dh.publicKey,
          piEdPublicKey: pairCode.qr.epkBytes,
        );
        final signature = await Ed25519().sign(
          transcript,
          keyPair: stack.ownerKey,
        );
        final tampered = Uint8List.fromList(signature.bytes)..[0] ^= 0x01;
        final ownerPublic = await stack.ownerKey.extractPublicKey();
        final proof = await buildOwnerChannelPairProof(
          token: pairCode.qr.token,
          ownerEdPublicKey: ownerPublic.bytes,
          appDhPublicKey: dh.publicKey,
          piEdPublicKey: pairCode.qr.epkBytes,
        );
        final request = PairRequest(
          id: uuid7(),
          tokenId: base64.encode(proof.tokenId),
          pairMac: base64.encode(proof.mac),
          deviceName: 'Tampered DH Phone',
          dhPk: base64.encode(dh.publicKey),
          dhSig: base64.encode(tampered),
        );
        final response = await stack.exchangePairingJson(request.toJson());
        expect(response['type'], 'pair_error');
        expect(response['code'], 'bad_dh_sig');
      } finally {
        dh.secretKey.fillRange(0, dh.secretKey.length, 0);
      }

      expect(await storage.listPeers(), isEmpty);
      expect(await inspector.peerCount(), 0);
      expect((await host.status()).state, 'started');

      final valid = await stack.pair(deviceName: 'Valid After Tampered DH');
      expect(await storage.loadPeer(valid.peer.remoteEpk), isNotNull);
      expect(await inspector.peerCount(), 1);
      expect((await host.status()).state, 'paired');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'pairing substitution is rejected without consuming the honest token',
    () async {
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      addTearDown(stack.close);
      final attackerKey = await Ed25519().newKeyPair();
      final attacker = await RawOwnerRelayClient.connect(
        relay: endpoints.relay,
        ownerKey: attackerKey,
        deviceId:
            'pairing-substitution-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(attacker.close);

      final attackerDh = await generateOwnerChannelKeyPair();
      try {
        final paired = await stack.pair(
          deviceName: 'Honest After Substitution',
          beforeRequestSend: (observed) async {
            final attackerTranscript = buildAppOwnerChannelTranscript(
              token: pairCode.qr.token,
              appDhPublicKey: attackerDh.publicKey,
              piEdPublicKey: pairCode.qr.epkBytes,
            );
            final attackerSignature = await Ed25519().sign(
              attackerTranscript,
              keyPair: attackerKey,
            );
            final forged = PairRequest(
              id: uuid7(),
              tokenId: observed['token_id']! as String,
              pairMac: observed['pair_mac']! as String,
              deviceName: 'Substitution Attacker',
              dhPk: base64.encode(attackerDh.publicKey),
              dhSig: base64.encode(attackerSignature.bytes),
            );
            final response = await attacker.exchangePairingJson(
              piPublicKey: pairCode.qr.epk,
              piRoomId: pairCode.qr.roomId!,
              request: forged.toJson(),
            );
            expect(response['type'], 'pair_error');
            expect(response['code'], 'token_unknown');
            expect(await inspector.peerCount(), 0);
            expect((await host.status()).state, 'started');
          },
        );

        expect(await storage.loadPeer(paired.peer.remoteEpk), isNotNull);
        expect(await inspector.peerCount(), 1);
        expect((await host.status()).state, 'paired');
      } finally {
        attackerDh.secretKey.fillRange(0, attackerDh.secretKey.length, 0);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'plaintext post-key frame is dropped without dispatch and is audited',
    () async {
      final hiveDirectory = await _openHive('owner_channel_plaintext');
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'Plaintext Rejection Phone');
      final session = await stack.adoptAndHydrate(paired);
      addTearDown(() => _closeSession(session, stack, hiveDirectory));
      await session.ping();

      final raw = await stack.openRawOwnerRelayClient();
      addTearDown(raw.close);
      final beforeEnvelopes = raw.deliveredEnvelopeCount;
      final ownerPeer = await _ownerPublicKey(stack.ownerKey);
      final auditBefore = await _auditCount(
        inspector,
        peer: ownerPeer,
        reason: 'plaintext_post_key',
      );
      raw.inject(
        piPublicKey: pairCode.qr.epk,
        piRoomId: pairCode.qr.roomId!,
        payload: utf8.encode(jsonEncode(Ping(id: uuid7()).toJson())),
      );

      expect(
        await _waitForNewAudit(
          inspector,
          peer: ownerPeer,
          reason: 'plaintext_post_key',
          afterCount: auditBefore,
        ),
        auditBefore + 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        raw.deliveredEnvelopeCount,
        beforeEnvelopes,
        reason: 'a plaintext ping must not dispatch a pong',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'sealed channel and session_sync recover after relay reconnect',
    () async {
      final hiveDirectory = await _openHive('owner_channel_reconnect');
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'Reconnect Phone');
      final session = await stack.adoptAndHydrate(paired);
      addTearDown(() => _closeSession(session, stack, hiveDirectory));
      await session.ping();
      final before = await session.persistedChannelState();
      final pairedEventsBefore = await _pairedEventCount(host);

      final proxy = ToxiproxyClient(endpoints.toxiproxy);
      await proxy.setAppRelayEnabled(false);
      addTearDown(() => proxy.setAppRelayEnabled(true));
      await eventually<bool>(
        () async => session.connection.status is StatusOnline ? null : true,
        timeout: const Duration(seconds: 10),
        description: 'owner channel relay disconnect',
      );
      await proxy.setAppRelayEnabled(true);
      await eventually<bool>(
        () async => session.connection.status is StatusOnline ? true : null,
        timeout: const Duration(seconds: 20),
        description: 'owner channel relay reconnect',
      );

      await session.ping();
      session.sync.requestSync();
      final ref = RemoteSessionRef(
        peerEpk: session.peer.remoteEpk,
        roomId: session.peer.roomId!,
        sessionId: session.sessionId,
      );
      await eventually<List<MessageRecord>>(
        () async {
          final boxes = LocalBoxes();
          if (!boxes.isMsgsBoxOpen(ref)) return null;
          final rows = <MessageRecord>[
            for (final value in boxes.openMsgsBox(ref).values)
              MessageRecord.fromJson((value as Map).cast<String, dynamic>()),
          ];
          return rows.any(
                (row) =>
                    row.role == MsgRole.user &&
                    row.text == _seededTranscriptText &&
                    !row.pending,
              )
              ? rows
              : null;
        },
        timeout: const Duration(seconds: 15),
        description: 'sealed reconnect session_sync hydration',
      );

      final after = await session.persistedChannelState();
      expect(after.sendSequence, greaterThan(before.sendSequence));
      expect(after.receiveSequence, greaterThan(before.receiveSequence));
      expect(await _pairedEventCount(host), pairedEventsBefore);
      expect((await host.status()).state, 'paired');
      expect(
        session.protectedOutboundFrames,
        everyElement(predicate<Uint8List>((frame) => frame.first == 0x01)),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<Directory> _openHive(String name) async {
  final directory = Directory.systemTemp.createTempSync('outpost_pi_$name');
  await LocalBoxes.initForTest(directory.path);
  return directory;
}

Future<void> _closeSession(
  HydratedSession session,
  PairingStack stack,
  Directory hiveDirectory,
) async {
  await session.close();
  await stack.close();
  await Hive.close();
  if (hiveDirectory.existsSync()) await hiveDirectory.delete(recursive: true);
}

Future<String> _ownerPublicKey(SimpleKeyPair key) async =>
    base64.encode((await key.extractPublicKey()).bytes);

Future<int> _auditCount(
  PiHostInspector inspector, {
  required String peer,
  required String reason,
}) async => (await inspector.ownerChannelAudit())
    .where((event) => event['peer'] == peer && event['reason'] == reason)
    .length;

Future<int> _waitForNewAudit(
  PiHostInspector inspector, {
  required String peer,
  required String reason,
  required int afterCount,
}) => eventually<int>(
  () async {
    final count = await _auditCount(inspector, peer: peer, reason: reason);
    return count > afterCount ? count : null;
  },
  timeout: const Duration(seconds: 10),
  description: 'new owner-channel $reason audit event',
);

Future<int> _pairedEventCount(PiHostClient host) async =>
    (await host.eventsAfter(0)).where((event) {
      final payload = event.payload;
      return event.kind == 'tui_message' &&
          payload is Map<String, dynamic> &&
          payload['customType'] == 'outpost-pi:paired';
    }).length;
