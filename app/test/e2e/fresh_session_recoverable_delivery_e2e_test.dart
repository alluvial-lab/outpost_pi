@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/hive_owner_delivery_outbox.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/domain/entities/pending_owner_delivery.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/secure_storage_fixture.dart';

const _deliveryProbe = 'e2e recoverable delivery probe';

void main() {
  test(
    'quiesced prompt recovers once after a fresh preserving restart',
    () async {
      final hiveDirectory = Directory.systemTemp.createTempSync(
        'outpost_pi_recoverable_delivery_e2e_',
      );
      await LocalBoxes.initForTest(hiveDirectory.path);

      final endpoints = HarnessEndpoints.fromEnvironment();
      final host = PiHostClient(endpoints.piHost);
      final initialStatus = await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'E2E Recovery Phone');
      final session = await stack.adoptAndHydrate(paired);
      final outbox = HiveOwnerDeliveryOutbox(LocalBoxes());

      addTearDown(() async {
        await session.close();
        await stack.close();
        await Hive.close();
        await hiveDirectory.delete(recursive: true);
      });

      await session.ping();
      final quiescing = await host.beginDeliveryQuiesce();
      expect(quiescing.fenced, isTrue);
      expect(quiescing.sdkDeliveryCount, 0);

      await session.sync.sendMessage(_deliveryProbe);
      final pending = await eventually<PendingOwnerDelivery>(
        () async {
          final deliveries = await outbox.listForRoom(
            peerEpk: session.peer.remoteEpk,
            roomId: session.peer.roomId!,
          );
          return deliveries.length == 1 ? deliveries.single : null;
        },
        timeout: const Duration(seconds: 10),
        description: 'quiesced prompt persisted in owner outbox',
      );
      expect(pending.targetSessionId, initialStatus.sessionId);

      await eventually<bool>(
        () async {
          final control = await host.deliveryControlStatus();
          return control.fenced &&
                  control.sdkDeliveryCount == 0 &&
                  session.sync.debugPendingSendTimerCount == 0
              ? true
              : null;
        },
        timeout: const Duration(seconds: 10),
        description: 'delivery_retry reached SyncService without SDK delivery',
      );

      final successor = await host.restartForFreshSession();
      expect(successor.sessionId, isNot(initialStatus.sessionId));
      await eventually<bool>(
        () async {
          return session.connection.activeSessionId == successor.sessionId &&
                  session.connection.isRoomLive(
                    session.peer.remoteEpk,
                    session.peer.roomId!,
                  )
              ? true
              : null;
        },
        timeout: const Duration(seconds: 30),
        description: 'successor room and canonical session hydration',
      );

      await eventually<bool>(
        () async {
          final control = await host.deliveryControlStatus();
          return control.sdkDeliveryCount == 1 ? true : null;
        },
        timeout: const Duration(seconds: 15),
        description: 'one recovered SDK delivery',
      );
      await eventually<bool>(
        () async =>
            (await outbox.listForRoom(
              peerEpk: session.peer.remoteEpk,
              roomId: session.peer.roomId!,
            )).isEmpty
            ? true
            : null,
        timeout: const Duration(seconds: 15),
        description: 'matching successor confirmation cleared the outbox',
      );

      final successorRef = RemoteSessionRef(
        peerEpk: session.peer.remoteEpk,
        roomId: session.peer.roomId!,
        sessionId: successor.sessionId,
      );
      final rows = await eventually<List<MessageRecord>>(
        () async {
          final boxes = LocalBoxes();
          if (!boxes.isMsgsBoxOpen(successorRef)) return null;
          final matches = <MessageRecord>[
            for (final value in boxes.openMsgsBox(successorRef).values)
              MessageRecord.fromJson((value as Map).cast<String, dynamic>()),
          ].where((row) => row.id == pending.id).toList(growable: false);
          return matches.length == 1 &&
                  matches.single.role == MsgRole.user &&
                  matches.single.status == UserMsgStatus.confirmed
              ? matches
              : null;
        },
        timeout: const Duration(seconds: 15),
        description: 'one confirmed successor transcript row by stable id',
      );
      expect(rows.single.id, pending.id);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
