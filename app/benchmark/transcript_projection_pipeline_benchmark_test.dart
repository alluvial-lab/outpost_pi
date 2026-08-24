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

  test(
    'AFTER: append receipt drives delta materialization without a full read',
    () async {
      // Implementation checkpoint: use an instrumented TranscriptEventStore to
      // assert zero append-path readSession calls, apply only accepted receipt
      // entries, and compare every resulting projection with a clean rebuild.
      // Target: one 5,500-event replay batch <=250 ms and a 1,000-event
      // one-at-a-time persisted pipeline <=400 ms on the discovery host.
      throw UnimplementedError(
        'Incremental append pipeline is not implemented yet.',
      );
    },
    skip: 'AFTER scaffold for opt-2/opt-3; implementation enables it.',
  );
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
