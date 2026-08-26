import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('LocalBoxes.discardUnreadableTranscripts', () {
    late Directory directory;
    late _MemoryKeyStore keyStore;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('transcript_recovery_');
      keyStore = _MemoryKeyStore();
      await LocalBoxes.initForTest(directory.path);
    });

    tearDown(() async {
      LocalBoxes.afterTranscriptRecoveryBoxDeleteForTesting = null;
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test(
      'key detection is fail-closed and does not delete ciphertext',
      () async {
        const eventKey = TranscriptSessionKey(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'session',
        );
        final eventsName = LocalBoxes.transcriptEventsBoxName(eventKey);
        await (await LocalBoxes().transcriptEventsBox(
          eventKey,
        )).put('event', {'text': 'ciphertext'});
        await Hive.box<dynamic>(
          'transcript_security_meta',
        ).put('key_verifier_v3', 'different-key');
        await Hive.close();

        await expectLater(
          LocalBoxes.initForTest(
            directory.path,
            encryptionKey: List<int>.filled(32, 9),
          ),
          throwsA(
            isA<TranscriptStorageKeyException>().having(
              (error) => error.code,
              'code',
              'key_mismatch',
            ),
          ),
        );

        expect(await Hive.boxExists(eventsName), isTrue);
      },
    );

    test('explicit discard removes only encrypted transcript data', () async {
      const ref = RemoteSessionRef(
        peerEpk: 'peer',
        roomId: 'room',
        sessionId: 'session',
      );
      const eventKey = TranscriptSessionKey(
        peerId: 'peer',
        roomId: 'room',
        sessionId: 'session',
      );
      final eventsName = LocalBoxes.transcriptEventsBoxName(eventKey);
      final messagesName = LocalBoxes.msgsBoxName(ref);
      const orphanName = 'transcript_events_v3_orphan';
      await (await LocalBoxes().transcriptEventsBox(
        eventKey,
      )).put('event', {'text': 'encrypted transcript'});
      await (await LocalBoxes().msgsBox(
        ref,
      )).put(0, {'text': 'encrypted projection'});
      await (await Hive.openBox<dynamic>(
        orphanName,
      )).put('event', {'text': 'orphan'});
      final outbox = LocalBoxes().ownerDeliveryOutboxBox();
      await outbox.put('delivery', {'text': 'unconfirmed'});
      final outboxName = outbox.name;
      await LocalBoxes().runtimeBox().put('room', {'online': true});
      final unrelated = await Hive.openBox<dynamic>('pairings');
      await unrelated.put('peer', 'retain me');
      final metadata = Hive.box<dynamic>('transcript_security_meta');
      await metadata.put('key_provisioned_v3', true);
      await metadata.put('key_verifier_v3', 'verifier');
      await metadata.put('migration_version', 3);

      await LocalBoxes.discardUnreadableTranscripts(keyStore: keyStore);

      expect(await Hive.boxExists('sessions_index_v3'), isFalse);
      expect(await Hive.boxExists('runtime'), isFalse);
      expect(await Hive.boxExists(outboxName), isFalse);
      expect(await Hive.boxExists(eventsName), isFalse);
      expect(await Hive.boxExists(messagesName), isFalse);
      expect(await Hive.boxExists(orphanName), isFalse);
      expect(await Hive.boxExists('pairings'), isTrue);
      expect(Hive.box<dynamic>('pairings').get('peer'), 'retain me');
      expect(metadata.get('key_provisioned_v3'), isNull);
      expect(metadata.get('key_verifier_v3'), isNull);
      expect(metadata.get('migration_version'), 3);
      expect(metadata.get('transcript_discard_pending_v3'), isNull);
      expect(keyStore.deleteCalls, 1);
    });

    test('a latched partial discard converges during the next init', () async {
      const ref = RemoteSessionRef(
        peerEpk: 'peer',
        roomId: 'room',
        sessionId: 'session',
      );
      final messagesName = LocalBoxes.msgsBoxName(ref);
      await (await LocalBoxes().msgsBox(ref)).put(0, {'text': 'old'});
      var deletions = 0;
      LocalBoxes.afterTranscriptRecoveryBoxDeleteForTesting = (_) async {
        deletions += 1;
        if (deletions == 1) throw StateError('injected recovery interruption');
      };

      await expectLater(
        LocalBoxes.discardUnreadableTranscripts(keyStore: keyStore),
        throwsA(isA<StateError>()),
      );
      final metadata = Hive.box<dynamic>('transcript_security_meta');
      expect(metadata.get('transcript_discard_pending_v3'), isTrue);

      LocalBoxes.afterTranscriptRecoveryBoxDeleteForTesting = null;
      await Hive.close();
      await LocalBoxes.initForTest(directory.path, keyStore: keyStore);

      expect(await Hive.boxExists(messagesName), isFalse);
      expect(
        Hive.box<dynamic>(
          'transcript_security_meta',
        ).get('transcript_discard_pending_v3'),
        isNull,
      );
      expect(keyStore.deleteCalls, 1);
      expect(LocalBoxes().sessionsIndexBox(), isEmpty);
    });
  });
}

final class _MemoryKeyStore implements TranscriptKeyValueStore {
  int deleteCalls = 0;

  @override
  Future<void> delete() async => deleteCalls += 1;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String encodedKey) async {}
}
