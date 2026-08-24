import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
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
  test('BEFORE: canonical full projection at soak sizes', () {
    for (final eventCount in <int>[200, 1000, 5500]) {
      final events = _syntheticTranscript(eventCount);
      final samples = _sampleMicros(
        warmup: eventCount == 5500 ? 2 : 4,
        iterations: eventCount == 5500 ? 12 : 30,
        operation: () {
          final projection = deriveTranscriptProjection(
            sessionId: _sessionId,
            events: events,
          );
          expect(projection.messages, hasLength(eventCount));
        },
      );
      _report(
        probe: 'transcript_projection_full_before',
        eventCount: eventCount,
        samples: samples,
      );
    }
  });

  test('BEFORE: reply-anchor shape localizes the projection hot span', () {
    final shapes = <String, List<TranscriptEvent>>{
      'alternating_user_assistant': _syntheticTranscript(5500),
      'assistant_only': _assistantOnlyTranscript(5500),
      'user_only': _userOnlyTranscript(5500),
    };
    for (final entry in shapes.entries) {
      final samples = _sampleMicros(
        warmup: 2,
        iterations: 8,
        operation: () {
          final projection = deriveTranscriptProjection(
            sessionId: _sessionId,
            events: entry.value,
          );
          expect(projection.messages, hasLength(entry.value.length));
        },
      );
      _report(
        probe: 'transcript_projection_shape_${entry.key}_before',
        eventCount: entry.value.length,
        samples: samples,
      );
    }
  });

  test('BEFORE: every-prefix rebuild for one-at-a-time appends', () {
    final events = _syntheticTranscript(1000);
    final samples = _sampleMicros(
      warmup: 1,
      iterations: 5,
      operation: () {
        TranscriptProjection? projection;
        for (var prefix = 1; prefix <= events.length; prefix += 1) {
          projection = deriveTranscriptProjection(
            sessionId: _sessionId,
            events: events.take(prefix),
          );
        }
        expect(projection?.messages, hasLength(1000));
      },
    );
    _report(
      probe: 'transcript_projection_prefix_rebuild_before',
      eventCount: events.length,
      samples: samples,
    );
  });

  test('BEFORE: encrypted Hive replay append, read, and projection', () async {
    final directory = Directory.systemTemp.createTempSync(
      'transcript_projection_benchmark_',
    );
    try {
      await LocalBoxes.initForTest(
        directory.path,
        encryptionKey: List<int>.generate(32, (index) => index),
      );
      final store = HiveTranscriptEventStore(LocalBoxes());
      final events = _syntheticTranscript(5500);

      final appendWatch = Stopwatch()..start();
      final result = await store.appendAll(_key, events);
      appendWatch.stop();
      expect(result.appended, events.length);

      final readSamples = <int>[];
      for (var iteration = 0; iteration < 12; iteration += 1) {
        final watch = Stopwatch()..start();
        final log = await store.readSession(_key);
        watch.stop();
        expect(log, hasLength(events.length));
        if (iteration >= 2) readSamples.add(watch.elapsedMicroseconds);
      }

      final pipelineSamples = <int>[];
      for (var iteration = 0; iteration < 8; iteration += 1) {
        final watch = Stopwatch()..start();
        final log = await store.readSession(_key);
        final projection = deriveTranscriptProjection(
          sessionId: _sessionId,
          events: log,
        );
        watch.stop();
        expect(projection.messages, hasLength(events.length));
        if (iteration >= 2) {
          pipelineSamples.add(watch.elapsedMicroseconds);
        }
      }

      _report(
        probe: 'transcript_store_append_before',
        eventCount: events.length,
        samples: <int>[appendWatch.elapsedMicroseconds],
      );
      _report(
        probe: 'transcript_store_read_before',
        eventCount: events.length,
        samples: readSamples,
      );
      _report(
        probe: 'transcript_read_project_before',
        eventCount: events.length,
        samples: pipelineSamples,
      );

      const batchKey = TranscriptSessionKey(
        peerId: 'benchmark-peer',
        roomId: 'main',
        sessionId: 'benchmark-batch-1000',
      );
      final batchEvents = _syntheticTranscript(
        1000,
        sessionId: batchKey.sessionId,
      );
      final batchWatch = Stopwatch()..start();
      await store.appendAll(batchKey, batchEvents);
      batchWatch.stop();

      const singleKey = TranscriptSessionKey(
        peerId: 'benchmark-peer',
        roomId: 'main',
        sessionId: 'benchmark-single-1000',
      );
      final singleEvents = _syntheticTranscript(
        1000,
        sessionId: singleKey.sessionId,
      );
      final singleWatch = Stopwatch()..start();
      for (final event in singleEvents) {
        await store.appendAll(singleKey, <TranscriptEvent>[event]);
      }
      singleWatch.stop();
      _report(
        probe: 'transcript_store_append_batch_before',
        eventCount: batchEvents.length,
        samples: <int>[batchWatch.elapsedMicroseconds],
      );
      _report(
        probe: 'transcript_store_append_one_at_a_time_before',
        eventCount: singleEvents.length,
        samples: <int>[singleWatch.elapsedMicroseconds],
      );
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

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
    'AFTER: append receipt drives delta materialization without a full read',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'transcript_delta_pipeline_benchmark_',
      );
      try {
        await LocalBoxes.initForTest(
          directory.path,
          encryptionKey: List<int>.generate(32, (index) => index),
        );
        final store = _CountingTranscriptEventStore(
          HiveTranscriptEventStore(LocalBoxes()),
        );
        final replayEvents = _syntheticTranscript(5500);
        final replayReducer = TranscriptProjectionReducer.empty(
          sessionId: _sessionId,
        );
        final replayWatch = Stopwatch()..start();
        final replayReceipt = await store.appendAll(_key, replayEvents);
        final replayUpdate = replayReducer.applyAll(
          replayReceipt.accepted.map((entry) => entry.event),
        );
        replayWatch.stop();
        expect(replayUpdate.projection.messages, hasLength(5500));
        expect(replayUpdate.firstChangedMessageIndex, 0);
        expect(store.readCalls, 0);

        const singleKey = TranscriptSessionKey(
          peerId: 'benchmark-peer',
          roomId: 'main',
          sessionId: 'benchmark-delta-single-1000',
        );
        final singleEvents = _syntheticTranscript(
          1000,
          sessionId: singleKey.sessionId,
        );
        final singleReducer = TranscriptProjectionReducer.empty(
          sessionId: singleKey.sessionId,
        );
        var affectedRows = 0;
        final singleWatch = Stopwatch()..start();
        for (final event in singleEvents) {
          final receipt = await store.appendAll(singleKey, <TranscriptEvent>[
            event,
          ]);
          final update = singleReducer.applyAll(
            receipt.accepted.map((entry) => entry.event),
          );
          final firstChanged = update.firstChangedMessageIndex;
          if (firstChanged != null) {
            affectedRows += update.projection.messages.length - firstChanged;
          }
        }
        singleWatch.stop();
        expect(store.readCalls, 0);
        expect(affectedRows, 1000, reason: 'tail traffic changes one row');
        _expectEquivalent(
          singleReducer.projection,
          deriveTranscriptProjection(
            sessionId: singleKey.sessionId,
            events: singleEvents,
          ),
        );

        _report(
          probe: 'transcript_receipt_delta_replay_5500_after',
          eventCount: replayEvents.length,
          samples: <int>[replayWatch.elapsedMicroseconds],
        );
        _report(
          probe: 'transcript_receipt_delta_single_1000_after',
          eventCount: singleEvents.length,
          samples: <int>[singleWatch.elapsedMicroseconds],
        );
        expect(replayWatch.elapsedMilliseconds, lessThanOrEqualTo(250));
        expect(singleWatch.elapsedMilliseconds, lessThanOrEqualTo(400));
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

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

List<TranscriptEvent> _assistantOnlyTranscript(int eventCount) =>
    <TranscriptEvent>[
      for (var index = 0; index < eventCount; index += 1)
        AssistantMessageCommitted(
          eventId: 'assistant-only-event-$index',
          sessionId: _sessionId,
          ts: _baseTime.add(Duration(milliseconds: index)),
          messageId: 'assistant-only-$index',
          replyTo: 'absent-user-$index',
          text: 'Synthetic assistant-only response $index.',
        ),
    ];

List<TranscriptEvent> _userOnlyTranscript(int eventCount) => <TranscriptEvent>[
  for (var index = 0; index < eventCount; index += 1)
    UserMessageConfirmed(
      eventId: 'user-only-event-$index',
      sessionId: _sessionId,
      ts: _baseTime.add(Duration(milliseconds: index)),
      clientMessageId: 'user-only-$index',
      text: 'Synthetic user-only message $index.',
    ),
];

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
