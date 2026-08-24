// Session domain model — chat message variants + streaming buffer.
// Lives in domain/ → no Flutter, no network, no storage.

// ---------------------------------------------------------------------------
// ChatMessage — sealed union of message variants in the conversation history
// ---------------------------------------------------------------------------

/// Represent one renderable entry in a conversation transcript.
sealed class ChatMessage {
  final String id;
  const ChatMessage({required this.id});
}

/// Plan/24-fix-app-source-of-truth: every UserMsg is tagged with the
/// lifecycle stage of its rebroadcast. `pending` = not yet confirmed and may
/// still be held for identity/connectivity or awaiting Pi's echo; `confirmed`
/// = Pi rebroadcast it (or it came from `session_history` / another device's
/// echo); `failed` = the configured pending-send backstop elapsed, so the user
/// can retry.
///
/// Default is `confirmed` for back-compat — every persisted UserMsg
/// from before this fix was effectively confirmed (the Pi wasn't
/// rebroadcasting then, but the local cache treated it as
/// authoritative).
enum UserMsgStatus { pending, confirmed, failed }

/// Plan/30 — an image attached to a user message. Carries the JPEG bytes
/// base64-encoded plus its mime type, mirroring the SDK's `ImageContent`.
/// Bytes always travel inline (decision #8: history replays the image too),
/// so the bubble can render straight from [data] with no extra round-trip.
class MessageImage {
  /// Base64-encoded image bytes (no data-URI prefix).
  final String data;

  /// Mime type, e.g. `image/jpeg`.
  final String mime;

  const MessageImage({required this.data, required this.mime});

  @override
  bool operator ==(Object other) =>
      other is MessageImage && other.data == data && other.mime == mime;

  @override
  int get hashCode => Object.hash(data, mime);
}

/// Preserve a user submission and its confirmation state for transcript views.
class UserMsg extends ChatMessage {
  final String text;
  final UserMsgStatus status;

  /// Plan/30 — optional attached image (one max). `null` for text-only
  /// messages, which is every message before this feature.
  final MessageImage? image;

  const UserMsg({
    required super.id,
    required this.text,
    this.status = UserMsgStatus.confirmed,
    this.image,
  });

  UserMsg copyWith({UserMsgStatus? status}) =>
      UserMsg(id: id, text: text, status: status ?? this.status, image: image);

  @override
  bool operator ==(Object other) =>
      other is UserMsg &&
      other.id == id &&
      other.text == text &&
      other.status == status &&
      other.image == image;

  @override
  int get hashCode => Object.hash(id, text, status, image);
}

/// Preserve a committed assistant reply in the transcript.
class AssistantMsg extends ChatMessage {
  final String text;
  const AssistantMsg({required super.id, required this.text});

  @override
  bool operator ==(Object other) =>
      other is AssistantMsg && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// Project a requested tool call and its terminal result into the transcript.
class ToolEvent extends ChatMessage {
  final String toolCallId;
  final String tool;
  final dynamic args;
  final ToolEventStatus status;
  final dynamic result;
  final String? error;

  const ToolEvent({
    required super.id,
    required this.toolCallId,
    required this.tool,
    required this.args,
    this.status = ToolEventStatus.pending,
    this.result,
    this.error,
  });

  ToolEvent copyWith({
    ToolEventStatus? status,
    dynamic result,
    String? error,
  }) => ToolEvent(
    id: id,
    toolCallId: toolCallId,
    tool: tool,
    args: args,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolEvent &&
      other.id == id &&
      other.toolCallId == toolCallId &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, toolCallId, status);
}

/// Plan/32 — `denied` = the user/SDK declined the tool; `failed` = the tool
/// ran but errored (a distinct, red outcome). `expired` = approval timed out.
enum ToolEventStatus { pending, allowed, denied, expired, completed, failed }

/// Plan/32 — a context-compaction marker rendered as a system bubble
/// (distinct from user/assistant). [summary] is the Pi's recap of the
/// compacted thread; [tokensBefore] is the token count reclaimed (null when
/// the Pi didn't report it).
class CompactionMsg extends ChatMessage {
  final String summary;
  final int? tokensBefore;
  const CompactionMsg({
    required super.id,
    required this.summary,
    this.tokensBefore,
  });

  @override
  bool operator ==(Object other) =>
      other is CompactionMsg &&
      other.id == id &&
      other.summary == summary &&
      other.tokensBefore == tokensBefore;

  @override
  int get hashCode => Object.hash(id, summary, tokensBefore);
}

// ---------------------------------------------------------------------------
// StreamingMessage — accumulated deltas while the assistant is typing
// ---------------------------------------------------------------------------

/// Accumulate assistant deltas until the corresponding reply is committed.
class StreamingMessage {
  final String inReplyTo; // id of the UserMsg being answered
  final String buffer;

  const StreamingMessage({required this.inReplyTo, this.buffer = ''});

