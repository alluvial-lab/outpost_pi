import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';

/// Non-projected transcript side entry.
///
/// Assistant/user/thinking/tool messages are rendered from immutable
/// [ProjectedTranscriptMessage] values in the session projection. These entries
/// remain for local side-channel rows such as process info, worked duration,
/// extension notices, and interactive UI requests.
sealed class AgentEntry {
  AgentEntry();
}

/// Record a lifecycle message such as an error ACK, stderr, or process exit.
final class InfoEntry extends AgentEntry {
  InfoEntry(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// Mark the end of a turn with the time the agent spent working.
final class WorkedEntry extends AgentEntry {
  WorkedEntry(this.duration);
  final Duration duration;
}

/// Represent an extension notice (`extension_ui_request` method `notify`).
///
/// This is not an agent response. [level] is 0 for info, 1 for warning, and 2
/// for error.
final class NoticeEntry extends AgentEntry {
  NoticeEntry(this.message, this.level);
  final String message;
  final int level;
}

/// Represent an interactive extension request (`select`, `confirm`, `input`,
/// or `editor`).
///
/// The transcript renders this as a card. Responding marks it [resolved], sets
/// [answerLabel], and sends `extension_ui_response`; it is intentionally
/// mutable.
final class UiRequestEntry extends AgentEntry {
  UiRequestEntry({
    required this.id,
    required this.method,
    this.title,
    this.message,
    this.placeholder,
    this.defaultValue,
    this.options = const <String>[],
  });

  final String id;
  final String method; // select | confirm | input | editor
  final String? title;
  final String? message;
  final String? placeholder;
  final String? defaultValue;
  final List<String> options;

  bool resolved = false;
  String? answerLabel;
}
