@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/pairing/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/secure_storage_fixture.dart';

const _seededTranscriptText = 'e2e persisted transcript';

void main() {
  test('pair_ok is followed by canonical transcript hydration', () async {
    final hiveDirectory = Directory.systemTemp.createTempSync(
      'outpost_pi_pairing_e2e_',
    );
    await LocalBoxes.initForTest(hiveDirectory.path);

    final endpoints = HarnessEndpoints.fromEnvironment();
    final host = PiHostClient(endpoints.piHost);
    final status = await host.restartForIsolation();
    final pairCode = await waitForPairCode(host);
    final secureStorage = SecureStorageFixture();
    final storage = PairingStorage(secureStorage);
    final stack = await PairingStack.connect(
      endpoints: endpoints,
      qr: pairCode.qr,
      storage: storage,
    );
    final paired = await stack.pair(deviceName: 'E2E Hydration Phone');
    final session = await stack.adoptAndHydrate(paired);

    addTearDown(() async {
      await session.close();
      await stack.close();
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    expect(session.sessionId, status.sessionId);
    expect(session.sessionId, isNotEmpty);
    expect(session.peer.roomId, status.roomId);

    session.sync.requestSync();
    final ref = RemoteSessionRef(
      peerEpk: session.peer.remoteEpk,
      roomId: session.peer.roomId!,
      sessionId: session.sessionId,
    );
    final rows = await eventually<List<MessageRecord>>(
      () async {
        final boxes = LocalBoxes();
        if (!boxes.isMsgsBoxOpen(ref)) return null;
        final records = <MessageRecord>[
          for (final value in boxes.openMsgsBox(ref).values)
            MessageRecord.fromJson((value as Map).cast<String, dynamic>()),
        ];
        return records.any(
              (row) =>
                  row.role == MsgRole.user &&
                  row.text == _seededTranscriptText &&
                  !row.pending,
            )
            ? records
            : null;
      },
      timeout: const Duration(seconds: 15),
      description: 'materialized seeded transcript row',
    );

    expect(
      rows,
      contains(
        isA<MessageRecord>()
            .having((row) => row.role, 'role', MsgRole.user)
            .having((row) => row.text, 'text', _seededTranscriptText)
            .having((row) => row.pending, 'pending', isFalse),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
