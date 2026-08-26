import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart' show UserMessageStreamingBehavior;

/// Represent the transcript-derived state of the current conversation turn.
final class TranscriptTurnView {
  const TranscriptTurnView({
    required this.status,
    this.sessionId,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;

  /// Canonical session that produced this turn state, when bound.
  final String? sessionId;
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

  if (room.status == AppTurnStatus.idle &&
      room.sessionId != null &&
      room.sessionId == transcript.sessionId) {
    return AppTurnProjection.idle;
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

/// Materialize transcript messages, their timestamps, and live turn state.
final class TranscriptProjection {
  const TranscriptProjection({
    required this.messages,
    required this.messageTimestamps,
    required this.turn,
    required this.steering,
    this.streaming,
  });

  final List<ChatMessage> messages;
  final List<DateTime> messageTimestamps;
  final StreamingMessage? streaming;
  final TranscriptTurnView turn;
  final SteeringProjection steering;
}

/// Describe one accepted reducer application and its materialized delta.
final class TranscriptProjectionUpdate {
  const TranscriptProjectionUpdate({
    required this.acceptedEvents,
    required this.projection,
    required this.firstChangedMessageIndex,
  });

  final List<TranscriptEvent> acceptedEvents;
  final TranscriptProjection projection;
  final int? firstChangedMessageIndex;
}

final class _ProjectedRow {
  _ProjectedRow({
    required this.message,
    required this.sortTimestamp,
    required this.timestamp,
    required this.arrival,
  });

  ChatMessage message;
  DateTime sortTimestamp;
  DateTime timestamp;
  final int arrival;
}

/// Incrementally reduce one session's append-only transcript event stream.
///
/// Event identity, canonical ordering, optimistic reconciliation, and live turn
/// state are owned here so clean recovery and accepted-event application use the
/// same algorithm. Published message and timestamp lists are immutable.
final class TranscriptProjectionReducer {
  TranscriptProjectionReducer._(this._sessionId)
    : _projection = TranscriptProjection(
        messages: const <ChatMessage>[],
        messageTimestamps: const <DateTime>[],
        turn: TranscriptTurnView(
          status: AppTurnStatus.idle,
          sessionId: _sessionId,
        ),
        steering: const NoSteering(),
      );

  /// Create an empty reducer scoped to [sessionId].
  factory TranscriptProjectionReducer.empty({required String sessionId}) =>
      TranscriptProjectionReducer._(sessionId);

  final String _sessionId;
  final Set<String> _seenEventIds = <String>{};
  final Map<String, UserMessageConfirmed> _acceptedUsers =
      <String, UserMessageConfirmed>{};
  final Map<String, UserMessageConfirmed> _pickedUpUsers =
      <String, UserMessageConfirmed>{};
  final Map<String, UserMessageSubmitted> _submittedUsers =
      <String, UserMessageSubmitted>{};
  final Map<String, UserMessageFailed> _failedUsers =
      <String, UserMessageFailed>{};
  final Set<String> _authoritativeIds = <String>{};
  final Map<String, _ProjectedRow> _messageRows = <String, _ProjectedRow>{};
  final Map<String, _ProjectedRow> _toolRows = <String, _ProjectedRow>{};
  final List<_ProjectedRow> _authoritativeRows = <_ProjectedRow>[];
  final Map<String, DateTime> _messageTimestamps = <String, DateTime>{};
  final Map<String, String> _assistantReplyTo = <String, String>{};
  final Map<String, _ProjectedRow> _firstAssistantRowByReplyTo =
      <String, _ProjectedRow>{};

  var _arrivalCounter = 0;
  var _requiresReplyAnchoring = false;
  StreamingMessage? _streaming;
  String? _activeReplyAnchor;
  var _turn = TranscriptTurnView.idle;
  SteeringProjection _steering = const NoSteering();
  late TranscriptProjection _projection;

  /// Return the current immutable projection snapshot.
  TranscriptProjection get projection => _projection;

  /// Apply unseen events and return the first changed materialized row.
  TranscriptProjectionUpdate applyAll(Iterable<TranscriptEvent> events) {
    final accepted = <TranscriptEvent>[];
    for (final event in events) {
      if (event.sessionId != _sessionId || !_seenEventIds.add(event.eventId)) {
        continue;
      }
      accepted.add(event);
      _apply(event);
    }

    if (accepted.isEmpty) {
      return TranscriptProjectionUpdate(
        acceptedEvents: const <TranscriptEvent>[],
        projection: _projection,
        firstChangedMessageIndex: null,
      );
    }

    final previous = _projection;
    final next = _buildProjection();
    _projection = next;
    return TranscriptProjectionUpdate(
      acceptedEvents: List<TranscriptEvent>.unmodifiable(accepted),
      projection: next,
      firstChangedMessageIndex: _firstChangedIndex(previous, next),
    );
  }

  void _apply(TranscriptEvent event) {
    switch (event) {
      case UserMessageSubmitted():
        _submittedUsers[event.clientMessageId] = event;
        _messageTimestamps.putIfAbsent(event.clientMessageId, () => event.ts);
        if (event.awaitingPickup) {
          _steering = SteeringPending(
            clientMessageId: event.clientMessageId,
            text: event.text,
          );
        } else {
          _activeReplyAnchor = event.clientMessageId;
          _turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
          );
        }
      case UserMessageConfirmed():
        // A confirmation is authoritative even when a no-echo backstop fired
        // first. The timeout was a transport false-negative, so do not let the
        // stale failure continue to control the optimistic rendering path.
        _failedUsers.remove(event.clientMessageId);
        _acceptedUsers[event.clientMessageId] = event;
        _messageTimestamps[event.clientMessageId] = event.ts;
        if (!event.semanticPickup) {
          _steering = SteeringPending(
            clientMessageId: event.clientMessageId,
            text: event.text,
          );
          break;
        }
        _pickedUpUsers[event.clientMessageId] = event;
        _appendAuthoritative(
          UserMsg(
            id: event.clientMessageId,
            text: event.text,
            image: event.image,
          ),
          event.ts,
        );
        final userRow = _messageRows[event.clientMessageId];
        final firstReply = _firstAssistantRowByReplyTo[event.clientMessageId];
        if (userRow != null &&
            firstReply != null &&
            _compareRows(userRow, firstReply) > 0) {
          _requiresReplyAnchoring = true;
        }
        if (_steering case SteeringPending(
          :final clientMessageId,
        ) when clientMessageId == event.clientMessageId) {
          _steering = const NoSteering();
        }
        if (event.streamingBehavior != UserMessageStreamingBehavior.steer) {
          _activeReplyAnchor = event.clientMessageId;
          _turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
          );
        }
      case UserMessageFailed():
        _failedUsers[event.clientMessageId] = event;
        _messageTimestamps[event.clientMessageId] = event.ts;
        final failedSubmission = _submittedUsers[event.clientMessageId];
        if (_steering case SteeringPending(
          :final clientMessageId,
        ) when clientMessageId == event.clientMessageId) {
          _steering = const NoSteering();
        }
        if (!_pickedUpUsers.containsKey(event.clientMessageId) &&
            failedSubmission?.awaitingPickup != true) {
          _activeReplyAnchor = null;
          _turn = TranscriptTurnView(
            status: AppTurnStatus.error,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
            error: event.message,
          );
        }
      case AssistantDeltaReceived():
        _activeReplyAnchor = event.replyTo;
        _streaming =
            (_streaming?.inReplyTo == event.replyTo
                    ? _streaming
                    : StreamingMessage(inReplyTo: event.replyTo))
                ?.appendDelta(event.delta);
        _turn = TranscriptTurnView(
          status: AppTurnStatus.streaming,
          turnId: event.turnId ?? event.replyTo,
          replyTo: event.replyTo,
        );
      case AssistantMessageCommitted():
        _activeReplyAnchor = event.replyTo;
        _assistantReplyTo[event.messageId] = event.replyTo;
        _messageTimestamps[event.messageId] = event.ts;
        _appendAuthoritative(
          AssistantMsg(id: event.messageId, text: event.text),
          event.ts,
        );
        final assistantRow = _messageRows[event.messageId];
        if (assistantRow != null) {
          _firstAssistantRowByReplyTo.putIfAbsent(
            event.replyTo,
            () => assistantRow,
          );
          final userRow = _messageRows[event.replyTo];
          if (userRow == null || _compareRows(userRow, assistantRow) > 0) {
            _requiresReplyAnchoring = true;
          }
        }
        _streaming = null;
        _turn = TranscriptTurnView.idle;
      case AssistantDoneReceived():
        _activeReplyAnchor = null;
        _streaming = null;
        _turn = TranscriptTurnView.idle;
      case ToolRequested():
        _messageTimestamps.putIfAbsent(event.toolCallId, () => event.ts);
        _upsertTool(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: event.tool,
            args: event.args,
          ),
          event.ts,
        );
        final replyAnchor =
            _turn.replyTo ?? _streaming?.inReplyTo ?? _activeReplyAnchor;
        if (replyAnchor != null) {
          _activeReplyAnchor = replyAnchor;
          _turn = TranscriptTurnView(
            status: AppTurnStatus.awaitingTool,
            turnId: _turn.turnId ?? event.turnId ?? replyAnchor,
            replyTo: replyAnchor,
          );
        }
      case ToolFinished():
        _messageTimestamps[event.toolCallId] = event.ts;
        _upsertTool(
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
          event.ts,
        );
        if (_turn.status == AppTurnStatus.awaitingTool) {
          _turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: _turn.turnId,
            replyTo: _turn.replyTo,
          );
        }
      case CompactionRecorded():
        _activeReplyAnchor = null;
        _messageTimestamps[event.eventId] = event.ts;
        _appendAuthoritative(
          CompactionMsg(
            id: event.eventId,
            summary: event.summary,
            tokensBefore: event.tokensBefore,
          ),
          event.ts,
        );
        _streaming = null;
        _turn = TranscriptTurnView.idle;
    }
  }