  StreamingMessage appendDelta(String delta) =>
      StreamingMessage(inReplyTo: inReplyTo, buffer: buffer + delta);

  @override
  bool operator ==(Object other) =>
      other is StreamingMessage &&
      other.inReplyTo == inReplyTo &&
      other.buffer == buffer;

  @override
  int get hashCode => Object.hash(inReplyTo, buffer);
}

/// Canonical app-side turn status projection.
///
/// This mirrors the pi-extension `TurnProjection.phase` vocabulary while
/// keeping the mobile domain pure: no Flutter, storage, transport, or context
/// imports. UI and data adapters derive booleans/cancel targets from this value
/// instead of carrying independent sticky flags.
enum AppTurnStatus {
  idle,
  working,
  awaitingTool,
  streaming,
  done,
  error,
  stale,
}

/// Describe the canonical app-side state of one active or completed turn.
///
/// Consumers derive working and cancellation affordances from this projection
/// rather than maintaining independent sticky flags.
final class AppTurnProjection {
  const AppTurnProjection({
    required this.status,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final String? error;

  static const idle = AppTurnProjection(status: AppTurnStatus.idle);
  static const stale = AppTurnProjection(status: AppTurnStatus.stale);

  bool get working => switch (status) {
    AppTurnStatus.working ||
    AppTurnStatus.awaitingTool ||
    AppTurnStatus.streaming => true,
    AppTurnStatus.idle ||
    AppTurnStatus.done ||
    AppTurnStatus.error ||
    AppTurnStatus.stale => false,
  };

  String? get cancelTargetId => working ? replyTo : null;

  @override
  bool operator ==(Object other) =>
      other is AppTurnProjection &&
      other.status == status &&
      other.turnId == turnId &&
      other.replyTo == replyTo &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, turnId, replyTo, error);
}

/// Room-level transport projection from relay metadata.
///
/// Session identity scopes authoritative idle/working state; stale gating keeps
/// cached metadata from rendering as live after disconnect or room end.
final class RoomTurnProjection {
  const RoomTurnProjection({required this.status, this.sessionId});

  final AppTurnStatus status;

  /// Session identity described by this metadata, when the Pi supplied one.
  final String? sessionId;

  static const idle = RoomTurnProjection(status: AppTurnStatus.idle);
  static const active = RoomTurnProjection(status: AppTurnStatus.working);
  static const stale = RoomTurnProjection(status: AppTurnStatus.stale);

  bool get isFresh => status != AppTurnStatus.stale;
  bool get working => status == AppTurnStatus.working;
}

/// Describe transport reachability independently from the current agent turn.
sealed class ChatTransportProjection {
  const ChatTransportProjection();
}

/// Confirm that the selected Pi room is reachable through the relay.
final class ChatTransportOnline extends ChatTransportProjection {
  const ChatTransportOnline({required this.roomId});

  final String roomId;

  @override
  bool operator ==(Object other) =>
      other is ChatTransportOnline && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;
}

/// Describe a connection attempt or retry backoff in progress.
final class ChatTransportRetrying extends ChatTransportProjection {
  const ChatTransportRetrying({required this.attempt, required this.nextRetry});

  final int attempt;
  final Duration nextRetry;

  @override
  bool operator ==(Object other) =>
      other is ChatTransportRetrying &&
      other.attempt == attempt &&
      other.nextRetry == nextRetry;

  @override
  int get hashCode => Object.hash(attempt, nextRetry);
}

/// Describe an unavailable selected room with a user-facing reason.
final class ChatTransportOffline extends ChatTransportProjection {
  const ChatTransportOffline({required this.reason});

  final String reason;

  @override
  bool operator ==(Object other) =>
      other is ChatTransportOffline && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// Describe a steering prompt independently from transport and agent phase.
sealed class SteeringProjection {
  const SteeringProjection();
}

/// Confirm that no steering prompt is awaiting semantic pickup.
final class NoSteering extends SteeringProjection {
  const NoSteering();
}

/// Describe one accepted prompt waiting for the agent to pick it up.
final class SteeringPending extends SteeringProjection {
  const SteeringPending({required this.clientMessageId, required this.text});

  final String clientMessageId;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SteeringPending &&
      other.clientMessageId == clientMessageId &&
      other.text == text;

  @override
  int get hashCode => Object.hash(clientMessageId, text);
}

/// Compose the independent transport, turn, and steering presentation axes.
final class ChatStatusProjection {
  const ChatStatusProjection({
    required this.transport,
    required this.turn,
    required this.steering,
  });

  final ChatTransportProjection transport;
  final AppTurnProjection turn;
  final SteeringProjection steering;

  bool get isOnline => transport is ChatTransportOnline;
  bool get canCancel => isOnline && turn.cancelTargetId != null;

  @override
  bool operator ==(Object other) =>
      other is ChatStatusProjection &&
      other.transport == transport &&
      other.turn == turn &&
      other.steering == steering;

  @override
  int get hashCode => Object.hash(transport, turn, steering);
}
