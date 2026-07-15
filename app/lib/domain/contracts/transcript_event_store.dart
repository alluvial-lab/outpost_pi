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

/// Report how a deduplicating transcript append handled its input batch.
final class AppendTranscriptEventsResult {
  const AppendTranscriptEventsResult({
    required this.received,
    required this.appended,
    required this.skipped,
  });

  final int received;
  final int appended;
  final int skipped;
}

/// Persist and observe the canonical append-only transcript event stream.
///
/// Implementations deduplicate by event identity and expose each session as an
/// ordered snapshot suitable for rebuilding a projection.
abstract interface class TranscriptEventStore {
  /// Append [events] for [key], reporting appended and duplicate entries.
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );

  /// Read the current ordered event snapshot for [key].
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);

  /// Watch complete ordered snapshots for [key] after each persisted change.
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key);
}