  void _appendAuthoritative(ChatMessage message, DateTime timestamp) {
    if (!_authoritativeIds.add(message.id)) return;
    final row = _ProjectedRow(
      message: message,
      sortTimestamp: timestamp,
      timestamp: timestamp,
      arrival: _arrivalCounter++,
    );
    _messageRows[message.id] = row;
    _insertAuthoritative(row);
  }

  void _upsertTool(ToolEvent tool, DateTime timestamp) {
    final existing = _toolRows[tool.toolCallId];
    if (existing == null) {
      final row = _ProjectedRow(
        message: tool,
        sortTimestamp: timestamp,
        timestamp: timestamp,
        arrival: _arrivalCounter++,
      );
      _toolRows[tool.toolCallId] = row;
      _authoritativeIds.add(tool.id);
      _insertAuthoritative(row);
      return;
    }

    final previous = existing.message as ToolEvent;
    final preservesTerminalOutcome =
        tool.status == ToolEventStatus.pending &&
        previous.status != ToolEventStatus.pending;
    existing.message = ToolEvent(
      id: previous.id,
      toolCallId: previous.toolCallId,
      tool: previous.tool.isNotEmpty ? previous.tool : tool.tool,
      args: previous.tool.isNotEmpty ? previous.args : tool.args,
      status: preservesTerminalOutcome ? previous.status : tool.status,
      result: preservesTerminalOutcome ? previous.result : tool.result,
      error: preservesTerminalOutcome ? previous.error : tool.error,
    );
    existing.timestamp = timestamp;
    if (timestamp.millisecondsSinceEpoch <
        existing.sortTimestamp.millisecondsSinceEpoch) {
      _authoritativeRows.remove(existing);
      existing.sortTimestamp = timestamp;
      _insertAuthoritative(existing);
    }
  }

