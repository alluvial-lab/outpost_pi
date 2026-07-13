import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart'
    show Usage, UserMessageStreamingBehavior;

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
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;

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
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;
  final UserMessageStreamingBehavior? streamingBehavior;
}

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
