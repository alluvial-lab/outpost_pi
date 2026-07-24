import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/transcript_storage_migration.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('LocalBoxes.wipeTranscriptsForOwnerTransition', () {
    late Directory directory;
    late LocalBoxes boxes;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('owner_transition_');
      await LocalBoxes.initForTest(directory.path);
      boxes = LocalBoxes();
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test(
      'wipes same-tuple transcript boxes while retaining security metadata',
      () async {
        const ref = RemoteSessionRef(
          peerEpk: 'same-peer',
          roomId: 'same-room',
          sessionId: 'same-session',
        );
        const eventKey = TranscriptSessionKey(
          peerId: 'same-peer',
          roomId: 'same-room',
          sessionId: 'same-session',
        );
        final index = SessionIndexRecord(
          epk: ref.peerEpk,
          roomId: ref.roomId,
          sessionId: ref.sessionId,
        );
        final oldEventsName = LocalBoxes.transcriptEventsBoxName(eventKey);
        final oldMessagesName = LocalBoxes.msgsBoxName(ref);
        await boxes.sessionsIndexBox().put(index.key, index.toJson());
        await (await boxes.transcriptEventsBox(
          eventKey,
        )).put('old-event', {'event_id': 'old-event'});
        await (await boxes.msgsBox(ref)).put(0, {'text': 'old transcript'});
        await boxes.runtimeBox().put('same-peer:same-room', {'online': true});

        final metadata = Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        final verifier = metadata.get('key_verifier_v3');
        await metadata.put('key_provisioned_v3', true);
        await metadata.put(TranscriptStorageMigrator.migrationVersionKey, 999);

        await LocalBoxes.wipeTranscriptsForOwnerTransition();

        expect(LocalBoxes.transcriptEventsBoxName(eventKey), oldEventsName);
        expect(LocalBoxes.msgsBoxName(ref), oldMessagesName);
        expect(boxes.sessionsIndexBox(), isEmpty);
        expect(boxes.runtimeBox(), isEmpty);
        expect((await boxes.transcriptEventsBox(eventKey)), isEmpty);
        expect((await boxes.msgsBox(ref)), isEmpty);
        expect(metadata.get('key_verifier_v3'), verifier);
        expect(metadata.get('key_provisioned_v3'), isTrue);
        expect(
          metadata.get(TranscriptStorageMigrator.migrationVersionKey),
          999,
        );

        // Identity B can reuse the same tuple but starts with only its own rows.
        await boxes.sessionsIndexBox().put(index.key, index.toJson());
        final replacementMessages = await boxes.msgsBox(ref);
        await replacementMessages.put(0, {'text': 'replacement transcript'});
        expect(replacementMessages.get(0), {'text': 'replacement transcript'});
      },
    );

    test(
      'deletes an orphan event box absent from the sessions index',
      () async {
        const orphan = TranscriptSessionKey(
          peerId: 'orphan-peer',
          roomId: 'orphan-room',
          sessionId: 'orphan-session',
        );
        final orphanName = LocalBoxes.transcriptEventsBoxName(orphan);
        await (await boxes.transcriptEventsBox(
          orphan,
        )).put('old-event', {'event_id': 'old-event'});
        expect(boxes.sessionsIndexBox(), isEmpty);

        await LocalBoxes.wipeTranscriptsForOwnerTransition();

        expect(await Hive.boxExists(orphanName), isFalse);
      },
    );
  });
}