  void _insertAuthoritative(_ProjectedRow row) {
    var low = 0;
    var high = _authoritativeRows.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_compareRows(_authoritativeRows[middle], row) <= 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _authoritativeRows.insert(low, row);
  }

  int _compareRows(_ProjectedRow a, _ProjectedRow b) {
    final byTimestamp = a.sortTimestamp.millisecondsSinceEpoch.compareTo(
      b.sortTimestamp.millisecondsSinceEpoch,
    );
    return byTimestamp != 0 ? byTimestamp : a.arrival.compareTo(b.arrival);
  }

  TranscriptProjection _buildProjection() {
    final rows = <_ProjectedRow>[..._authoritativeRows];
    for (final submitted in _submittedUsers.values) {
      if (_pickedUpUsers.containsKey(submitted.clientMessageId)) continue;
      final failed = _failedUsers[submitted.clientMessageId];
      if (submitted.awaitingPickup && failed == null) continue;
      if (_acceptedUsers.containsKey(submitted.clientMessageId) &&
          failed == null) {
        continue;
      }
      rows.add(
        _ProjectedRow(
          message: UserMsg(
            id: submitted.clientMessageId,
            text: submitted.text,
            status: failed == null
                ? UserMsgStatus.pending
                : UserMsgStatus.failed,
            image: submitted.image,
          ),
          sortTimestamp: submitted.ts,
          timestamp:
              _messageTimestamps[submitted.clientMessageId] ?? submitted.ts,
          arrival: _arrivalCounter,
        ),
      );
    }

    final orderedRows = _requiresReplyAnchoring
        ? _anchorLatePrompts(rows)
        : rows;

    final messages = <ChatMessage>[];
    final timestamps = <DateTime>[];
    for (final row in orderedRows) {
      messages.add(row.message);
      timestamps.add(_messageTimestamps[row.message.id] ?? row.timestamp);
    }

    return TranscriptProjection(
      messages: List<ChatMessage>.unmodifiable(messages),
      messageTimestamps: List<DateTime>.unmodifiable(timestamps),
      streaming: _streaming,
      turn: TranscriptTurnView(
        status: _turn.status,
        sessionId: _sessionId,
        turnId: _turn.turnId,
        replyTo: _turn.replyTo,
        error: _turn.error,
      ),
      steering: _steering,
    );
  }

