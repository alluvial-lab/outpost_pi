import 'package:cockpit/domain/entities/rpc_event.dart';

/// Converte a linha JSON crua do stdout do `pi --mode rpc` em [RpcEvent]
/// tipado. **Único lugar** que conhece o wire format — nada acima da `data/`
/// vê `Map<String,dynamic>`.
///
/// Schema em `docs/rpc-protocol.md`. Tipos não mapeados viram [RpcUnknown]
/// (a UI os ignora) — assim novos eventos do pi nunca derrubam o cliente.
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
          args: _asStringMap(json['args']),
        );

      case 'tool_execution_end':
        return RpcToolEnd(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '?',
          isError: json['isError'] == true,
          resultText: _extractContentText(json['result']),
        );

      case 'message_update':
        return _fromMessageUpdate(json['assistantMessageEvent']);

      case 'message_end':
        // Carrega o erro do turno quando o assistant falhou (provider fora do
        // ar, etc.). Os deltas não trazem isso — só a mensagem final.
        final error = _errorMessageOf(json['message']);
        return error != null ? RpcStreamError(error) : const RpcUnknown('message_end');

      case 'auto_retry_start':
        return RpcAutoRetry(
          attempt: (json['attempt'] as num?)?.toInt() ?? 0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 0,
          delayMs: (json['delayMs'] as num?)?.toInt() ?? 0,
          message: json['errorMessage'] as String? ?? 'erro transitório',
        );

      default:
        return RpcUnknown(type ?? '<none>');
    }
  }

  /// `errorMessage` de uma mensagem com `stopReason == "error"`, ou `null`.
  String? _errorMessageOf(Object? message) {
    if (message is Map && message['stopReason'] == 'error') {
      final error = message['errorMessage'];
      if (error is String && error.isNotEmpty) return error;
      return 'erro desconhecido';
    }
    return null;
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
        // text_start/thinking_start/toolcall_*/done/error — ignorados no MVP.
        return RpcUnknown('message_update:${eventType ?? "?"}');
    }
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const {};
  }

  /// Extrai o texto concatenado de um `{content: [{type:"text", text:...}]}`.
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
