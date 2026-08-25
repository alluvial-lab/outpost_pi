import 'dart:async';

import 'package:app/domain/transcript/transcript_event.dart';

/// Identify one durable transcript stream within a peer room and session.
final class TranscriptSessionKey {
  const TranscriptSessionKey({
    required this.peerId,
    required this.roomId,
    required this.sessionId,
  });

  final String peerId;
  final String roomId;
  final String sessionId;

  String get durableKey => '$peerId:$roomId:$sessionId';
}

/// Pair an accepted transcript event with its durable append sequence.
final class SequencedTranscriptEvent {
  const SequencedTranscriptEvent({required this.event, required this.sequence});

  final TranscriptEvent event;
  final int sequence;
}

/// Report how a deduplicating transcript append handled its input batch.
final class AppendTranscriptEventsResult {
  const AppendTranscriptEventsResult({
    required this.received,
    required this.appended,
    required this.skipped,
    required this.accepted,
  });

  final int received;
  final int appended;
  final int skipped;
  final List<SequencedTranscriptEvent> accepted;
}

/// Persist and observe the canonical append-only transcript event stream.
///
/// Implementations deduplicate by event identity and expose each session as an
/// ordered snapshot suitable for rebuilding a projection.
abstract interface class TranscriptEventStore {
  /// Append [events] for [key], reporting appended and duplicate entries.
  ///
  /// Implementations validate that every event belongs to [key]'s canonical
  /// session before writing. Storage failures propagate to the caller rather
  /// than being converted into an apparently successful empty result.
  ///
  /// Throws [StateError] when an event targets another session, and propagates
  /// adapter/storage failures.
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );

  /// Clear [key] as one reset boundary for append sequence ownership.
  ///
  /// Underlying storage failures propagate to the caller.
  Future<void> clearSession(TranscriptSessionKey key);

  /// Read the current ordered event snapshot for [key].
  ///
  /// A corrupt or unsupported stored record is a durable-state failure, not an
  /// absent session: implementations surface [FormatException] for malformed
  /// records and [StateError] for records stored under the wrong session.
  /// Underlying storage failures also propagate.
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);

  /// Watch complete ordered snapshots for [key] after each persisted change.
  ///
  /// The initial read and later snapshots retain the same validation and
  /// failure contract; decode or storage failures are surfaced as stream
  /// errors rather than silently omitted.
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key);
}
