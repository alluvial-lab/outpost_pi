import 'dart:convert';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/hive_owner_delivery_outbox.dart';
import 'package:app/domain/entities/pending_owner_delivery.dart';
import 'package:app/domain/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('HiveOwnerDeliveryOutbox', () {
    late Directory directory;
    late HiveOwnerDeliveryOutbox outbox;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('owner_outbox_');
      await LocalBoxes.initForTest(directory.path);
      outbox = HiveOwnerDeliveryOutbox(LocalBoxes());
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    PendingOwnerDelivery delivery({String? targetSessionId = 'session-old'}) =>
        PendingOwnerDelivery(
          id: 'cli-stable',
          peerEpk: 'peer-a',
          roomId: 'room-a',
          targetSessionId: targetSessionId,
          text: 'recover me',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
          image: const MessageImage(data: 'aW1hZ2U=', mime: 'image/jpeg'),
          awaitingPickup: true,
        );

    test('encrypted common box survives close and reopen', () async {
      await outbox.upsert(delivery());
      final box = LocalBoxes().ownerDeliveryOutboxBox();
      await box.flush();
      final path = box.path;
      expect(path, isNotNull);
      expect(
        _containsBytes(
          await File(path!).readAsBytes(),
          utf8.encode('recover me'),
        ),
        isFalse,
        reason: 'prompt plaintext must not appear in the Hive file',
      );
      await Hive.close();
      await LocalBoxes.initForTest(directory.path);

      final reopened = HiveOwnerDeliveryOutbox(LocalBoxes());
      expect(
        await reopened.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        <PendingOwnerDelivery>[delivery()],
      );
    });

    test('confirmation removes only the matching durable target', () async {
      await outbox.upsert(delivery());

      await outbox.removeConfirmed(
        id: 'cli-stable',
        confirmedSessionId: 'session-stale',
      );
      expect(
        await outbox.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        hasLength(1),
      );

      final retargeted = delivery().target('session-new');
      await outbox.upsert(retargeted);
      await outbox.removeConfirmed(
        id: 'cli-stable',
        confirmedSessionId: 'session-old',
      );
      expect(
        await outbox.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        <PendingOwnerDelivery>[retargeted],
      );

      await outbox.removeConfirmed(
        id: 'cli-stable',
        confirmedSessionId: 'session-new',
      );
      expect(
        await outbox.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        isEmpty,
      );
    });

    test('malformed rows fail closed instead of disappearing', () async {
      await LocalBoxes().ownerDeliveryOutboxBox().put('bad', <String, Object?>{
        'version': 1,
        'id': 'cli-bad',
        'peer_epk': 'peer-a',
        'room_id': 'room-a',
        'target_session_id': 'session-a',
        'text': 'bad',
        'created_at_ms': -1,
        'awaiting_pickup': false,
      });

      await expectLater(
        outbox.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        throwsFormatException,
      );
    });

    test('Owner-transition wipe clears the encrypted outbox', () async {
      await outbox.upsert(delivery());

      await LocalBoxes.wipeTranscriptsForOwnerTransition();

      expect(
        await outbox.listForRoom(peerEpk: 'peer-a', roomId: 'room-a'),
        isEmpty,
      );
    });
  });
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var start = 0; start <= haystack.length - needle.length; start += 1) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset += 1) {
      if (haystack[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
