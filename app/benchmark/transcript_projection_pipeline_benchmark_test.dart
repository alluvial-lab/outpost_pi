import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _sessionId = 'benchmark-session';
const _key = TranscriptSessionKey(
  peerId: 'benchmark-peer',
  roomId: 'main',
  sessionId: _sessionId,
);
final _baseTime = DateTime.utc(2026, 8, 24);

void main() {
  test(
    'AFTER: incremental reducer applies every prefix and matches rebuild',
    () {
      final cleanFoldSamples = _sampleMicros(
        warmup: 2,
        iterations: 12,
        operation: () {
          final projection = deriveTranscriptProjection(
            sessionId: _sessionId,
            events: _syntheticTranscript(5500),
          );
          expect(projection.messages, hasLength(5500));
        },
      );
      _report(
        probe: 'transcript_projection_clean_fold_after',
        eventCount: 5500,
        samples: cleanFoldSamples,
      );

      final incrementalEvents = _syntheticTranscript(1000);
      final incrementalSamples = _sampleMicros(
        warmup: 2,
        iterations: 12,
        operation: () {
          final reducer = TranscriptProjectionReducer.empty(
            sessionId: _sessionId,
          );
          for (final event in incrementalEvents) {
            reducer.applyAll(<TranscriptEvent>[event]);
          }
          expect(reducer.projection.messages, hasLength(1000));
        },
      );
      _report(
        probe: 'transcript_projection_incremental_apply_after',
        eventCount: incrementalEvents.length,
        samples: incrementalSamples,
      );

      for (final eventCount in <int>[200, 1000, 5500]) {
        final events = _syntheticTranscript(eventCount);
        final reducer = TranscriptProjectionReducer.empty(
          sessionId: _sessionId,
        );
        final prefix = <TranscriptEvent>[];
        for (final event in events) {
          prefix.add(event);
          final update = reducer.applyAll(<TranscriptEvent>[event]);
          final clean = deriveTranscriptProjection(
            sessionId: _sessionId,
            events: prefix,
          );
          _expectEquivalent(update.projection, clean);
        }
      }

      expect(
        _percentile(cleanFoldSamples..sort(), 0.50),
        lessThanOrEqualTo(40000),
      );
      expect(_percentile(cleanFoldSamples, 0.95), lessThanOrEqualTo(60000));
      expect(
        _percentile(incrementalSamples..sort(), 0.50),
        lessThanOrEqualTo(100000),
      );
    },
  );

  test('AFTER: accepted receipts use batched Hive persistence', () async {
    final directory = Directory.systemTemp.createTempSync(
      'transcript_receipt_benchmark_',
    );
    try {
      await LocalBoxes.initForTest(
        directory.path,
        encryptionKey: List<int>.generate(32, (index) => index),
      );
      final store = HiveTranscriptEventStore(LocalBoxes());
      final batch5500 = _syntheticTranscript(5500);
      final batch5500Watch = Stopwatch()..start();
      final batch5500Result = await store.appendAll(_key, batch5500);
      batch5500Watch.stop();
      expect(batch5500Result.accepted, hasLength(5500));
      expect(batch5500Result.accepted.first.sequence, 0);
      expect(batch5500Result.accepted.last.sequence, 5499);

      const batchKey = TranscriptSessionKey(
        peerId: 'benchmark-peer',
        roomId: 'main',
        sessionId: 'benchmark-receipt-batch-1000',
      );
      final batch1000 = _syntheticTranscript(
        1000,
        sessionId: batchKey.sessionId,
      );
      final batch1000Watch = Stopwatch()..start();
      final batch1000Result = await store.appendAll(batchKey, batch1000);
      batch1000Watch.stop();
      expect(batch1000Result.accepted, hasLength(1000));

      const singleKey = TranscriptSessionKey(
        peerId: 'benchmark-peer',
        roomId: 'main',
        sessionId: 'benchmark-receipt-single-1000',
      );
      final single1000 = _syntheticTranscript(
        1000,
        sessionId: singleKey.sessionId,
      );
      final single1000Watch = Stopwatch()..start();
      for (final event in single1000) {
        final result = await store.appendAll(singleKey, <TranscriptEvent>[
          event,
        ]);
        expect(result.accepted.single.event.eventId, event.eventId);
      }
      single1000Watch.stop();

      _report(
        probe: 'transcript_store_append_batch_5500_after',
        eventCount: batch5500.length,
        samples: <int>[batch5500Watch.elapsedMicroseconds],
      );
      _report(
        probe: 'transcript_store_append_batch_1000_after',
        eventCount: batch1000.length,
        samples: <int>[batch1000Watch.elapsedMicroseconds],
      );
      _report(
        probe: 'transcript_store_append_one_at_a_time_1000_after',
        eventCount: single1000.length,
        samples: <int>[single1000Watch.elapsedMicroseconds],
      );
      expect(batch5500Watch.elapsedMilliseconds, lessThanOrEqualTo(250));
      expect(batch1000Watch.elapsedMilliseconds, lessThanOrEqualTo(50));
      expect(single1000Watch.elapsedMilliseconds, lessThanOrEqualTo(400));
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'AFTER: receipt pipeline reaches production Hive materialization boundary',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'transcript_delta_pipeline_benchmark_',
      );
      try {
        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: List<int>.generate(32, (index) => index),
        );
        final boxes = LocalBoxes();
        final store = _CountingTranscriptEventStore(
          HiveTranscriptEventStore(boxes),
        );

        final replay = await _materializationHarness(
          boxes: boxes,
          store: store,
          sessionId: _sessionId,
        );
        final replayEvents = _historyEvents(5500);
        final replayReadsBefore = store.readCalls;
        final replayWatch = Stopwatch()..start();
        // ignore: invalid_use_of_visible_for_testing_member — benchmark seam.
        await replay.sync.debugApplyHistory(
          _history(sessionId: _sessionId, events: replayEvents),
        );
        replayWatch.stop();
        expect(replay.box, hasLength(5500));
        expect(store.readCalls, replayReadsBefore);
        replay.dispose();

        const singleSessionId = 'benchmark-delta-single-1000';
        final single = await _materializationHarness(
          boxes: boxes,
          store: store,
          sessionId: singleSessionId,
        );
        final singleEvents = _historyEvents(1000);
        final singleReadsBefore = store.readCalls;
        final singleWatch = Stopwatch()..start();
        for (var index = 0; index < singleEvents.length; index += 1) {
          // ignore: invalid_use_of_visible_for_testing_member — benchmark seam.
          await single.sync.debugApplyHistory(
            _history(
              sessionId: singleSessionId,
              events: <SessionHistoryEvent>[singleEvents[index]],
              requestId: 'benchmark-single-$index',
            ),
          );
        }
        singleWatch.stop();
        expect(single.box, hasLength(1000));
        expect(store.readCalls, singleReadsBefore);
        single.dispose();

        _report(
          probe: 'transcript_receipt_materialized_replay_5500_after',
          eventCount: replayEvents.length,
          samples: <int>[replayWatch.elapsedMicroseconds],
        );
        _report(
          probe: 'transcript_receipt_materialized_single_1000_after',
          eventCount: singleEvents.length,
          samples: <int>[singleWatch.elapsedMicroseconds],
        );
        expect(replayWatch.elapsedMilliseconds, lessThanOrEqualTo(1000));
        expect(singleWatch.elapsedMilliseconds, lessThanOrEqualTo(1500));
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

final class _PipelineConnectionManager extends ConnectionManager {
  _PipelineConnectionManager(this.peer, this.sessionId)
    : super(
        factory: (_, _) async => throw UnsupportedError('benchmark is offline'),
        storage: _BenchmarkStorage(),
      );

  final PeerRecord peer;
  final String sessionId;

  @override
  PeerRecord? get activePeer => peer;

  @override
  String get activeRoomId => 'main';

  @override
  String? get activeSessionId => sessionId;

  @override
  bool isRoomLive(String epk, String roomId) =>
      epk == peer.remoteEpk && roomId == 'main';
}

final class _BenchmarkStorage extends PairingStorage {}

final class _MaterializationHarness {
  const _MaterializationHarness({
    required this.sync,
    required this.connection,
    required this.box,
  });

  final SyncService sync;
  final ConnectionManager connection;
  final Box<dynamic> box;

  void dispose() {
    sync.dispose();
    connection.dispose();
  }
}

Future<_MaterializationHarness> _materializationHarness({
  required LocalBoxes boxes,
  required TranscriptEventStore store,
  required String sessionId,
}) async {
  final peer = PeerRecord(
    remoteEpk: 'benchmark-peer-$sessionId',
    sessionName: 'Benchmark Pi',
    relayUrl: 'ws://localhost',
    pairedAt: '2026-08-24T00:00:00Z',
    roomId: 'main',
  );
  final connection = _PipelineConnectionManager(peer, sessionId);
  final sync = SyncService(
    connection,
    boxes,
    transcriptEventStore: store,
    runtimeRecordWriter: (_, _) async {},
  );
  await sync.activate(peer.remoteEpk, 'main');
  final ref = RemoteSessionRef(
    peerEpk: peer.remoteEpk,
    roomId: 'main',
    sessionId: sessionId,
  );
  return _MaterializationHarness(
    sync: sync,
    connection: connection,
    box: await boxes.msgsBox(ref),
  );
}

SessionHistory _history({
  required String sessionId,
  required List<SessionHistoryEvent> events,
  String requestId = 'benchmark-replay',
}) => SessionHistory(
  sessionId: sessionId,
  inReplyTo: requestId,
  sessionStartedAt: _baseTime.millisecondsSinceEpoch,
  events: events,
  eos: true,
);

List<SessionHistoryEvent> _historyEvents(
  int eventCount,
) => <SessionHistoryEvent>[
  for (var index = 0; index < eventCount; index += 1)
    if (index.isEven)
      UserInputEvt(
        ts: _baseTime.add(Duration(milliseconds: index)).millisecondsSinceEpoch,
        id: 'user-${index ~/ 2}',
        text: 'Synthetic user message ${index ~/ 2} for the soak workload.',
      )
    else
      AgentMessageEvt(
        ts: _baseTime.add(Duration(milliseconds: index)).millisecondsSinceEpoch,
        inReplyTo: 'user-${index ~/ 2}',
        messageId: 'assistant-${index ~/ 2}',
        text:
            'Synthetic assistant response ${index ~/ 2} for projection materialization.',
      ),
];

final class _CountingTranscriptEventStore implements TranscriptEventStore {
  _CountingTranscriptEventStore(this._delegate);

  final TranscriptEventStore _delegate;
  int readCalls = 0;

  @override
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  ) => _delegate.appendAll(key, events);

  @override
  Future<void> clearSession(TranscriptSessionKey key) =>
      _delegate.clearSession(key);

  @override
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key) {
    readCalls += 1;
    return _delegate.readSession(key);
  }

  @override
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key) =>
      _delegate.watchSession(key);
}

