import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('HiveTranscriptEventStore', () {
    late Directory dir;
    late LocalBoxes boxes;
    late HiveTranscriptEventStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('transcript_events_');
      await LocalBoxes.initForTest(dir.path);
      boxes = LocalBoxes();
      store = HiveTranscriptEventStore(boxes);
    });

    tearDown(() async {
      LocalBoxes.beforeOwnerTransitionCommonClearForTesting = null;
      LocalBoxes.afterOwnerTransitionBoxDeleteForTesting = null;
      LocalBoxes.beforeTranscriptBoxOpenForTesting = null;
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test(
      'an append blocked in box open is rejected by an overlapping wipe',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'racing-peer',
          roomId: 'racing-room',
          sessionId: 'racing-session',
        );
        final boxName = LocalBoxes.transcriptEventsBoxName(key);
        final openStarted = Completer<void>();
        final releaseOpen = Completer<void>();
        LocalBoxes.beforeTranscriptBoxOpenForTesting = (name) async {
          if (name != boxName) return;
          if (!openStarted.isCompleted) openStarted.complete();
          await releaseOpen.future;
        };

        final appending = store.appendAll(key, <TranscriptEvent>[
          _submitted('racing-event', key.sessionId, 'client-id', 'old owner'),
        ]);
        await openStarted.future;
        final wiping = LocalBoxes.wipeTranscriptsForOwnerTransition();
        releaseOpen.complete();

        await expectLater(appending, throwsA(isA<StateError>()));
        await wiping;
        expect(await Hive.boxExists(boxName), isFalse);
      },
    );

    test('dedupes by event id and preserves original seq and order', () async {
      const key = TranscriptSessionKey(
        peerId: 'peer/one=',
        roomId: 'room:one',
        sessionId: 'sess-1',
      );
      final accepted = await store.appendAll(key, <TranscriptEvent>[
        _submitted('event-1', 'sess-1', 'cli-1', 'first'),
        _submitted('event-2', 'sess-1', 'cli-2', 'second'),
      ]);
      expect(accepted.accepted.map((entry) => entry.event.eventId), <String>[
        'event-1',
        'event-2',
      ]);
      expect(accepted.accepted.map((entry) => entry.sequence), <int>[0, 1]);

      final duplicate = await store.appendAll(key, <TranscriptEvent>[
        _submitted('event-1', 'sess-1', 'cli-1', 'changed'),
      ]);
      expect(duplicate.received, 1);
      expect(duplicate.appended, 0);
      expect(duplicate.skipped, 1);

      final events = await store.readSession(key);
      expect(events.map((event) => event.eventId), <String>[
        'event-1',
        'event-2',
      ]);
      expect((events.first as UserMessageSubmitted).text, 'first');

      final box = boxes.openTranscriptEventsBox(key);
      final rawFirst = (box.get('event-1') as Map).cast<String, Object?>();
      final rawSecond = (box.get('event-2') as Map).cast<String, Object?>();
      expect(rawFirst['seq'], 0);
      expect(rawSecond['seq'], 1);
    });

    test(
      'assigns monotonically increasing seq across append batches',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'sess-1',
        );

        final first = await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-1', 'sess-1', 'cli-1', 'one'),
          _submitted('event-2', 'sess-1', 'cli-2', 'two'),
        ]);
        final second = await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-3', 'sess-1', 'cli-3', 'three'),
        ]);
        expect(first.accepted.map((entry) => entry.sequence), <int>[0, 1]);
        expect(second.accepted.single.sequence, 2);

        final box = boxes.openTranscriptEventsBox(key);
        expect(
          ['event-1', 'event-2', 'event-3'].map((id) {
            final json = (box.get(id) as Map).cast<String, Object?>();
            return json['seq'];
          }),
          <int>[0, 1, 2],
        );
      },
    );

    test(
      'batch duplicate keeps the first event and clear resets sequence',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'sess-1',
        );
        final first = _submitted('event-1', 'sess-1', 'cli-1', 'first');
        final result = await store.appendAll(key, <TranscriptEvent>[
          first,
          _submitted('event-1', 'sess-1', 'cli-1', 'changed'),
          _submitted('event-2', 'sess-1', 'cli-2', 'second'),
        ]);

        expect(result.received, 3);
        expect(result.appended, 2);
        expect(result.skipped, 1);
        expect(result.accepted.map((entry) => entry.sequence), <int>[0, 1]);
        expect(
          ((await store.readSession(key)).first as UserMessageSubmitted).text,
          'first',
        );

        await store.clearSession(key);
        final afterClear = await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-3', 'sess-1', 'cli-3', 'after clear'),
        ]);
        expect(afterClear.accepted.single.sequence, 0);
        expect(
          (await store.readSession(key)).map((event) => event.eventId),
          <String>['event-3'],
        );
      },
    );

    test(
      'reopen continues sequence allocation from append-only length',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'sess-1',
        );
        await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-1', 'sess-1', 'cli-1', 'one'),
          _submitted('event-2', 'sess-1', 'cli-2', 'two'),
        ]);
        await Hive.close();
        await LocalBoxes.initForTest(dir.path);
        boxes = LocalBoxes();
        store = HiveTranscriptEventStore(boxes);

        final result = await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-3', 'sess-1', 'cli-3', 'three'),
        ]);

        expect(result.accepted.single.sequence, 2);
        expect(
          (await store.readSession(key)).map((event) => event.eventId),
          <String>['event-1', 'event-2', 'event-3'],
        );
      },
    );

    test('uses per-session box names and isolates reads', () async {
      const first = TranscriptSessionKey(
        peerId: 'peer/id=',
        roomId: 'room:main',
        sessionId: 'sess:one',
      );
      const second = TranscriptSessionKey(
        peerId: 'peer/id=',
        roomId: 'room:main',
        sessionId: 'sess:two',
      );

      expect(
        LocalBoxes.transcriptEventsBoxName(first),
        isNot(LocalBoxes.transcriptEventsBoxName(second)),
      );

      await store.appendAll(first, <TranscriptEvent>[
        _submitted('event-1', 'sess:one', 'cli-1', 'one'),
      ]);
      await store.appendAll(second, <TranscriptEvent>[
        _submitted('event-2', 'sess:two', 'cli-2', 'two'),
      ]);

      expect((await store.readSession(first)).map((e) => e.eventId), <String>[
        'event-1',
      ]);
      expect((await store.readSession(second)).map((e) => e.eventId), <String>[
        'event-2',
      ]);
    });

    test(
      'encrypts transcript bytes and reopens them with the same key',
      () async {
        const sentinel = 'unique-plaintext-transcript-sentinel-9f2d';
        const key = TranscriptSessionKey(
          peerId: 'encrypted-peer',
          roomId: 'main',
          sessionId: 'encrypted-session',
        );
        final encryptionKey = List<int>.generate(32, (index) => index);

        await Hive.close();
        await LocalBoxes.initForTest(dir.path, encryptionKey: encryptionKey);
        boxes = LocalBoxes();
        store = HiveTranscriptEventStore(boxes);
        await store.appendAll(key, <TranscriptEvent>[
          _submitted('encrypted-event', key.sessionId, 'client-id', sentinel),
        ]);
        await boxes.sessionsIndexBox().put('sentinel-index', <String, Object?>{
          'preview': sentinel,
        });
        final projection = await boxes.msgsBox(
          const RemoteSessionRef(
            peerEpk: 'encrypted-peer',
            roomId: 'main',
            sessionId: 'encrypted-session',
          ),
        );
        await projection.put(0, <String, Object?>{'text': sentinel});
        await Hive.close();

        final needle = utf8.encode(sentinel);
        final files = dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.hive'));
        expect(files, isNotEmpty);
        for (final file in files) {
          final bytes = await file.readAsBytes();
          expect(
            _containsBytes(bytes, needle),
            isFalse,
            reason: '${file.path} exposed the transcript sentinel',
          );
        }

        await LocalBoxes.initForTest(dir.path, encryptionKey: encryptionKey);
        boxes = LocalBoxes();
        store = HiveTranscriptEventStore(boxes);
        final reopened = await store.readSession(key);
        expect((reopened.single as UserMessageSubmitted).text, sentinel);
      },
    );

    test('rejects a wrong key before transcript access', () async {
      await boxes.sessionsIndexBox().put('cipher-check', <String, Object?>{
        'value': 'encrypted',
      });
      await Hive.close();

      await expectLater(
        LocalBoxes.initForTest(
          dir.path,
          encryptionKey: List<int>.filled(32, 99),
        ),
        throwsA(
          isA<TranscriptStorageKeyException>().having(
            (error) => error.code,
            'code',
            'key_mismatch',
          ),
        ),
      );
    });

    test('guards against appending an event for a different session', () async {
      const key = TranscriptSessionKey(
        peerId: 'peer',
        roomId: 'room',
        sessionId: 'sess-1',
      );

      expect(
        () => store.appendAll(key, <TranscriptEvent>[
          _submitted('event-1', 'sess-2', 'cli-1', 'wrong session'),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'shared store/replay fixture is append-only, isolated, and rebuildable',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer-fixture',
          roomId: 'main',
          sessionId: 'sess-store-fixture',
        );
        const foreignKey = TranscriptSessionKey(
          peerId: 'peer-fixture',
          roomId: 'main',
          sessionId: 'sess-foreign-fixture',
        );
        final ts = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        final fixture = <TranscriptEvent>[
          UserMessageSubmitted(
            eventId: 'local:cli_1',
            sessionId: key.sessionId,
            ts: ts,
            clientMessageId: 'cli_1',
            text: 'hello',
          ),
          UserMessageFailed(
            eventId: 'local:cli_1:timeout',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 1)),
            clientMessageId: 'cli_1',
            code: 'timeout',
            message: 'Timed out waiting for echo.',
          ),
          UserMessageConfirmed(
            eventId: 'server:cli_1',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 2)),
            clientMessageId: 'cli_1',
            text: 'hello',
          ),
          AssistantMessageCommitted(
            eventId: 'server:chunk_1:committed',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 3)),
            messageId: 'agent_chunk_1',
            replyTo: 'cli_1',
            text: 'done',
          ),
          AssistantDoneReceived(
            eventId: 'server:done_1',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 4)),
            replyTo: 'cli_1',
          ),
        ];

        final first = await store.appendAll(key, fixture);
        final duplicate = await store.appendAll(key, fixture);
        await store.appendAll(foreignKey, <TranscriptEvent>[
          _submitted('foreign:cli_1', foreignKey.sessionId, 'cli_1', 'foreign'),
        ]);

        expect(first.appended, fixture.length);
        expect(duplicate.appended, 0, reason: 'duplicate append is ignored');
        expect(duplicate.skipped, fixture.length);
        expect(
          (await store.readSession(key)).map((event) => event.eventId),
          fixture.map((event) => event.eventId),
          reason: 'stable append order is the replay order',
        );
        expect(
          (await store.readSession(foreignKey)).map((event) => event.eventId),
          <String>['foreign:cli_1'],
          reason: 'foreign session_id is isolated in its own canonical box',
        );

        final projection = deriveTranscriptProjection(
          sessionId: key.sessionId,
          events: await store.readSession(key),
        );
        expect(projection.turn.working, isFalse);
        expect(projection.messages.map((message) => message.id), <String>[
          'cli_1',
          'agent_chunk_1',
        ]);
        final user = projection.messages.first as UserMsg;
        expect(
          user.status,
          UserMsgStatus.confirmed,
          reason: 'late confirmation suppresses timeout failure',
        );
        expect(user.text, 'hello');
        expect((projection.messages.last as AssistantMsg).text, 'done');
      },
    );

    test('old user records default to canonical pickup placement', () {
      final submitted =
          TranscriptEventRecord.fromJson(<String, Object?>{
                'event_id': 'old-submitted',
                'seq': 0,
                'session_id': 'sess-1',
                'kind': 'user_submitted',
                'ts': 1700000000000,
                'payload': <String, Object?>{
                  'client_message_id': 'old-user',
                  'text': 'legacy',
                },
              }).toEvent()
              as UserMessageSubmitted;
      final confirmed =
          TranscriptEventRecord.fromJson(<String, Object?>{
                'event_id': 'old-confirmed',
                'seq': 1,
                'session_id': 'sess-1',
                'kind': 'user_confirmed',
                'ts': 1700000000001,
                'payload': <String, Object?>{
                  'client_message_id': 'old-user',
                  'text': 'legacy',
                },
              }).toEvent()
              as UserMessageConfirmed;

      expect(submitted.awaitingPickup, isFalse);
      expect(confirmed.semanticPickup, isTrue);
    });

    test('fails fast on unknown record kind', () {
      expect(
        () => TranscriptEventRecord.fromJson(<String, Object?>{
          'event_id': 'event-1',
          'seq': 0,
          'session_id': 'sess-1',
          'kind': 'future_kind',
          'ts': 1700000000000,
          'payload': <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

bool _containsBytes(List<int> haystack, List<int> needle) {
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

UserMessageSubmitted _submitted(
  String eventId,
  String sessionId,
  String clientMessageId,
  String text,
) => UserMessageSubmitted(
  eventId: eventId,
  sessionId: sessionId,
  ts: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  clientMessageId: clientMessageId,
  text: text,
);
