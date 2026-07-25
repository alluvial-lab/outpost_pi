import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/rpc_json_object.dart';

/// Map raw JSON lines from `pi --mode rpc` stdout into typed [RpcEvent]s.
///
/// This is the only adapter that knows the event wire format; layers above
/// `data/` never receive `Map<String, dynamic>`. Unmapped event types become
/// [RpcUnknown], allowing newer Pi events to remain harmless to this client.
/// See `docs/rpc-protocol.md` for the schema.
class RpcEventMapper {
  const RpcEventMapper();

  RpcEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'agent_start':
        return const RpcAgentStart();
      case 'agent_end':
        return const RpcAgentEnd();
      case 'turn_start':
        return const RpcTurnStart();
      case 'turn_end':
        return const RpcTurnEnd();

      case 'response':
        return RpcCommandResponse(
          command: json['command'] as String? ?? '?',
          success: json['success'] == true,
          error: json['error'] as String?,
        );

      case 'tool_execution_start':
        return RpcToolStart(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '?',
          args: RpcJsonObject.tryFromWire(json['args']) ?? RpcJsonObject.empty,
        );

      case 'tool_execution_end':
        return RpcToolEnd(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '?',
          isError: json['isError'] == true,
          resultText: _extractContentText(json['result']),
        );

      case 'extension_ui_request':
        return _fromUiRequest(json);

      case 'message_update':
        return _fromMessageUpdate(json['assistantMessageEvent']);

      case 'message_start':
        final msg = json['message'];
        // Map a user message, whether locally echoed or received from the
        // app/mesh, to an input bubble.
        if (msg is Map<String, dynamic> && msg['role'] == 'user') {
          return RpcUserMessage(_contentText(msg['content']));
        }
        return _fromCustomMessage(msg);

      case 'message_end':
        // Surface the turn error when the assistant failed, such as when its
        // provider is unavailable. Deltas omit it; only the final message has it.
        final error = _errorMessageOf(json['message']);
        return error != null
            ? RpcStreamError(error)
            : const RpcUnknown('message_end');

      case 'auto_retry_start':
        return RpcAutoRetry(
          attempt: (json['attempt'] as num?)?.toInt() ?? 0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 0,
          delayMs: (json['delayMs'] as num?)?.toInt() ?? 0,
          message: json['errorMessage'] as String? ?? 'transient error',
        );

