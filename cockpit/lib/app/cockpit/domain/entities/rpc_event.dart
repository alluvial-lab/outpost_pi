import 'package:cockpit/app/cockpit/domain/value_objects/rpc_json_object.dart';

/// Represent the domain form of the `pi --mode rpc` stdout stream.
///
/// The domain and `ui/` never see the raw wire format (`Map<String,dynamic>`).
/// `data/adapters/` parses JSON lines into these types. The observed schema is
/// documented in `docs/rpc-protocol.md` from the Plan 37 spike against Pi 0.78.1.
sealed class RpcEvent {
  const RpcEvent();
}

/// `agent_start` — the agent began processing a prompt.
final class RpcAgentStart extends RpcEvent {
  const RpcAgentStart();
}

/// `agent_end` — the agent finished the turn and became idle.
final class RpcAgentEnd extends RpcEvent {
  const RpcAgentEnd();
}

/// `turn_start` — an assistant-and-tools round began.
final class RpcTurnStart extends RpcEvent {
  const RpcTurnStart();
}

/// `turn_end` — the round ended.
final class RpcTurnEnd extends RpcEvent {
  const RpcTurnEnd();
}

/// `message_update` with `assistantMessageEvent.type == "text_delta"`.
final class RpcTextDelta extends RpcEvent {
  const RpcTextDelta(this.delta);
  final String delta;
}

/// `message_update` with `assistantMessageEvent.type == "text_end"`.
final class RpcTextEnd extends RpcEvent {
  const RpcTextEnd(this.content);
  final String content;
}

/// `message_start` with `role == "user"` — a user message added to the session.
///
/// Emitted for both local sends (echoing typed input) and messages arriving
/// **externally** from the app or mesh. The UI displays remote message bubbles;
/// local messages are inserted optimistically and deduplicated.
final class RpcUserMessage extends RpcEvent {
  const RpcUserMessage(this.text);
  final String text;
}

/// `message_update` with `assistantMessageEvent.type == "thinking_delta"`.
/// Reasoning models such as DeepSeek emit this through RPC even when thinking is hidden in the TUI.
final class RpcThinkingDelta extends RpcEvent {
  const RpcThinkingDelta(this.delta);
  final String delta;
}

/// `tool_execution_start` — a tool began executing.
final class RpcToolStart extends RpcEvent {
  const RpcToolStart({
    required this.toolCallId,
    required this.toolName,
    required this.args,
  });
  final String toolCallId;
  final String toolName;
  final RpcJsonObject args;
}

/// `tool_execution_end` — a tool finished with result text.
final class RpcToolEnd extends RpcEvent {
  const RpcToolEnd({
    required this.toolCallId,
    required this.toolName,
    required this.isError,
    required this.resultText,
  });
  final String toolCallId;
  final String toolName;
  final bool isError;
  final String resultText;
}

/// `response` — acknowledgement or error for a command sent over stdin.
final class RpcCommandResponse extends RpcEvent {
  const RpcCommandResponse({
    required this.command,
    required this.success,
    this.error,
  });
  final String command;
  final bool success;
  final String? error;
}

/// Turn failure reported by `stopReason: "error"` in the assistant message.
///
/// For example, an unavailable provider may report
/// `errorMessage: "Connection error."`. This arrives in `message_end` or
/// `agent_end`, not in deltas.
final class RpcStreamError extends RpcEvent {
  const RpcStreamError(this.message);
  final String message;
}

/// `auto_retry_start` — Pi will retry after a transient failure.
///
/// Covers overload, rate limits, 5xx responses, and refused connections;
/// `delayMs` is the backoff.
final class RpcAutoRetry extends RpcEvent {
  const RpcAutoRetry({
    required this.attempt,
    required this.maxAttempts,
    required this.delayMs,
    required this.message,
  });
  final int attempt;
  final int maxAttempts;
  final int delayMs;
  final String message;
}

/// Classify content-free child-process diagnostics.
enum RpcDiagnosticKind { childStderr, streamReadFailure }

/// Report the fact of a child-process diagnostic without retaining its text.
///
/// Stderr and stream errors are untrusted diagnostic surfaces, not protocol
/// data. Only the fixed [kind] crosses the process boundary into the UI.
final class RpcDiagnostic extends RpcEvent {
  const RpcDiagnostic(this.kind);
  final RpcDiagnosticKind kind;
}

