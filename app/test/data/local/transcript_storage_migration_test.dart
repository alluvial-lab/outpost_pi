import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/local/transcript_storage_migration.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('TranscriptStorageMigrator', () {
    late Directory directory;
    final encryptionKey = List<int>.generate(32, (index) => index);

    setUp(() {
      directory = Directory.systemTemp.createTempSync('transcript_migration_');
      Hive.init(directory.path);
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test(
      'migrates indexed events and remains idempotent across restart',
      () async {
        final session = _session('peer-one', 'main', 'session-one');
        final event = UserMessageConfirmed(
          eventId: 'event-one',
          sessionId: session.sessionId,
          ts: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          clientMessageId: 'message-one',
          text: 'preserved plaintext history',
        );
        await _seedIndex([session]);
        final legacyEvents = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.legacyEventsBoxName(session.ref),
        );
        await legacyEvents.put(
          event.eventId,
          TranscriptEventRecord.fromEvent(event, 0).toJson(),
        );
        final eventSourceName = legacyEvents.name;
        await Hive.close();

        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: encryptionKey,
        );
        final boxes = LocalBoxes();
        final migrated = await HiveTranscriptEventStore(
          boxes,
        ).readSession(_transcriptKey(session));
        expect(migrated.map((item) => item.eventId), ['event-one']);
        expect(
          (migrated.single as UserMessageConfirmed).text,
          'preserved plaintext history',
        );
        expect(
          SessionIndexRecord.fromJson(
            (boxes.sessionsIndexBox().get(session.key) as Map)
                .cast<String, dynamic>(),
          ),
          session,
        );
        expect(await Hive.boxExists(eventSourceName), isFalse);
        expect(
          await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
          isFalse,
        );
        expect(
          Hive.box<dynamic>(
            TranscriptStorageMigrator.metadataBoxName,
          ).get(TranscriptStorageMigrator.migrationVersionKey),
          TranscriptStorageMigrator.migrationVersion,
        );

        final firstEventIds = migrated.map((item) => item.eventId).toList();
        await Hive.close();
        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: encryptionKey,
        );
        final afterRestart = await HiveTranscriptEventStore(
          LocalBoxes(),
        ).readSession(_transcriptKey(session));
        expect(afterRestart.map((item) => item.eventId), firstEventIds);
      },
    );

    test('partitions a lossy-name collision by embedded session id', () async {
      final first = _session('peer', 'room/a', 'session/a');
      final second = _session('peer', 'room?a', 'session?a');
      expect(
        TranscriptStorageMigrator.legacyEventsBoxName(first.ref),
        TranscriptStorageMigrator.legacyEventsBoxName(second.ref),
      );
      await _seedIndex([first, second]);
      final shared = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.legacyEventsBoxName(first.ref),
      );
      await shared.put(
        'first-event',
        TranscriptEventRecord.fromEvent(
          _confirmed('first-event', first.sessionId, 'first-message', 'first'),
          0,
        ).toJson(),
      );
      await shared.put(
        'second-event',
        TranscriptEventRecord.fromEvent(
          _confirmed(
            'second-event',
            second.sessionId,
            'second-message',
            'second',
          ),
          1,
        ).toJson(),
      );
      await Hive.close();

      await LocalBoxes.initForTest(
        directory.path,
        encryptionKey: encryptionKey,
      );
      final store = HiveTranscriptEventStore(LocalBoxes());
      expect(
        (await store.readSession(
          _transcriptKey(first),
        )).map((item) => item.eventId),
        ['first-event'],
      );
      expect(
        (await store.readSession(
          _transcriptKey(second),
        )).map((item) => item.eventId),
        ['second-event'],
      );
    });

    test(
      'imports a unique projection with stable ids and visible order',
      () async {
        final session = _session(
          'peer-projection',
          'main',
          'session-projection',
        );
        await _seedIndex([session]);
        final projection = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.legacyMessagesBoxName(session.ref),
        );
        final rows = <MessageRecord>[
          MessageRecord(
            id: 'user-one',
            seq: 0,
            role: MsgRole.user,
            text: 'hello',
            ts: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
          MessageRecord(
            id: 'assistant-one',
            seq: 1,
            role: MsgRole.assistant,
            text: 'world',
            ts: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
          MessageRecord(
            id: 'tool-one',
            seq: 2,
            role: MsgRole.tool,
            ts: DateTime.fromMillisecondsSinceEpoch(3000),
            tool: const ToolEventData(
              toolCallId: 'tool-one',
              tool: 'read',
              args: {'path': 'README.md'},
              status: ToolEventStatus.completed,
              result: {'ok': true},
            ),
          ),
          MessageRecord(
            id: 'compact-one',
            seq: 3,
            role: MsgRole.compaction,
            text: 'summary',
            tokensBefore: 1200,
            ts: DateTime.fromMillisecondsSinceEpoch(4000),
          ),
          MessageRecord(
            id: 'pending-one',
            seq: 4,
            role: MsgRole.user,
            text: 'not sent yet',
            status: UserMsgStatus.pending,
            ts: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ];
        for (final row in rows) {
          await projection.put(row.seq, row.toJson());
        }
        await Hive.close();

        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: encryptionKey,
        );
        final store = HiveTranscriptEventStore(LocalBoxes());
        final firstEvents = await store.readSession(_transcriptKey(session));
        final firstIds = firstEvents.map((event) => event.eventId).toList();
        final visible = deriveTranscriptProjection(
          sessionId: session.sessionId,
          events: firstEvents,
        ).messages;
        final compactionId = firstEvents
            .whereType<CompactionRecorded>()
            .single
            .eventId;
        expect(visible.map((message) => message.id), [
          'user-one',
          'assistant-one',
          'tool-one',
          compactionId,
          'pending-one',
        ]);
        expect((visible[0] as UserMsg).text, 'hello');
        expect((visible[1] as AssistantMsg).text, 'world');
        expect((visible[2] as ToolEvent).result, {'ok': true});
        expect((visible[3] as CompactionMsg).summary, 'summary');
        expect((visible[4] as UserMsg).status, UserMsgStatus.pending);

        await Hive.close();
        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: encryptionKey,
        );
        final secondIds = (await HiveTranscriptEventStore(
          LocalBoxes(),
        ).readSession(_transcriptKey(session))).map((event) => event.eventId);
        expect(secondIds, firstIds, reason: 'retry/restart must not duplicate');
      },
    );

    test(
      'ambiguous projection aborts and retains every plaintext source',
      () async {
        final first = _session('peer', 'room/a', 'session/a');
        final second = _session('peer', 'room?a', 'session?a');
        await _seedIndex([first, second]);
        final sharedProjectionName =
            TranscriptStorageMigrator.legacyMessagesBoxName(first.ref);
        expect(
          sharedProjectionName,
          TranscriptStorageMigrator.legacyMessagesBoxName(second.ref),
        );
        final shared = await Hive.openBox<dynamic>(sharedProjectionName);
        await shared.put(
          0,
          MessageRecord(
            id: 'ambiguous',
            seq: 0,
            role: MsgRole.assistant,
            text: 'cannot attribute',
            ts: DateTime.fromMillisecondsSinceEpoch(1000),
          ).toJson(),
        );
        await Hive.close();

        await expectLater(
          LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
          throwsA(
            isA<TranscriptMigrationException>().having(
              (error) => error.code,
              'code',
              'ambiguous_legacy_projection',
            ),
          ),
        );
        expect(await Hive.boxExists(sharedProjectionName), isTrue);
        expect(
          await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
          isTrue,
        );
        final metadata = Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        expect(
          metadata.get(TranscriptStorageMigrator.migrationVersionKey),
          isNull,
        );
        expect(LocalBoxes().sessionsIndexBox().isEmpty, isTrue);
      },
    );

    test('malformed canonical index row aborts without deletion', () async {
      final index = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.legacyIndexBoxName,
      );
      await index.put('bad', <String, Object?>{
        'epk': 'peer',
        'room_id': 'main',
        'last_message_preview': 'must remain recoverable',
      });
      await Hive.close();

      await expectLater(
        LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
        throwsA(
          isA<TranscriptMigrationException>().having(
            (error) => error.code,
            'code',
            'malformed_legacy_index',
          ),
        ),
      );
      expect(
        await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
        isTrue,
      );
      expect(
        Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        ).get(TranscriptStorageMigrator.migrationVersionKey),
        isNull,
      );
    });

    test('unknown index status aborts without normalized copy', () async {
      final session = _session('peer-status', 'main', 'session-status');
      final index = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.legacyIndexBoxName,
      );
      await index.put(session.key, <String, Object?>{
        ...session.toJson(),
        'status': 'paused',
      });
      await Hive.close();

      await expectLater(
        LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
        throwsA(
          isA<TranscriptMigrationException>().having(
            (error) => error.code,
            'code',
            'malformed_legacy_index',
          ),
        ),
      );

      expect(
        await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
        isTrue,
      );
      expect(LocalBoxes().sessionsIndexBox().isEmpty, isTrue);
      expect(
        Hive.box<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        ).get(TranscriptStorageMigrator.copyVerifiedKey),
        isNull,
      );
    });

    test(
      'fractional projection timestamp retains every plaintext source',
      () async {
        final session = _session('peer-ts', 'main', 'session-ts');
        await _seedIndex([session]);
        final sourceName = TranscriptStorageMigrator.legacyMessagesBoxName(
          session.ref,
        );
        final projection = await Hive.openBox<dynamic>(sourceName);
        await projection.put(0, <String, Object?>{
          ...MessageRecord(
            id: 'fractional-ts',
            seq: 0,
            role: MsgRole.assistant,
            text: 'must remain plaintext',
            ts: DateTime.fromMillisecondsSinceEpoch(1000),
          ).toJson(),
          'ts': 1000.5,
        });
        await Hive.close();

        await expectLater(
          LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
          throwsA(
            isA<TranscriptMigrationException>().having(
              (error) => error.code,
              'code',
              'malformed_legacy_projection',
            ),
          ),
        );

        expect(await Hive.boxExists(sourceName), isTrue);
        expect(
          Hive.isBoxOpen(sourceName),
          isFalse,
          reason: 'a malformed source must be closed before migration aborts',
        );
        expect(
          await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
          isTrue,
        );
        expect(LocalBoxes().sessionsIndexBox().isEmpty, isTrue);
        expect(
          await Hive.boxExists(
            LocalBoxes.transcriptEventsBoxName(_transcriptKey(session)),
          ),
          isFalse,
        );
      },
    );

    test('missing non-tool text retains every plaintext source', () async {
      final session = _session('peer-text', 'main', 'session-text');
      await _seedIndex([session]);
      final sourceName = TranscriptStorageMigrator.legacyMessagesBoxName(
        session.ref,
      );
      final projection = await Hive.openBox<dynamic>(sourceName);
      final malformed = MessageRecord(
        id: 'missing-text',
        seq: 0,
        role: MsgRole.user,
        text: 'must not become empty',
        ts: DateTime.fromMillisecondsSinceEpoch(1000),
      ).toJson()..remove('text');
      await projection.put(0, malformed);
      await Hive.close();

      await expectLater(
        LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
        throwsA(
          isA<TranscriptMigrationException>().having(
            (error) => error.code,
            'code',
            'malformed_legacy_projection',
          ),
        ),
      );

      expect(await Hive.boxExists(sourceName), isTrue);
      expect(
        await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
        isTrue,
      );
      expect(LocalBoxes().sessionsIndexBox().isEmpty, isTrue);
      expect(
        await Hive.boxExists(
          LocalBoxes.transcriptEventsBoxName(_transcriptKey(session)),
        ),
        isFalse,
      );
    });

    test(
      'resumes after a crash following a partial destination write',
      () async {
        final session = _session('peer-crash', 'main', 'session-crash');
        await _seedIndex([session]);
        final sourceName = TranscriptStorageMigrator.legacyEventsBoxName(
          session.ref,
        );
        final source = await Hive.openBox<dynamic>(sourceName);
        for (var index = 0; index < 2; index += 1) {
          final event = _confirmed(
            'event-$index',
            session.sessionId,
            'message-$index',
            'text-$index',
          );
          await source.put(
            event.eventId,
            TranscriptEventRecord.fromEvent(event, index).toJson(),
          );
        }
        final metadata = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        final secureIndex = await Hive.openBox<dynamic>(
          'sessions_index_v3',
          encryptionCipher: HiveAesCipher(encryptionKey),
          crashRecovery: false,
        );
        final legacyIndex = Hive.box<dynamic>(
          TranscriptStorageMigrator.legacyIndexBoxName,
        );
        var writes = 0;

        await expectLater(
          TranscriptStorageMigrator(
            cipher: HiveAesCipher(encryptionKey),
            afterDestinationWrite: () async {
              writes += 1;
              if (writes == 1) throw StateError('injected crash');
            },
          ).migrate(
            legacyIndex: legacyIndex,
            secureIndex: secureIndex,
            metadata: metadata,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await Hive.boxExists(sourceName), isTrue);
        expect(
          metadata.get(TranscriptStorageMigrator.migrationVersionKey),
          isNull,
        );
        await Hive.close();

        Hive.init(directory.path);
        final resumedMetadata = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        final resumedIndex = await Hive.openBox<dynamic>(
          'sessions_index_v3',
          encryptionCipher: HiveAesCipher(encryptionKey),
          crashRecovery: false,
        );
        final resumedLegacyIndex = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.legacyIndexBoxName,
          crashRecovery: false,
        );
        final report =
            await TranscriptStorageMigrator(
              cipher: HiveAesCipher(encryptionKey),
            ).migrate(
              legacyIndex: resumedLegacyIndex,
              secureIndex: resumedIndex,
              metadata: resumedMetadata,
            );

        expect(report.events, 2);
        final destination = await Hive.openBox<dynamic>(
          LocalBoxes.transcriptEventsBoxName(_transcriptKey(session)),
          encryptionCipher: HiveAesCipher(encryptionKey),
          crashRecovery: false,
        );
        expect(destination.keys.toSet(), {'event-0', 'event-1'});
        expect(await Hive.boxExists(sourceName), isFalse);
        expect(
          resumedMetadata.get(TranscriptStorageMigrator.migrationVersionKey),
          TranscriptStorageMigrator.migrationVersion,
        );
      },
    );

    test('resumes deletion after a crash without a deleted source', () async {
      final session = _session('peer-delete', 'main', 'session-delete');
      await _seedIndex([session]);
      final sourceName = TranscriptStorageMigrator.legacyEventsBoxName(
        session.ref,
      );
      final source = await Hive.openBox<dynamic>(sourceName);
      final event = _confirmed(
        'event-delete',
        session.sessionId,
        'message-delete',
        'verified before delete',
      );
      await source.put(
        event.eventId,
        TranscriptEventRecord.fromEvent(event, 0).toJson(),
      );
      final metadata = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.metadataBoxName,
      );
      final secureIndex = await Hive.openBox<dynamic>(
        'sessions_index_v3',
        encryptionCipher: HiveAesCipher(encryptionKey),
        crashRecovery: false,
      );
      final legacyIndex = Hive.box<dynamic>(
        TranscriptStorageMigrator.legacyIndexBoxName,
      );
      var deletions = 0;

      await expectLater(
        TranscriptStorageMigrator(
          cipher: HiveAesCipher(encryptionKey),
          afterSourceDelete: () async {
            deletions += 1;
            if (deletions == 1) throw StateError('injected delete crash');
          },
        ).migrate(
          legacyIndex: legacyIndex,
          secureIndex: secureIndex,
          metadata: metadata,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await Hive.boxExists(sourceName), isFalse);
      expect(
        await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
        isTrue,
      );
      expect(metadata.get(TranscriptStorageMigrator.copyVerifiedKey), isTrue);
      expect(
        metadata.get(TranscriptStorageMigrator.migrationVersionKey),
        isNull,
      );
      await Hive.close();

      Hive.init(directory.path);
      final resumedMetadata = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.metadataBoxName,
      );
      final resumedIndex = await Hive.openBox<dynamic>(
        'sessions_index_v3',
        encryptionCipher: HiveAesCipher(encryptionKey),
        crashRecovery: false,
      );
      final resumedLegacyIndex = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.legacyIndexBoxName,
        crashRecovery: false,
      );
      await TranscriptStorageMigrator(
        cipher: HiveAesCipher(encryptionKey),
      ).migrate(
        legacyIndex: resumedLegacyIndex,
        secureIndex: resumedIndex,
        metadata: resumedMetadata,
      );

      expect(
        resumedMetadata.get(TranscriptStorageMigrator.copyVerifiedKey),
        isNull,
      );
      expect(
        resumedMetadata.get(TranscriptStorageMigrator.migrationVersionKey),
        TranscriptStorageMigrator.migrationVersion,
      );
      final destination = await Hive.openBox<dynamic>(
        LocalBoxes.transcriptEventsBoxName(_transcriptKey(session)),
        encryptionCipher: HiveAesCipher(encryptionKey),
        crashRecovery: false,
      );
      expect(destination.keys, ['event-delete']);
    });

    test(
      'failed persisted index reopen retains every plaintext source',
      () async {
        final session = _session('peer-reopen', 'main', 'session-reopen');
        await _seedIndex([session]);
        final sourceName = TranscriptStorageMigrator.legacyEventsBoxName(
          session.ref,
        );
        final source = await Hive.openBox<dynamic>(sourceName);
        final event = _confirmed(
          'event-reopen',
          session.sessionId,
          'message-reopen',
          'must survive failed persisted verification',
        );
        await source.put(
          event.eventId,
          TranscriptEventRecord.fromEvent(event, 0).toJson(),
        );
        final metadata = await Hive.openBox<dynamic>(
          TranscriptStorageMigrator.metadataBoxName,
        );
        final secureIndex = await Hive.openBox<dynamic>(
          'sessions_index_v3',
          encryptionCipher: HiveAesCipher(encryptionKey),
          crashRecovery: false,
        );
        final legacyIndex = Hive.box<dynamic>(
          TranscriptStorageMigrator.legacyIndexBoxName,
        );
        final indexFile = File('${directory.path}/sessions_index_v3.hive');
        var destinationReopens = 0;

        await expectLater(
          TranscriptStorageMigrator(
            cipher: HiveAesCipher(encryptionKey),
            beforeDestinationReopen: () async {
              destinationReopens += 1;
              if (destinationReopens != 2) return;
              expect(indexFile.existsSync(), isTrue);
              await indexFile.delete();
            },
          ).migrate(
            legacyIndex: legacyIndex,
            secureIndex: secureIndex,
            metadata: metadata,
          ),
          throwsA(
            isA<TranscriptMigrationException>().having(
              (error) => error.code,
              'code',
              'destination_verification_failed',
            ),
          ),
        );

        expect(destinationReopens, 2);
        expect(await Hive.boxExists(sourceName), isTrue);
        expect(
          await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
          isTrue,
        );
        expect(metadata.get(TranscriptStorageMigrator.copyVerifiedKey), isNull);
        expect(
          metadata.get(TranscriptStorageMigrator.migrationVersionKey),
          isNull,
        );
        expect(Hive.box<dynamic>('sessions_index_v3').isEmpty, isTrue);
      },
    );

    test(
      'destination conflict is fail-closed before source deletion',
      () async {
        final session = _session('peer-conflict', 'main', 'session-conflict');
        await _seedIndex([session]);
        final sourceName = TranscriptStorageMigrator.legacyEventsBoxName(
          session.ref,
        );
        final source = await Hive.openBox<dynamic>(sourceName);
        final event = _confirmed(
          'event-conflict',
          session.sessionId,
          'message-conflict',
          'source value',
        );
        await source.put(
          event.eventId,
          TranscriptEventRecord.fromEvent(event, 0).toJson(),
        );
        final destination = await Hive.openBox<dynamic>(
          LocalBoxes.transcriptEventsBoxName(_transcriptKey(session)),
          encryptionCipher: HiveAesCipher(encryptionKey),
          crashRecovery: false,
        );
        await destination.put(event.eventId, <String, Object?>{'wrong': true});
        await Hive.close();

        await expectLater(
          LocalBoxes.initForTest(directory.path, encryptionKey: encryptionKey),
          throwsA(
            isA<TranscriptMigrationException>().having(
              (error) => error.code,
              'code',
              'destination_conflict',
            ),
          ),
        );
        expect(await Hive.boxExists(sourceName), isTrue);
        expect(
          await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName),
          isTrue,
        );
        expect(
          Hive.box<dynamic>(
            TranscriptStorageMigrator.metadataBoxName,
          ).get(TranscriptStorageMigrator.migrationVersionKey),
          isNull,
        );
      },
    );
  });
}

Future<void> _seedIndex(List<SessionIndexRecord> sessions) async {
  final index = await Hive.openBox<dynamic>(
    TranscriptStorageMigrator.legacyIndexBoxName,
  );
  for (final session in sessions) {
    await index.put(session.key, session.toJson());
  }
}

SessionIndexRecord _session(String peer, String room, String session) =>
    SessionIndexRecord(
      epk: peer,
      roomId: room,
      sessionId: session,
      displayName: session,
    );

TranscriptSessionKey _transcriptKey(SessionIndexRecord session) =>
    TranscriptSessionKey(
      peerId: session.epk,
      roomId: session.roomId,
      sessionId: session.sessionId,
    );

UserMessageConfirmed _confirmed(
  String eventId,
  String sessionId,
  String messageId,
  String text,
) => UserMessageConfirmed(
  eventId: eventId,
  sessionId: sessionId,
  ts: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  clientMessageId: messageId,
  text: text,
);