      default:
        return const RpcUnknown('<unknown-frame>');
    }
  }

  /// Dispatch a `message_start` with `role:"custom"` by its custom type.
  ///
  /// Other or missing roles become [RpcUnknown].
  RpcEvent _fromCustomMessage(Object? message) {
    if (message is! Map<String, dynamic>) {
      return const RpcUnknown('message_start');
    }
    if (message['role'] != 'custom') return const RpcUnknown('message_start');

    final customType = message['customType'] as String?;
    final details = RpcJsonObject.tryFromWire(message['details']);
    final detailValues = details?.values;

    switch (RpcControlOverlayEventType.fromWire(customType)) {
      case RpcControlOverlayEventType.relayState:
        if (detailValues == null) {
          return const RpcUnknown('message_start:relay-state:no-details');
        }
        final statusStr = detailValues['status'] as String?;
        return RpcRelayState(
          status: switch (statusStr) {
            'connected' => RelayStatus.connected,
            'reconnecting' => RelayStatus.reconnecting,
            _ => RelayStatus.disconnected,
          },
          connected: detailValues['connected'] == true,
          relayUrl: _nonEmptyString(detailValues['relayUrl']),
          room: _nonEmptyString(detailValues['room']),
        );
      case RpcControlOverlayEventType.nameAssigned:
        if (detailValues == null) {
          return const RpcUnknown('message_start:name-assigned:no-details');
        }
        final assigned = _nonEmptyString(detailValues['assigned']);
        if (assigned == null) {
          return const RpcUnknown('message_start:name-assigned:no-assigned');
        }
        return RpcNameAssigned(
          requested: _nonEmptyString(detailValues['requested']),
          assigned: assigned,
          changed: detailValues['changed'] == true,
        );
      case RpcControlOverlayEventType.paired:
        if (detailValues == null) {
          return const RpcUnknown('message_start:paired:no-details');
        }
        final name = _nonEmptyString(detailValues['name']);
        final peerId = _nonEmptyString(detailValues['peerId']);
        final pairedAt = _int(detailValues['pairedAt']);
        if (name == null || peerId == null || pairedAt == null) {
          return const RpcUnknown('message_start:paired:invalid-details');
        }
        return RpcPaired(name: name, peerId: peerId, pairedAt: pairedAt);
      case RpcControlOverlayEventType.meshRevoked:
        return RpcMeshRevoked(details: details);
      case null:
        return const RpcUnknown('<unknown-custom-message>');
    }
  }

  /// Extract text from a Pi message `content` value.
  ///
  /// Accepts either a raw string or a list of `{type:"text", text:"..."}`
  /// parts, ignores non-text parts such as images, and joins text with spaces.
  String _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final p in content) {
        if (p is String) {
          parts.add(p);
        } else if (p is Map && p['type'] == 'text' && p['text'] is String) {
          parts.add(p['text'] as String);
        }
      }
      return parts.join(' ');
    }
    return '';
  }

  /// Extract `errorMessage` when `stopReason == "error"`, or return `null`.
  String? _errorMessageOf(Object? message) {
    if (message is Map && message['stopReason'] == 'error') {
      final error = message['errorMessage'];
      if (error is String && error.isNotEmpty) return error;
      return 'unknown error';
    }
    return null;
  }

  /// Map an `extension_ui_request` to its supported domain event.
  ///
  /// Fire-and-forget `notify` becomes [RpcNotice], interactive requests become
  /// [RpcUiRequest], and TUI chrome methods remain ignored as [RpcUnknown].
  RpcEvent _fromUiRequest(Map<String, dynamic> json) {
    final method = json['method'] as String?;
    switch (method) {
      case 'notify':
        return RpcNotice(
          _str(json['message']) ?? '',
          switch (json['notifyType']) {
            'warning' => RpcNoticeLevel.warning,
            'error' => RpcNoticeLevel.error,
            _ => RpcNoticeLevel.info,
          },
        );
      case 'select':
      case 'confirm':
      case 'input':
      case 'editor':
        final id = _str(json['id']);
        if (id == null) return const RpcUnknown('extension_ui_request:no-id');
        final rawOptions = json['options'];
        // `placeholder` can be either a hint string or a
        // `{defaultValue: "..."}` object. Avoid a raw `as String` cast because
        // a mismatched shape would turn the whole event into <parse-error>.
        return RpcUiRequest(
          id: id,
          method: method!,
          title: _str(json['title']),
          message: _str(json['message']),
          placeholder: _str(json['placeholder']),
          defaultValue: _defaultValue(json),
          options: rawOptions is List
              ? rawOptions.map((o) => o.toString()).toList(growable: false)
              : const <String>[],
        );
      default:
        return const RpcUnknown('<unknown-ui-request>');
    }
  }

  /// Coerce to String without throwing; return `null` for non-string values.
  String? _str(Object? v) => v is String ? v : null;

  String? _nonEmptyString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  int? _int(Object? value) => value is num ? value.toInt() : null;

  /// Resolve the initial field value from `placeholder.defaultValue`,
  /// `defaultValue`, or `prefill`.
  ///
  /// This covers Outpost-Pi's `ui.input(title, {defaultValue})` shape.
  String? _defaultValue(Map<String, dynamic> json) {
    final p = json['placeholder'];
    if (p is Map && p['defaultValue'] is String) {
      return p['defaultValue'] as String;
    }
    return _str(json['defaultValue']) ?? _str(json['prefill']);
  }

  RpcEvent _fromMessageUpdate(Object? assistantMessageEvent) {
    if (assistantMessageEvent is! Map) {
      return const RpcUnknown('message_update');
    }
    final eventType = assistantMessageEvent['type'] as String?;
    switch (eventType) {
      case 'text_delta':
        return RpcTextDelta(assistantMessageEvent['delta'] as String? ?? '');
      case 'thinking_delta':
        return RpcThinkingDelta(
          assistantMessageEvent['delta'] as String? ?? '',
        );
      case 'text_end':
        return RpcTextEnd(assistantMessageEvent['content'] as String? ?? '');
      default:
        // text_start/thinking_start/toolcall_*/done/error remain ignored in the MVP.
        return const RpcUnknown('<unknown-message-update>');
    }
  }

  /// Concatenate text from a `{content: [{type:"text", text:...}]}` payload.
  String _extractContentText(Object? result) {
    if (result is Map && result['content'] is List) {
      return (result['content'] as List)
          .whereType<Map>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String? ?? '')
          .join('\n');
    }
    return '';
  }
}
