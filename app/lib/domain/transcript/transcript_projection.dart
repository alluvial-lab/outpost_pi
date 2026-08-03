import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart' show UserMessageStreamingBehavior;

/// Backward-compatible aliases for the transcript seam. The canonical variant
/// set is [AppTurnStatus]; keep this wrapper so older tests/callers do not
/// grow a second enum.
abstract final class TranscriptTurnStatus {
  static const idle = AppTurnStatus.idle;
  static const working = AppTurnStatus.working;
  static const awaitingTool = AppTurnStatus.awaitingTool;
  static const streaming = AppTurnStatus.streaming;
  static const done = AppTurnStatus.done;
  static const error = AppTurnStatus.error;
  static const stale = AppTurnStatus.stale;
}

/// Represent the transcript-derived state of the current conversation turn.
final class TranscriptTurnView {
  const TranscriptTurnView({
    required this.status,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final String? error;

  static const idle = TranscriptTurnView(status: AppTurnStatus.idle);

  bool get working => switch (status) {
    AppTurnStatus.working ||
    AppTurnStatus.awaitingTool ||
    AppTurnStatus.streaming => true,
    AppTurnStatus.idle ||
    AppTurnStatus.done ||
    AppTurnStatus.error ||
    AppTurnStatus.stale => false,
  };

  AppTurnProjection toAppProjection() => AppTurnProjection(
    status: status,
    turnId: turnId,
    replyTo: replyTo,
    error: error,
  );
}

/// Reconcile room reachability, transcript state, and streamed deltas.
///
/// Stale room reachability wins; otherwise active transcript or streaming state
/// supplies the app's canonical turn projection.
AppTurnProjection deriveChatTurnProjection({
  required RoomTurnProjection room,
  required TranscriptTurnView transcript,
  required StreamingMessage? streaming,
}) {
  if (room.status == AppTurnStatus.stale) {
    return AppTurnProjection.stale;
  }

  if (streaming != null) {
    return AppTurnProjection(
      status: AppTurnStatus.streaming,
      turnId: transcript.turnId ?? streaming.inReplyTo,
      replyTo: streaming.inReplyTo,
      error: transcript.error,
    );
  }

  if (room.status == AppTurnStatus.working) {
    final transcriptProjection = transcript.toAppProjection();
    if (transcriptProjection.working) return transcriptProjection;
    return AppTurnProjection(
      status: AppTurnStatus.working,
      turnId: transcript.turnId ?? transcript.replyTo,
      replyTo: transcript.replyTo,
      error: transcript.error,
    );
  }

  if (transcript.working || transcript.status == AppTurnStatus.error) {
    return transcript.toAppProjection();
  }

  return AppTurnProjection.idle;
}

/// Materialize transcript messages, streaming state, and turn state together.
final class TranscriptProjection {
  const TranscriptProjection({
    required this.messages,
    required this.turn,
    required this.steering,
    this.streaming,
  });

  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final TranscriptTurnView turn;
  final SteeringProjection steering;
}

/// Pure transcript projection and optimistic/authoritative reconcile reducer.
///
/// The event log is append-only, but this materialized view is rebuildable.
/// Server-authoritative events (`UserMessageConfirmed`, assistant/tool events,
/// compaction) form the stable prefix. Local optimistic submissions that have no
/// authoritative confirmation remain visible after that prefix. A failure marks
/// the local message failed only while no later confirmation exists; late
/// confirmation wins and suppresses the failure projection.
TranscriptProjection deriveTranscriptProjection({
  required String sessionId,
  required Iterable<TranscriptEvent> events,
}) {
  final scoped = events.where((event) => event.sessionId == sessionId);
  final seenEventIds = <String>{};
  final ordered = <TranscriptEvent>[];
  for (final event in scoped) {
    if (seenEventIds.add(event.eventId)) ordered.add(event);
  }

  final acceptedUsers = <String, UserMessageConfirmed>{};
  final pickedUpUsers = <String, UserMessageConfirmed>{};
  final submittedUsers = <String, UserMessageSubmitted>{};
  final failedUsers = <String, UserMessageFailed>{};
  final authoritativeMessages = <ChatMessage>[];
  final authoritativeIds = <String>{};
  final messageTs = <String, int>{};
  final messageArrival = <String, int>{};
  var arrivalCounter = 0;
  final assistantReplyTo = <String, String>{};
  final toolIndexes = <String, int>{};
  StreamingMessage? streaming;
  String? activeReplyAnchor;
  var turn = TranscriptTurnView.idle;
  SteeringProjection steering = const NoSteering();

  void appendAuthoritative(ChatMessage message, int ts) {
    if (authoritativeIds.add(message.id)) {
      authoritativeMessages.add(message);
      messageTs[message.id] = ts;
      messageArrival[message.id] = arrivalCounter++;
    }
  }

  void upsertTool(ToolEvent tool, int ts) {
    final existingIndex = toolIndexes[tool.toolCallId];
    final previousTs = messageTs[tool.toolCallId];
    final requestTs = previousTs == null || ts < previousTs ? ts : previousTs;
    if (existingIndex == null) {
      toolIndexes[tool.toolCallId] = authoritativeMessages.length;
      authoritativeMessages.add(tool);
      authoritativeIds.add(tool.id);
      messageTs[tool.id] = ts;
      messageArrival[tool.id] = arrivalCounter++;
      messageTs[tool.toolCallId] = requestTs;
      return;
    }
    messageTs[tool.toolCallId] = requestTs;
    final previous = authoritativeMessages[existingIndex];
    if (previous is ToolEvent) {
      authoritativeMessages[existingIndex] = ToolEvent(
        id: previous.id,
        toolCallId: previous.toolCallId,
        tool: previous.tool.isNotEmpty ? previous.tool : tool.tool,
        args: previous.args,
        status: tool.status,
        result: tool.result,
        error: tool.error,
      );
    }
  }

  for (final event in ordered) {
    switch (event) {
      case UserMessageSubmitted():
        submittedUsers[event.clientMessageId] = event;
        if (event.awaitingPickup) {
          steering = SteeringPending(
            clientMessageId: event.clientMessageId,
            text: event.text,
          );
        } else {
          activeReplyAnchor = event.clientMessageId;
          turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
          );
        }
      case UserMessageConfirmed():
        acceptedUsers[event.clientMessageId] = event;
        if (!event.semanticPickup) {
          steering = SteeringPending(
            clientMessageId: event.clientMessageId,
            text: event.text,
          );
          break;
        }
        pickedUpUsers[event.clientMessageId] = event;
        appendAuthoritative(
          UserMsg(
            id: event.clientMessageId,
            text: event.text,
            image: event.image,
          ),
          event.ts.millisecondsSinceEpoch,
        );
        if (steering case SteeringPending(
          :final clientMessageId,
        ) when clientMessageId == event.clientMessageId) {
          steering = const NoSteering();
        }
        if (event.streamingBehavior != UserMessageStreamingBehavior.steer) {
          activeReplyAnchor = event.clientMessageId;
          turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
          );
        }
      case UserMessageFailed():
        failedUsers[event.clientMessageId] = event;
        final failedSubmission = submittedUsers[event.clientMessageId];
        if (steering case SteeringPending(
          :final clientMessageId,
        ) when clientMessageId == event.clientMessageId) {
          steering = const NoSteering();
        }
        if (!pickedUpUsers.containsKey(event.clientMessageId) &&
            failedSubmission?.awaitingPickup != true) {
          activeReplyAnchor = null;
          turn = TranscriptTurnView(
            status: AppTurnStatus.error,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
            error: event.message,
          );
        }
      case AssistantDeltaReceived():
        activeReplyAnchor = event.replyTo;
        streaming =
            (streaming?.inReplyTo == event.replyTo
                    ? streaming
                    : StreamingMessage(inReplyTo: event.replyTo))
                ?.appendDelta(event.delta);
        turn = TranscriptTurnView(
          status: AppTurnStatus.streaming,
          turnId: event.turnId ?? event.replyTo,
          replyTo: event.replyTo,
        );
      case AssistantMessageCommitted():
        activeReplyAnchor = event.replyTo;
        assistantReplyTo[event.messageId] = event.replyTo;
        appendAuthoritative(
          AssistantMsg(id: event.messageId, text: event.text),
          event.ts.millisecondsSinceEpoch,
        );
        streaming = null;
        turn = TranscriptTurnView.idle;
      case AssistantDoneReceived():
        activeReplyAnchor = null;
        streaming = null;
        turn = TranscriptTurnView.idle;
      case ToolRequested():
        upsertTool(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: event.tool,
            args: event.args,
          ),
          event.ts.millisecondsSinceEpoch,
        );
        final replyAnchor =
            turn.replyTo ?? streaming?.inReplyTo ?? activeReplyAnchor;
        if (replyAnchor != null) {
          activeReplyAnchor = replyAnchor;
          turn = TranscriptTurnView(
            status: AppTurnStatus.awaitingTool,
            turnId: turn.turnId ?? event.turnId ?? replyAnchor,
            replyTo: replyAnchor,
          );
        }
      case ToolFinished():
        upsertTool(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: '',
            args: const <String, Object?>{},
            status: event.error == null
                ? ToolEventStatus.completed
                : ToolEventStatus.failed,
            result: event.result,
            error: event.error,
          ),
          event.ts.millisecondsSinceEpoch,
        );
        if (turn.status == AppTurnStatus.awaitingTool) {
          turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: turn.turnId,
            replyTo: turn.replyTo,
          );
        }
      case CompactionRecorded():
        activeReplyAnchor = null;
        appendAuthoritative(
          CompactionMsg(
            id: event.eventId,
            summary: event.summary,
            tokensBefore: event.tokensBefore,
          ),
          event.ts.millisecondsSinceEpoch,
        );
        streaming = null;
        turn = TranscriptTurnView.idle;
    }
  }

  // Lifecycle state reduces in arrival order above. Rendered authoritative
  // bubbles use canonical server time with arrival as the stable tiebreaker.
  // Phone-receipt-time deltas and local-time optimistic submissions never enter
  // this list, so the ordering remains single-clock.
  authoritativeMessages.sort((a, b) {
    final byTs = (messageTs[a.id] ?? 0).compareTo(messageTs[b.id] ?? 0);
    if (byTs != 0) return byTs;
    return (messageArrival[a.id] ?? 0).compareTo(messageArrival[b.id] ?? 0);
  });

  final localTail = <ChatMessage>[];
  for (final submitted in submittedUsers.values) {
    if (pickedUpUsers.containsKey(submitted.clientMessageId)) continue;
    final failed = failedUsers[submitted.clientMessageId];
    if (submitted.awaitingPickup && failed == null) continue;
    if (acceptedUsers.containsKey(submitted.clientMessageId) &&
        failed == null) {
      continue;
    }
    localTail.add(
      UserMsg(
        id: submitted.clientMessageId,
        text: submitted.text,
        status: failed == null ? UserMsgStatus.pending : UserMsgStatus.failed,
        image: submitted.image,
      ),
    );
  }

  final messages = [...authoritativeMessages, ...localTail];
  // Preserve the stable reply relationship as a same-timestamp safety net: a
  // prompt must precede assistant rows that name it.
  for (final user in messages.whereType<UserMsg>().toList(growable: false)) {
    final userIndex = messages.indexWhere((message) => message.id == user.id);
    final responseIndex = messages.indexWhere(
      (message) =>
          message is AssistantMsg && assistantReplyTo[message.id] == user.id,
    );
    if (responseIndex >= 0 && userIndex > responseIndex) {
      messages.removeAt(userIndex);
      messages.insert(responseIndex, user);
    }
  }

  return TranscriptProjection(
    messages: List.unmodifiable(messages),
    streaming: streaming,
    turn: turn,
    steering: steering,
  );
}
