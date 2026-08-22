import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart'
    show
        AgentMessageEvt,
        CompactionEvt,
        SessionHistory,
        SessionHistoryEvent,
        ToolRequestEvt,
        ToolResultEvt,
        UserInputEvt;

/// Converts an authoritative `session_history` wire payload into canonical
/// transcript events without touching storage or UI state.
///
/// Event ids are derived only from stable server facts in each history event.
/// The outer `SessionHistory.inReplyTo` request id is deliberately ignored so
/// reconnects and repeated sync requests append/dedupe the same event ids.
List<TranscriptEvent> sessionHistoryToTranscriptEvents({
  required SessionHistory history,
  required String sessionId,
}) {
  if (sessionId.isEmpty) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'SessionHistory replay requires a canonical session id',
    );
  }

  return <TranscriptEvent>[
    for (final event in history.events)
      sessionHistoryEventToTranscriptEvent(event, sessionId: sessionId),
  ];
}

/// Map one authoritative history event into its canonical transcript event.
///
/// Requires a non-empty canonical [sessionId] and derives deterministic IDs so
/// repeated history replays deduplicate against live delivery.
TranscriptEvent sessionHistoryEventToTranscriptEvent(
  SessionHistoryEvent event, {
  required String sessionId,
}) {
  if (sessionId.isEmpty) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'SessionHistory replay requires a canonical session id',
    );
  }

  final ts = DateTime.fromMillisecondsSinceEpoch(event.ts);
  return switch (event) {
    UserInputEvt(:final id, :final text, :final image) => UserMessageConfirmed(
      eventId: serverReplayUserEventId(sessionId, event.type, event.ts),
      sessionId: sessionId,
      ts: ts,
      clientMessageId: id,
      text: text,
      image: image == null
          ? null
          : MessageImage(data: image.data, mime: image.mime),
    ),
    AgentMessageEvt(:final inReplyTo, :final text, :final messageId) =>
      AssistantMessageCommitted(
        // Identity source (a): when the replay event carries `message_id`
        // (sync_<ts>:assistant:<blockIndex>), use it as the stable key so
        // multi-block assistant messages (same in_reply_to+ts, different
        // blocks) do NOT collide on the same eventId. Falls back to inReplyTo
        // for legacy replay events without message_id. See
        // story-mobile-assistant-message-duplicated-live-replay decision 1.
        eventId: serverReplayEventId(
          sessionId,
          event.type,
          messageId ?? inReplyTo,
          event.ts,
        ),
        sessionId: sessionId,
        ts: ts,
        messageId: serverReplayMessageId(
          sessionId,
          event.type,
          messageId ?? inReplyTo,
          event.ts,
        ),
        replyTo: inReplyTo,
        text: text,
      ),
    ToolRequestEvt(:final toolCallId, :final tool, :final args) =>
      ToolRequested(
        eventId: serverReplayEventId(
          sessionId,
          event.type,
          toolCallId,
          event.ts,
        ),
        sessionId: sessionId,
        ts: ts,
        toolCallId: toolCallId,
        tool: tool,
        args: _objectMap(args),
      ),
    ToolResultEvt(:final toolCallId, :final result, :final error) =>
      ToolFinished(
        eventId: serverReplayEventId(
          sessionId,
          event.type,
          toolCallId,
          event.ts,
        ),
        sessionId: sessionId,
        ts: ts,
        toolCallId: toolCallId,
        result: result,
        error: error,
      ),
    CompactionEvt(:final summary, :final tokensBefore) => CompactionRecorded(
      eventId: serverReplayEventId(
        sessionId,
        event.type,
        'compaction',
        event.ts,
      ),
      sessionId: sessionId,
      ts: ts,
      summary: summary,
      tokensBefore: tokensBefore,
    ),
  };
}

/// Derive a user-event identity that survives extension process replacement.
///
/// Delivered-user reservations can preserve an app client id only while the Pi
/// process remains alive. SDK backfill after restart falls back to `sync_<ts>`,
/// so the SDK timestamp—not that process-local id—is the durable identity.
String serverReplayUserEventId(String sessionId, String historyType, int ts) =>
    serverReplayEventId(sessionId, historyType, 'sdk_$ts', ts);

/// Derive a stable event identity shared by live and history-replay paths.
String serverReplayEventId(
  String sessionId,
  String historyType,
  String stableKey,
  int ts,
) => 'server:$sessionId:$historyType:$stableKey:$ts';

/// Derive the stable projected message identity for one replayed event.
String serverReplayMessageId(
  String sessionId,
  String historyType,
  String stableKey,
  int ts,
) => 'server-message:$sessionId:$historyType:$stableKey:$ts';

Map<String, Object?> _objectMap(Object? raw) {
  if (raw == null) return <String, Object?>{};
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    return raw.map((key, value) {
      if (key is! String) {
        throw const FormatException('Tool request args keys must be strings');
      }
      return MapEntry(key, value as Object?);
    });
  }
  throw const FormatException('Tool request args must be an object');
}
