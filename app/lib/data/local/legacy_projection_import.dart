import 'dart:convert';

import 'package:app/data/local/records/message_record.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:crypto/crypto.dart';

/// Convert a validated legacy message projection into canonical transcript events.
final class LegacyProjectionImport {
  const LegacyProjectionImport._();

  /// Preserve visible message state with deterministic event identities.
  ///
  /// Throws [FormatException] when a legacy tool row cannot be represented by
  /// the canonical transcript contract without changing its meaning.
  static List<TranscriptEvent> toEvents({
    required TranscriptSessionKey session,
    required Iterable<MessageRecord> rows,
  }) {
    final ordered = rows.toList(growable: false)
      ..sort((left, right) {
        final bySequence = left.seq.compareTo(right.seq);
        return bySequence == 0 ? left.id.compareTo(right.id) : bySequence;
      });
    final events = <TranscriptEvent>[];
    for (final row in ordered) {
      String eventId(String phase) => _eventId(session, row, phase);
      switch (row.role) {
        case MsgRole.user:
          if (row.status == UserMsgStatus.confirmed) {
            events.add(
              UserMessageConfirmed(
                eventId: eventId('user_confirmed'),
                sessionId: session.sessionId,
                ts: row.ts,
                clientMessageId: row.id,
                text: row.text,
                image: row.image,
              ),
            );
          } else {
            events.add(
              UserMessageSubmitted(
                eventId: eventId('user_submitted'),
                sessionId: session.sessionId,
                ts: row.ts,
                clientMessageId: row.id,
                text: row.text,
                image: row.image,
              ),
            );
            if (row.status == UserMsgStatus.failed) {
              events.add(
                UserMessageFailed(
                  eventId: eventId('user_failed'),
                  sessionId: session.sessionId,
                  ts: row.ts,
                  clientMessageId: row.id,
                  code: 'legacy_projection',
                  message: 'Legacy message delivery failed.',
                ),
              );
            }
          }
        case MsgRole.assistant:
          events.add(
            AssistantMessageCommitted(
              eventId: eventId('assistant_message'),
              sessionId: session.sessionId,
              ts: row.ts,
              messageId: row.id,
              replyTo: 'legacy:${session.sessionId}:root',
              text: row.text,
            ),
          );
        case MsgRole.tool:
          final tool = row.tool;
          if (tool == null) {
            throw const FormatException('Legacy tool row is missing tool data');
          }
          events.add(
            ToolRequested(
              eventId: eventId('tool_requested'),
              sessionId: session.sessionId,
              ts: row.ts,
              toolCallId: tool.toolCallId,
              tool: tool.tool,
              args: _objectMap(tool.args),
            ),
          );
          if (tool.status != ToolEventStatus.pending) {
            events.add(
              ToolFinished(
                eventId: eventId('tool_finished'),
                sessionId: session.sessionId,
                ts: row.ts,
                toolCallId: tool.toolCallId,
                result: tool.result,
                error: tool.status == ToolEventStatus.failed
                    ? (tool.error ?? 'Legacy tool failed.')
                    : tool.error,
              ),
            );
          }
        case MsgRole.compaction:
          events.add(
            CompactionRecorded(
              eventId: eventId('compaction'),
              sessionId: session.sessionId,
              ts: row.ts,
              summary: row.text,
              tokensBefore: row.tokensBefore,
            ),
          );
      }
    }
    return events;
  }

  static String _eventId(
    TranscriptSessionKey session,
    MessageRecord row,
    String phase,
  ) {
    final canonical = _canonicalize(<Object?>[
      session.peerId,
      session.roomId,
      session.sessionId,
      row.toJson(),
      phase,
    ]);
    return 'legacy_projection:${sha256.convert(utf8.encode(jsonEncode(canonical)))}';
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value == null) return <String, Object?>{};
    if (value is! Map) {
      throw const FormatException('Legacy tool args must be an object');
    }
    return value.map((key, value) {
      if (key is! String) {
        throw const FormatException('Legacy tool arg keys must be strings');
      }
      return MapEntry(key, _canonicalize(value));
    });
  }

  static Object? _canonicalize(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    if (value is Map) {
      final keys = value.keys.map((key) {
        if (key is! String) {
          throw const FormatException('Legacy map keys must be strings');
        }
        return key;
      }).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    throw FormatException(
      'Unsupported legacy projection value: ${value.runtimeType}',
    );
  }
}
