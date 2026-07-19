import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart'
    show Usage, UserMessageStreamingBehavior;

/// Capture one immutable fact in a session's append-only transcript stream.
sealed class TranscriptEvent {
  const TranscriptEvent({
    required this.eventId,
    required this.sessionId,
    required this.ts,
    this.turnId,
  });

  final String eventId;
  final String sessionId;
  final DateTime ts;
  final String? turnId;
}

/// Record a locally accepted user submission before server confirmation.
final class UserMessageSubmitted extends TranscriptEvent {
  const UserMessageSubmitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
    this.image,
    this.held = false,
    this.awaitingPickup = false,
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;

  /// Keep a steered submission out of transcript order until canonical pickup.
  final bool awaitingPickup;

  /// `true` when this message was held pending (never written to the
  /// channel) because the room was offline at send time (option-1 guard or
  /// the offline branch). The reconnect re-send path
  /// (story-app-reattempt-held-pending-on-reconnect) re-sends only held
  /// messages that are still pending/failed, so they actually reach the Pi
  /// instead of leaving a permanent failure badge. `false` (default) for
  /// messages that were written to the channel — those are handled by the
  /// late-confirmation path (SessionHistory replay) if they time out.
  final bool held;
}

/// Record the authoritative confirmation of a user message.
final class UserMessageConfirmed extends TranscriptEvent {
  const UserMessageConfirmed({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
    this.image,
    this.streamingBehavior,
    this.semanticPickup = true,
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;
  final UserMessageStreamingBehavior? streamingBehavior;

  /// Distinguish delivery acceptance from the timestamped agent pickup event.
  ///
  /// Old persisted records default to `true`, preserving their prior order.
  final bool semanticPickup;
}

/// Record a terminal local failure while a submission lacks confirmation.
final class UserMessageFailed extends TranscriptEvent {
  const UserMessageFailed({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.code,
    required this.message,
  });

  final String clientMessageId;
  final String code;
  final String message;
}

/// Record one streamed assistant delta for an in-progress reply.
final class AssistantDeltaReceived extends TranscriptEvent {
  const AssistantDeltaReceived({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.replyTo,
    required this.delta,
  });

  final String replyTo;
  final String delta;
}

/// Record the authoritative assistant reply that replaces streamed deltas.
final class AssistantMessageCommitted extends TranscriptEvent {
  const AssistantMessageCommitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.messageId,
    required this.replyTo,
    required this.text,
    this.usage,
  });

  final String messageId;
  final String replyTo;
  final String text;
  final Usage? usage;
}

/// Record completion of an assistant turn that may have no final message.
final class AssistantDoneReceived extends TranscriptEvent {
  const AssistantDoneReceived({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.replyTo,
    this.usage,
  });

  final String replyTo;
  final Usage? usage;
}

/// Record a tool invocation requested during a turn.
final class ToolRequested extends TranscriptEvent {
  const ToolRequested({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.toolCallId,
    required this.tool,
    required this.args,
  });

  final String toolCallId;
  final String tool;
  final Map<String, Object?> args;
}

/// Record the result or failure that settles a requested tool invocation.
final class ToolFinished extends TranscriptEvent {
  const ToolFinished({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.toolCallId,
    this.result,
    this.error,
  });

  final String toolCallId;
  final Object? result;
  final String? error;
}

/// Record a context compaction and its user-visible recap.
final class CompactionRecorded extends TranscriptEvent {
  const CompactionRecorded({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.summary,
    this.tokensBefore,
  });

  final String summary;
  final int? tokensBefore;
}
