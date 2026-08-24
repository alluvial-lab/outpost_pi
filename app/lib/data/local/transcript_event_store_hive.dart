import 'dart:async';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/transcript/transcript_event.dart';

/// Persist canonical transcript events in per-session Hive logs.
///
/// Appends are idempotent by event ID, reads are sequence-ordered, and every
/// event is rejected if its session ID disagrees with the addressed log.
final class HiveTranscriptEventStore implements TranscriptEventStore {
  const HiveTranscriptEventStore(this._boxes);

  final LocalBoxes _boxes;

  @override
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  ) async {
    final batch = events.toList(growable: false);
    for (final event in batch) {
      if (event.sessionId != key.sessionId) {
        throw StateError(
          'Transcript event ${event.eventId} belongs to session ${event.sessionId}, not ${key.sessionId}',
        );
      }
    }

    final box = await _boxes.transcriptEventsBox(key);
    var nextSequence = box.length;
    final batchIds = <String>{};
    final records = <String, Map<String, Object?>>{};
    final accepted = <SequencedTranscriptEvent>[];
    for (final event in batch) {
      if (!batchIds.add(event.eventId) || box.containsKey(event.eventId)) {
        continue;
      }
      final sequence = nextSequence++;
      records[event.eventId] = TranscriptEventRecord.fromEvent(
        event,
        sequence,
      ).toJson();
      accepted.add(SequencedTranscriptEvent(event: event, sequence: sequence));
    }
    if (records.isNotEmpty) await box.putAll(records);
    return AppendTranscriptEventsResult(
      received: batch.length,
      appended: accepted.length,
      skipped: batch.length - accepted.length,
      accepted: List<SequencedTranscriptEvent>.unmodifiable(accepted),
    );
  }

  @override
  Future<void> clearSession(TranscriptSessionKey key) async {
    final box = await _boxes.transcriptEventsBox(key);
    await box.clear();
  }

  @override
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key) async {
    final box = await _boxes.transcriptEventsBox(key);
    return _readBox(box.values, key.sessionId);
  }

  @override
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key) async* {
    final box = await _boxes.transcriptEventsBox(key);
    yield _readBox(box.values, key.sessionId);
    yield* box.watch().map((_) => _readBox(box.values, key.sessionId));
  }

  List<TranscriptEvent> _readBox(Iterable<dynamic> values, String sessionId) {
    final records = <TranscriptEventRecord>[];
    for (final value in values) {
      final record = _recordFromBoxValue(value);
      if (record == null) continue;
      if (record.sessionId != sessionId) {
        throw StateError(
          'Transcript event ${record.eventId} is stored in the wrong session box: ${record.sessionId} != $sessionId',
        );
      }
      records.add(record);
    }
    records.sort((a, b) {
      final seqCompare = a.seq.compareTo(b.seq);
      return seqCompare == 0 ? a.eventId.compareTo(b.eventId) : seqCompare;
    });
    return [for (final record in records) record.toEvent()];
  }

  TranscriptEventRecord? _recordFromBoxValue(dynamic value) {
    if (value == null) return null;
    if (value is TranscriptEventRecord) return value;
    if (value is Map<String, Object?>) {
      return TranscriptEventRecord.fromJson(value);
    }
    if (value is Map) {
      return TranscriptEventRecord.fromJson(
        value.map((key, value) {
          if (key is! String) {
            throw const FormatException(
              'Transcript event record keys must be strings',
            );
          }
          return MapEntry(key, value as Object?);
        }),
      );
    }
    throw FormatException(
      'Unsupported transcript event record value: ${value.runtimeType}',
    );
  }
}
