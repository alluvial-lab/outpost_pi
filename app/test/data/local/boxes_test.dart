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
      LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
      LocalBoxes.afterOwnerTransitionBoxDeleteForTesting = null;
      LocalBoxes.beforeTranscriptBoxOpenForTesting = null;
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
      'a failure before common clearing stays latched and init retries it',
      () async {
        const ref = RemoteSessionRef(
          peerEpk: 'failure-peer',
          roomId: 'failure-room',
          sessionId: 'failure-session',
        );
        final messagesName = LocalBoxes.msgsBoxName(ref);
        await (await boxes.msgsBox(ref)).put(0, {'text': 'prior owner'});
        LocalBoxes.beforeOwnerTransitionCommonClearForTesting = () async {
          throw StateError('injected before common clear');
        };

        await expectLater(
          LocalBoxes.wipeTranscriptsForOwnerTransition(),
          throwsA(isA<StateError>()),
        );
        final metadata = Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        expect(metadata.get('owner_transition_wipe_pending'), isTrue);

        LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
        await LocalBoxes.init();

        expect(metadata.get('owner_transition_wipe_pending'), isNull);
        expect(await Hive.boxExists(messagesName), isFalse);
        expect(boxes.sessionsIndexBox(), isEmpty);
        expect(boxes.runtimeBox(), isEmpty);
      },
    );

    test(
      'a partial per-session deletion stays latched and retry converges',
      () async {
        const first = RemoteSessionRef(
          peerEpk: 'partial-peer',
          roomId: 'partial-room',
          sessionId: 'partial-one',
        );
        const second = RemoteSessionRef(
          peerEpk: 'partial-peer',
          roomId: 'partial-room',
          sessionId: 'partial-two',
        );
        final firstName = LocalBoxes.msgsBoxName(first);
        final secondName = LocalBoxes.msgsBoxName(second);
        await (await boxes.msgsBox(first)).put(0, {'text': 'first'});
        await (await boxes.msgsBox(second)).put(0, {'text': 'second'});
        var deleted = 0;
        LocalBoxes.afterOwnerTransitionBoxDeleteForTesting = (_) async {
          deleted += 1;
          if (deleted == 1) throw StateError('injected during deletion');
        };

        await expectLater(
          LocalBoxes.wipeTranscriptsForOwnerTransition(),
          throwsA(isA<StateError>()),
        );
        final metadata = Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        expect(metadata.get('owner_transition_wipe_pending'), isTrue);

        LocalBoxes.afterOwnerTransitionBoxDeleteForTesting = null;
        await LocalBoxes.init();

        expect(metadata.get('owner_transition_wipe_pending'), isNull);
        expect(await Hive.boxExists(firstName), isFalse);
        expect(await Hive.boxExists(secondName), isFalse);
        expect(boxes.sessionsIndexBox(), isEmpty);
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
