@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/secure_storage_fixture.dart';

void main() {
  test(
    'background lifecycle crosses extension, relay, and app room metadata',
    () async {
      final hiveDirectory = Directory.systemTemp.createTempSync(
        'outpost_pi_background_meta_e2e_',
      );
      await LocalBoxes.initForTest(hiveDirectory.path);

      final endpoints = HarnessEndpoints.fromEnvironment();
      final host = PiHostClient(endpoints.piHost);
      await host.restartForIsolation();
      final pairCode = await waitForPairCode(host);
      final storage = PairingStorage(SecureStorageFixture());
      final stack = await PairingStack.connect(
        endpoints: endpoints,
        qr: pairCode.qr,
        storage: storage,
      );
      final paired = await stack.pair(deviceName: 'Background Metadata Phone');
      final session = await stack.adoptAndHydrate(paired);
      final roomId = paired.peer.roomId!;
      final control = session.currentChannel as IControlLink;
      final backgroundFrames = <RoomMetaUpdated>[];
      final controlSubscription = control.controlFrames.listen((frame) {
        if (frame is RoomMetaUpdated &&
            frame.roomId == roomId &&
            frame.background != null) {
          backgroundFrames.add(frame);
        }
      });

      addTearDown(() async {
        await controlSubscription.cancel();
        await session.close();
        await stack.close();
        await Hive.close();
        if (hiveDirectory.existsSync()) {
          await hiveDirectory.delete(recursive: true);
        }
      });

      await _waitForRoom(session.connection, paired.peer.remoteEpk, roomId);
      // Drain initial announce/connect traffic before attributing frames to the
      // lifecycle actions below. The action suffix must contain only the
      // transition edges caused by this test.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final actionFrameBaseline = backgroundFrames.length;

      await host.emitBackgroundLifecycle(event: 'created', id: 'background-a');
      await _waitForBackground(
        session.connection,
        paired.peer.remoteEpk,
        roomId,
        expected: true,
        description: 'background=true after subagents:created',
      );
      await _waitForFrame(
        backgroundFrames,
        after: actionFrameBaseline,
        expected: true,
        description: 'room_meta_updated background=true through relay',
      );

      // A duplicate id and another active id must not publish another edge.
      await host.emitBackgroundLifecycle(event: 'created', id: 'background-a');
      await host.emitBackgroundLifecycle(event: 'created', id: 'background-b');
      await _assertNoNewFrames(backgroundFrames, actionFrameBaseline);
      expect(
        session.connection.roomsFor(paired.peer.remoteEpk).single.background,
        isTrue,
      );

      // One terminal event does not drain the set while the second id lives.
      await host.emitBackgroundLifecycle(
        event: 'completed',
        id: 'background-a',
      );
      await _assertNoNewFrames(backgroundFrames, actionFrameBaseline);
      expect(
        session.connection.roomsFor(paired.peer.remoteEpk).single.background,
        isTrue,
      );

      // `resumed` is a terminal lifecycle edge for the remaining id.
      await host.emitBackgroundLifecycle(event: 'resumed', id: 'background-b');
      await _waitForBackground(
        session.connection,
        paired.peer.remoteEpk,
        roomId,
        expected: false,
        description: 'background=false after subagents:resumed',
      );
      await _waitForFrame(
        backgroundFrames,
        after: actionFrameBaseline,
        expected: false,
        description: 'room_meta_updated background=false through relay',
      );

      // Exercise the failed terminal edge as a second complete 0→1→0 cycle.
      await host.emitBackgroundLifecycle(event: 'created', id: 'background-c');
      await _waitForBackground(
        session.connection,
        paired.peer.remoteEpk,
        roomId,
        expected: true,
        description: 'background=true for a second lifecycle cycle',
      );
      await host.emitBackgroundLifecycle(event: 'failed', id: 'background-c');
      await _waitForBackground(
        session.connection,
        paired.peer.remoteEpk,
        roomId,
        expected: false,
        description: 'background=false after subagents:failed',
      );

      final actionValues = backgroundFrames
          .skip(actionFrameBaseline)
          .map((frame) => frame.background)
          .toList(growable: false);
      expect(
        actionValues,
        <bool?>[true, false, true, false],
        reason:
            'the tracker publishes only 0↔n edges and the relay must retain '
            'background in its generated decode/merge/broadcast path',
      );
      expect(
        session.connection.roomsFor(paired.peer.remoteEpk).single.background,
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitForRoom(
  ConnectionManager connection,
  String peer,
  String roomId,
) async {
  await eventually<RoomInfo>(
    () async {
      for (final room in connection.roomsFor(peer)) {
        if (room.roomId == roomId) return room;
      }
      return null;
    },
    timeout: const Duration(seconds: 10),
    description: 'paired room snapshot',
  );
}

Future<void> _waitForBackground(
  ConnectionManager connection,
  String peer,
  String roomId, {
  required bool expected,
  required String description,
}) async {
  await eventually<bool>(
    () async {
      for (final room in connection.roomsFor(peer)) {
        if (room.roomId == roomId && room.background == expected) return true;
      }
      return null;
    },
    timeout: const Duration(seconds: 10),
    description: description,
  );
}

Future<void> _waitForFrame(
  List<RoomMetaUpdated> frames, {
  required int after,
  required bool expected,
  required String description,
}) async {
  await eventually<bool>(
    () async => frames.skip(after).any((frame) => frame.background == expected)
        ? true
        : null,
    timeout: const Duration(seconds: 10),
    description: description,
  );
}

Future<void> _assertNoNewFrames(
  List<RoomMetaUpdated> frames,
  int baseline,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  expect(
    frames.length,
    baseline + 1,
    reason: 'non-edge background lifecycle events must not publish metadata',
  );
}