void _expectEquivalent(
  TranscriptProjection incremental,
  TranscriptProjection clean,
) {
  expect(incremental.messages, clean.messages);
  expect(incremental.messageTimestamps, clean.messageTimestamps);
  expect(incremental.streaming, clean.streaming);
  expect(incremental.turn.status, clean.turn.status);
  expect(incremental.turn.sessionId, clean.turn.sessionId);
  expect(incremental.turn.turnId, clean.turn.turnId);
  expect(incremental.turn.replyTo, clean.turn.replyTo);
  expect(incremental.turn.error, clean.turn.error);
  expect(incremental.steering, clean.steering);
}

List<TranscriptEvent> _syntheticTranscript(
  int eventCount, {
  String sessionId = _sessionId,
}) {
  return <TranscriptEvent>[
    for (var index = 0; index < eventCount; index += 1)
      if (index.isEven)
        UserMessageConfirmed(
          eventId: 'user-event-${index ~/ 2}',
          sessionId: sessionId,
          ts: _baseTime.add(Duration(milliseconds: index)),
          clientMessageId: 'user-${index ~/ 2}',
          text: 'Synthetic user message ${index ~/ 2} for the soak workload.',
        )
      else
        AssistantMessageCommitted(
          eventId: 'assistant-event-${index ~/ 2}',
          sessionId: sessionId,
          ts: _baseTime.add(Duration(milliseconds: index)),
          messageId: 'assistant-${index ~/ 2}',
          replyTo: 'user-${index ~/ 2}',
          text:
              'Synthetic assistant response ${index ~/ 2} for projection materialization.',
        ),
  ];
}

List<int> _sampleMicros({
  required int warmup,
  required int iterations,
  required void Function() operation,
}) {
  for (var iteration = 0; iteration < warmup; iteration += 1) {
    operation();
  }
  return <int>[
    for (var iteration = 0; iteration < iterations; iteration += 1)
      _timeMicros(operation),
  ];
}

int _timeMicros(void Function() operation) {
  final watch = Stopwatch()..start();
  operation();
  watch.stop();
  return watch.elapsedMicroseconds;
}

void _report({
  required String probe,
  required int eventCount,
  required List<int> samples,
}) {
  final ordered = List<int>.of(samples)..sort();
  final payload = <String, Object?>{
    'probe': probe,
    'events': eventCount,
    'iterations': ordered.length,
    'p50_us': _percentile(ordered, 0.50),
    'p95_us': _percentile(ordered, 0.95),
    'min_us': ordered.first,
    'max_us': ordered.last,
    'rss_bytes': ProcessInfo.currentRss,
  };
  stdout.writeln('PERF_JSON ${jsonEncode(payload)}');
}

int _percentile(List<int> ordered, double percentile) {
  final index = ((ordered.length - 1) * percentile).ceil();
  return ordered[index];
}