/// The child process exited cleanly or crashed.
///
/// `code == 0` denotes graceful shutdown; closing stdin is sufficient, as
/// established by the spike.
final class RpcProcessExit extends RpcEvent {
  const RpcProcessExit(this.code);
  final int code;
}

/// Classify the severity of an [RpcNotice] from `extension_ui_request` method `notify`.
enum RpcNoticeLevel { info, warning, error }

/// `extension_ui_request` method `notify` — a fire-and-forget extension notice.
///
/// Carries mesh status, "QR ready", or errors and expects no response.
final class RpcNotice extends RpcEvent {
  const RpcNotice(this.message, this.level);
  final String message;
  final RpcNoticeLevel level;
}

/// Interactive `extension_ui_request` for `select`, `confirm`, `input`, or `editor`.
///
/// The extension requests user input and **waits** for an
/// `extension_ui_response` with the same [id] on stdin. Without a response, the
/// extension remains pending until its own timeout.
final class RpcUiRequest extends RpcEvent {
  const RpcUiRequest({
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
  final String? message; // confirm
  final String? placeholder; // input/editor — hint
  final String? defaultValue; // input/editor — initial prefilled value
  final List<String> options; // select
}

/// Describe relay connectivity for [RpcRelayState].
enum RelayStatus { connected, reconnecting, disconnected }

/// Canonical custom event names from `protocol/schema/cockpit-control.schema.json`.
enum RpcControlOverlayEventType {
  relayState('outpost-pi:relay-state'),
  nameAssigned('outpost-pi:name-assigned'),
  paired('outpost-pi:paired'),
  meshRevoked('outpost-pi:mesh-revoked');

  const RpcControlOverlayEventType(this.wire);

  final String wire;

  static RpcControlOverlayEventType? fromWire(String? wire) {
    for (final eventType in values) {
      if (eventType.wire == wire) return eventType;
    }
    return null;
  }
}

/// `message_start` with `role:"custom"` and `customType:"outpost-pi:relay-state"`.
///
/// Emitted for every relay transition: enabled, dropped into reconnecting,
/// disabled, or reconnected. Also emitted in response to `relay:status` control.
final class RpcRelayState extends RpcEvent {
  const RpcRelayState({
    required this.status,
    required this.connected,
    this.relayUrl,
    this.room,
  });

  final RelayStatus status;
  final bool connected;
  final String? relayUrl;
  final String? room;
}

/// `message_start` with `role:"custom"` and `customType:"outpost-pi:name-assigned"`.
///
/// Emitted by the broker when joining the mesh. The broker may assign a name
/// different from the requested `agent_name` to avoid a collision, such as
/// "Proj" → "Proj#2". When [changed] is `false`, [assigned] equals the original
/// name and requires no action.
final class RpcNameAssigned extends RpcEvent {
  const RpcNameAssigned({
    required this.assigned,
    required this.changed,
    this.requested,
  });

  /// Name requested by the user before any collision resolution.
  final String? requested;

  /// Effective name assigned by the broker and displayed in the mesh.
  final String assigned;

  /// Whether the broker changed the requested name to resolve a collision.
  final bool changed;
}

/// `message_start` with `customType:"outpost-pi:paired"`.
final class RpcPaired extends RpcEvent {
  const RpcPaired({
    required this.name,
    required this.peerId,
    required this.pairedAt,
  });

  final String name;
  final String peerId;
  final int pairedAt;
}

/// `message_start` with `customType:"outpost-pi:mesh-revoked"`.
final class RpcMeshRevoked extends RpcEvent {
  const RpcMeshRevoked({this.details});

  final RpcJsonObject? details;
}

/// Preserve the category of any event not yet mapped, including compaction,
/// retry, queue updates, tool-call deltas, message boundaries, and status or
/// title changes.
///
/// The UI safely ignores these events rather than crashing. Raw wire content is
/// deliberately not retained because diagnostics must remain content-free.
final class RpcUnknown extends RpcEvent {
  const RpcUnknown(this.type);
  final String type;
}
