/// Versão de domínio do stream de stdout do `pi --mode rpc`.
///
/// A `ui/` e o domínio **nunca** veem o wire format cru (`Map<String,dynamic>`).
/// O parse das linhas JSON acontece em `data/adapters/` e produz estes tipos.
/// Schema real documentado em `docs/rpc-protocol.md` (descoberto empiricamente
/// no spike do plano 37, pi 0.78.1).
sealed class RpcEvent {
  const RpcEvent();
}

/// `agent_start` — o agente começou a processar um prompt.
final class RpcAgentStart extends RpcEvent {
  const RpcAgentStart();
}

/// `agent_end` — o agente terminou o turno (volta a ficar ocioso).
final class RpcAgentEnd extends RpcEvent {
  const RpcAgentEnd();
}

/// `turn_start` — começou uma rodada (resposta do assistant + tools).
final class RpcTurnStart extends RpcEvent {
  const RpcTurnStart();
}

/// `turn_end` — a rodada terminou.
final class RpcTurnEnd extends RpcEvent {
  const RpcTurnEnd();
}

/// `message_update` com `assistantMessageEvent.type == "text_delta"`.
final class RpcTextDelta extends RpcEvent {
  const RpcTextDelta(this.delta);
  final String delta;
}

/// `message_update` com `assistantMessageEvent.type == "text_end"`.
final class RpcTextEnd extends RpcEvent {
  const RpcTextEnd(this.content);
  final String content;
}

/// `message_update` com `assistantMessageEvent.type == "thinking_delta"`.
/// (deepseek/raciocinadores emitem isto pelo RPC mesmo com thinking oculto na TUI.)
final class RpcThinkingDelta extends RpcEvent {
  const RpcThinkingDelta(this.delta);
  final String delta;
}

/// `tool_execution_start` — uma tool começou a executar.
final class RpcToolStart extends RpcEvent {
  const RpcToolStart({
    required this.toolCallId,
    required this.toolName,
    required this.args,
  });
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> args;
}

/// `tool_execution_end` — uma tool terminou (com o texto do resultado).
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

/// `response` — ACK (ou erro) de um comando que mandamos pelo stdin.
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

/// Falha do turno reportada via `stopReason: "error"` na mensagem do assistant
/// (ex.: `errorMessage: "Connection error."` quando o provider está fora do ar).
/// Vem nos eventos `message_end`/`agent_end`, não nos deltas.
final class RpcStreamError extends RpcEvent {
  const RpcStreamError(this.message);
  final String message;
}

/// `auto_retry_start` — o pi vai retentar após um erro transitório
/// (overloaded, rate-limit, 5xx, conexão recusada). `delayMs` é o backoff.
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

/// Texto cru do stderr do child (warnings do pi, ex.: "model not found").
/// **Não** é protocolo — é diagnóstico, mantido separado do stdout JSONL.
final class RpcDiagnostic extends RpcEvent {
  const RpcDiagnostic(this.text);
  final String text;
}

/// O child process terminou (saída limpa ou crash). `code == 0` é encerramento
/// gracioso (fechar o stdin já basta — ver spike).
final class RpcProcessExit extends RpcEvent {
  const RpcProcessExit(this.code);
  final int code;
}

/// Qualquer evento ainda não mapeado (compaction, retry, queue_update, deltas
/// de toolcall, message_start/end...). A UI ignora com segurança — nunca crasha.
final class RpcUnknown extends RpcEvent {
  const RpcUnknown(this.type, [this.raw = '']);
  final String type;
  final String raw;
}
