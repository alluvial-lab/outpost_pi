@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
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

const _preReplacementText = 'e2e pre-replacement message';
const _postReplacementText = 'e2e post-replacement message';

/// Prove the first message after a real SDK session rotation confirms under its
/// original client id before the replacement turn's Future settles.
void main() {
  test(
    'real replacement confirms cli id before replacement turn settles',
    () async {
      final hiveDirectory = Directory.systemTemp.createTempSync(
        'outpost_pi_replacement_e2e_',
      );
      await LocalBoxes.initForTest(hiveDirectory.path);

      final endpoints = HarnessEndpoints.fromEnvironment();
      final host = PiHostClient(endpoints.piHost);
      final initialStatus = await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final secureStorage = SecureStorageFixture();
      final storage = PairingStorage(secureStorage);
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'E2E Replacement Phone');
      final session = await stack.adoptAndHydrate(paired);
      final actions = ActionsRepository(session.connection);

      addTearDown(() async {
        actions.dispose();
        await session.close();
        await stack.close();
        await Hive.close();
        await hiveDirectory.delete(recursive: true);
      });

      List<MessageRecord> rowsFor(RemoteSessionRef ref) {
        final boxes = LocalBoxes();
        if (!boxes.isMsgsBoxOpen(ref)) return const <MessageRecord>[];
        return <MessageRecord>[
          for (final value in boxes.openMsgsBox(ref).values)
            MessageRecord.fromJson((value as Map).cast<String, dynamic>()),
        ];
      }

      Future<MessageRecord> awaitConfirmedRow(
        RemoteSessionRef ref,
        String text, {
        required String description,
      }) => eventually<MessageRecord>(
        () async {
          for (final row in rowsFor(ref)) {
            if (row.role == MsgRole.user &&
                row.text == text &&
                row.status == UserMsgStatus.confirmed) {
              return row;
            }
          }
          return null;
        },
        timeout: const Duration(seconds: 15),
        description: description,
      );

      // Baseline the original production delivery path before replacement.
      await session.sync.sendMessage(_preReplacementText);
      final originalRef = RemoteSessionRef(
        peerEpk: session.peer.remoteEpk,
        roomId: session.peer.roomId!,
        sessionId: session.sessionId,
      );
      await awaitConfirmedRow(
        originalRef,
        _preReplacementText,
        description: 'confirmed pre-replacement row',
      );

      await actions.newSession();
      await session.sync.clearActiveSession();

      final replacementSessionId = await eventually<String>(
        () async {
          final hostSessionId = (await host.status()).sessionId;
          final appSessionId = session.connection.activeSessionId;
          if (hostSessionId == initialStatus.sessionId ||
              appSessionId == null ||
              appSessionId != hostSessionId) {
            return null;
          }
          return hostSessionId;
        },
        timeout: const Duration(seconds: 15),
        description: 'real replacement session id on host and app',
      );
      final replacementRef = RemoteSessionRef(
        peerEpk: session.peer.remoteEpk,
        roomId: session.peer.roomId!,
        sessionId: replacementSessionId,
      );
      expect(replacementRef, isNot(originalRef));
      await eventually<bool>(
        () async =>
            session.sync.activeSessionRef == replacementRef ? true : null,
        timeout: const Duration(seconds: 10),
        description: 'SyncService replacement-session writer binding',
      );
      await session.ping();

      expect((await host.deferNextTurn()).phase, 'armed');
      await session.sync.sendMessage(_postReplacementText);
      await eventually<bool>(
        () async =>
            (await host.turnControlStatus()).phase == 'pending' ? true : null,
        timeout: const Duration(seconds: 10),
        description: 'deferred replacement turn entered',
      );
      await host.deliveryControlStatus();

      // The SDK message_end event occurs while sendUserMessage is still held.
      // It must confirm the original optimistic cli_ row immediately.
      final confirmedBeforeSettlement = await awaitConfirmedRow(
        replacementRef,
        _postReplacementText,
        description: 'cli confirmation before deferred turn settlement',
      );
      expect(confirmedBeforeSettlement.id, startsWith('cli_'));
      expect(session.sync.debugPendingSendTimerCount, 0);
      final beforeSettlement = rowsFor(
        replacementRef,
      ).where((row) => row.text == _postReplacementText).toList();
      expect(beforeSettlement, hasLength(1));
      expect(beforeSettlement.single.id, isNot(startsWith('sync_')));
      expect(beforeSettlement.single.status, UserMsgStatus.confirmed);

      await host.resolveDeferredTurn();
      await eventually<bool>(
        () async =>
            (await host.turnControlStatus()).phase == 'settled' ? true : null,
        timeout: const Duration(seconds: 10),
        description: 'deferred replacement turn settlement',
      );

      final settledRows = await eventually<List<MessageRecord>>(
        () async {
          final rows = rowsFor(
            replacementRef,
          ).where((row) => row.text == _postReplacementText).toList();
          return rows.length == 1 &&
                  rows.single.status == UserMsgStatus.confirmed
              ? rows
              : null;
        },
        timeout: const Duration(seconds: 10),
        description: 'exactly-once settled replacement transcript',
      );
      expect(settledRows.single.id, confirmedBeforeSettlement.id);
      expect(settledRows.single.id, isNot(startsWith('sync_')));
      expect(session.sync.debugPendingSendTimerCount, 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