  List<_ProjectedRow> _anchorLatePrompts(List<_ProjectedRow> rows) {
    final canonicalIndexByUser = <String, int>{};
    final firstReplyIndexByUser = <String, int>{};
    for (var index = 0; index < rows.length; index++) {
      final message = rows[index].message;
      if (message is UserMsg) {
        canonicalIndexByUser.putIfAbsent(message.id, () => index);
      } else if (message is AssistantMsg) {
        final replyTo = _assistantReplyTo[message.id];
        if (replyTo != null) {
          firstReplyIndexByUser.putIfAbsent(replyTo, () => index);
        }
      }
    }

    final lateUserByReplyIndex = <int, _ProjectedRow>{};
    final lateUserIds = <String>{};
    for (final entry in canonicalIndexByUser.entries) {
      final replyIndex = firstReplyIndexByUser[entry.key];
      if (replyIndex != null && entry.value > replyIndex) {
        lateUserByReplyIndex[replyIndex] = rows[entry.value];
        lateUserIds.add(entry.key);
      }
    }

    final orderedRows = <_ProjectedRow>[];
    for (var index = 0; index < rows.length; index++) {
      final lateUser = lateUserByReplyIndex[index];
      if (lateUser != null) orderedRows.add(lateUser);
      final row = rows[index];
      if (row.message is UserMsg && lateUserIds.contains(row.message.id)) {
        continue;
      }
      orderedRows.add(row);
    }
    return orderedRows;
  }

  int? _firstChangedIndex(
    TranscriptProjection previous,
    TranscriptProjection next,
  ) {
    final sharedLength = previous.messages.length < next.messages.length
        ? previous.messages.length
        : next.messages.length;
    for (var index = 0; index < sharedLength; index++) {
      if (!_sameMessage(previous.messages[index], next.messages[index]) ||
          previous.messageTimestamps[index] != next.messageTimestamps[index]) {
        return index;
      }
    }
    return previous.messages.length == next.messages.length
        ? null
        : sharedLength;
  }

  bool _sameMessage(ChatMessage a, ChatMessage b) {
    if (a is ToolEvent && b is ToolEvent) {
      return a.id == b.id &&
          a.toolCallId == b.toolCallId &&
          a.tool == b.tool &&
          a.args.toString() == b.args.toString() &&
          a.status == b.status &&
          a.result.toString() == b.result.toString() &&
          a.error == b.error;
    }
    return a.runtimeType == b.runtimeType && a == b;
  }
}

/// Rebuild a transcript projection by folding the canonical incremental reducer.
TranscriptProjection deriveTranscriptProjection({
  required String sessionId,
  required Iterable<TranscriptEvent> events,
}) {
  final reducer = TranscriptProjectionReducer.empty(sessionId: sessionId);
  reducer.applyAll(events);
  return reducer.projection;
}
