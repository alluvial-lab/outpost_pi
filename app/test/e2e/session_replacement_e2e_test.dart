@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/actions/actions_repository.dart';
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

const _preReplacementText = 'e2e pre-replacement message';
const _postReplacementText = 'e2e post-replacement message';

/// Regression net for `feature-replacement-session-wake-confirmation`: the
/// first message after `/new` must confirm promptly (not gate on the full
/// agent turn) and must land in the transcript exactly once (no
/// `sync_`-echo misattribution duplicate after the turn).
///
/// Harness limitations: (1) the pi-host's stubbed SDK settles turns
/// instantly, so the buggy *timing* symptom (confirmation delayed by the
/// awaited full-turn Promise) is only weakly observable here; (2) the
/// harness's stubbed `newSession` acks without rotating the SessionManager,
/// so the replacement keeps the same session id (production rotates it).
/// The robust assertions are the post-replacement wipe convergence, the
/// prompt-confirmation bound, and the exact-once transcript count; the live
/// timing regression was verified on-device in the fixing feature.
void main() {
  test(
    'message after session_new confirms promptly and lands exactly once',
    () async {
      final hiveDirectory = Directory.systemTemp.createTempSync(
        'outpost_pi_replacement_e2e_',
      );
      await LocalBoxes.initForTest(hiveDirectory.path);

      final endpoints = HarnessEndpoints.fromEnvironment();
      final host = PiHostClient(endpoints.piHost);
      await host.restartForIsolation();
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

      addTearDown(() async {
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

      Future<void> awaitConfirmedRow(
        RemoteSessionRef ref,
        String text, {
        required String description,
      }) async {
        await eventually<List<MessageRecord>>(
          () async {
            final rows = rowsFor(ref);
            return rows.any(
                  (row) =>
                      row.role == MsgRole.user &&
                      row.text == text &&
                      !row.pending,
                )
                ? rows
                : null;
          },
          timeout: const Duration(seconds: 15),
          description: description,
        );
      }

      // Baseline: a live-turn send on the original session confirms normally.
      // Proves the harness's live delivery path works before the replacement
      // is exercised, so a failure later is attributable to the replacement.
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

      // Session replacement via the production action path, then the same
      // local wipe the UI performs after the `session_new` ack.
      final actions = ActionsRepository(session.connection);
      await actions.newSession();
      await session.sync.clearActiveSession();

      // Post-replacement convergence: the extension fans out an empty
      // session_history on session_new, so the confirmed baseline row must
      // disappear. This gates the next send on the replacement having fully
      // propagated (no racing the wipe with the optimistic row). The harness
      // keeps the same session id — see the limitation note above.
      await eventually<bool>(
        () async {
          final rows = rowsFor(originalRef);
          return rows.any(
                (row) =>
                    row.role == MsgRole.user &&
                    row.text == _preReplacementText,
              )
              ? null
              : true;
        },
        timeout: const Duration(seconds: 10),
        description: 'post-replacement wipe of baseline row',
      );

      // The regression case: first message on the replacement session.
      await session.sync.sendMessage(_postReplacementText);
      final replacementRef = originalRef; // harness keeps the session id

      // (a) Prompt confirmation — bounded wait, not gated on a turn settling.
      await awaitConfirmedRow(
        replacementRef,
        _postReplacementText,
        description: 'confirmed post-replacement row',
      );

      // (b) Exactly one copy after everything settles (the bug's duplicate
      // arrived *after* the turn via echo misattribution).
      await Future<void>.delayed(const Duration(seconds: 5));
      final copies = rowsFor(replacementRef)
          .where(
            (row) => row.role == MsgRole.user && row.text == _postReplacementText,
          )
          .length;
      expect(
        copies,
        1,
        reason: 'post-replacement message must land exactly once',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
