# `pi --mode rpc` protocol — schema used by Cockpit

Document for **Step 0 (spike)** of [plan 37](../../plan/37-desktop-cockpit.md).
Describes the RPC protocol spoken by `PiRpcProcess` (`lib/data/rpc/`) and
`pi --mode rpc`. **Empirically validated** (pi `0.78.1`, `/opt/homebrew/bin/pi`)
and checked against the official SDK documentation at
`@earendil-works/pi-coding-agent/docs/rpc.md`.

> Cockpit spawns `pi --mode rpc` **with extensions loaded** (revised decision B):
> `noSession`/`noExtensions` default to `false` (see
> `lib/app/core/env.dart` → `spawnArgs`). Extensions remain active to expose
> slash commands (`get_commands`) and Outpost-Pi control (relay/mesh/crypto)
> through the control overlay. With `noSession: true`, pi does not persist the
> session; `noExtensions: true` disables extensions (rarely used).

## Transport

- **Commands** → one JSON line through `stdin`.
- **Events + responses** ← one JSON line through `stdout`.
- **stderr** carries *warnings/diagnostics* (e.g., "Model not found…") — it is
  **not protocol**. `PiRpcProcess` reads stdout and stderr on separate channels;
  stderr becomes `RpcDiagnostic` and is never parsed as JSON.

### Framing (strict JSONL)

LF (`\n`) is the **only** record delimiter. A final `\r` is removed
(`\r\n` accepted). **Do not** use a generic line reader that splits on
`U+2028`/`U+2029` — they are valid *inside* JSON strings and could occur in the
middle of an event. Therefore `lib/data/rpc/jsonl_line_splitter.dart` splits only
on `\n` (rather than Dart's `LineSplitter`).

## Comandos que o Cockpit envia (stdin)

O Cockpit usa o protocolo RPC JSONL do Pi e, para o overlay Outpost-Pi, o schema
`protocol/schema/cockpit-control.schema.json`. O schema cobre a familia
`outpost_pi_control` e os eventos customizados `outpost-pi:*`; o transporte RPC
continua sendo uma linha `prompt` quando o comando precisa passar pelo hook de
input da extensao Outpost-Pi.

### `prompt` — manda um prompt do usuario  ✅ usado

```json
{"type": "prompt", "message": "liste os arquivos neste projeto"}
```

A resposta (`response`) chega **assim que o prompt e aceito/enfileirado**; os
eventos do turno seguem em streaming depois. `success: true` = aceito.

> ⚠️ **Correcao vs. plano 26/37**: o comando e `prompt` com campo `message` — **nao**
> `{type:"command", command:"sendUserMessage", ...}` (suposicao antiga do plano
> 26). O wire real do `0.78.1` e `{"type":"prompt","message":...}`.

**Durante streaming** (agente ocupado), um novo `prompt` e **recusado** a menos
que se passe `streamingBehavior`:

```json
{"type": "prompt", "message": "...", "streamingBehavior": "steer"}
```

- `"steer"`: entregue apos o turno atual terminar as tool calls, antes da proxima
  chamada ao LLM.
- `"followUp"`: entregue so quando o agente parar.

O MVP **desabilita o composer enquanto ocupado** (mais simples que enfileirar),
entao nao passa `streamingBehavior`. O gateway suporta `steerIfBusy` para o futuro.

### Overlay `outpost_pi_control` — controle Outpost-Pi  ✅ usado

Relay/rename nao sao prompts para o LLM. O Cockpit serializa um envelope de
controle schema-compatible e o carrega como string no mesmo comando `prompt` que
o Pi RPC ja expoe; a extensao Outpost-Pi intercepta o texto, executa a acao e
engole o input para nao poluir o transcript.

```json
{"type":"prompt","message":"{\"type\":\"outpost_pi_control\",\"command\":\"relay_status\"}"}
{"type":"prompt","message":"{\"type\":\"outpost_pi_control\",\"command\":\"rename\",\"name\":\"desk-agent\"}"}
```

O receptor ainda aceita o legado `\u0000outpost-pi-ctrl:<verb>` como shim de
compatibilidade, mas o Cockpit nao emite esse formato como caminho primario. Os
comandos validos sao os definidos no schema `cockpit-control`: `relay_on`,
`relay_off`, `relay_toggle`, `relay_status`, e `rename` com `name` nao vazio.

### Comandos request/response (correlacionados por `id`)  ✅ usados

Todo comando aceita um `id` opcional; se presente, a `response` ecoa o mesmo
`id`. O `PiRpcProcess` usa isso para um canal request/response: gera um `id`,
registra um `Completer`, manda o comando e completa quando a `response` com
aquele `id` chega no stdout (essas respostas **nao** entram no stream de
eventos — sao interceptadas). Timeout de 15s; processo morto → requests
pendentes falham (nao penduram).

Usados hoje pela toolbar do agente:

| Comando | Wire | `data` da resposta |
|---|---|---|
| `get_available_models` | `{"type":"get_available_models"}` | `{models:[{provider,id,name,reasoning,contextWindow,…}]}` (≈264 no setup deepseek+openrouter) |
| `get_state` | `{"type":"get_state"}` | `{model:Model\|null, thinkingLevel, isStreaming, …}` |
| `set_model` | `{"type":"set_model","provider":"…","modelId":"…"}` | o `Model` aplicado |
| `set_thinking_level` | `{"type":"set_thinking_level","level":"low"}` | — (niveis: off/minimal/low/medium/high/xhigh) |
| `get_session_stats` | `{"type":"get_session_stats"}` | `{…, contextUsage:{tokens,contextWindow,percent}}` |

> ⚠️ **`contextUsage.percent` esta na escala 0–100, nao 0–1.** Ex.: `tokens
> 8287 / contextWindow 1000000` → `percent: 0.8287` (= 0,83%). A UI usa `percent`
> direto e divide por 100 so para a barra de progresso.

> O modelo do spawn pode **nao** estar no `get_available_models` (ex.:
> `deepseek-chat` nao aparece no catalogo, que lista `deepseek-v4-*`). A toolbar
> injeta o modelo ativo na lista para nao ficar sem selecao.

### Outros comandos do protocolo (ainda nao usados)

`steer`, `follow_up`, `abort`, `new_session`, `get_messages`, `cycle_model`,
`cycle_thinking_level`, `compact`/`set_auto_compaction`,
`set_auto_retry`/`abort_retry`, `bash`/`abort_bash`, `export_html`,
`switch_session`/`fork`/`clone`, `set_session_name`, `get_commands`, …
Util proximo: `abort` → botao de "parar" o turno sem matar o processo.

## Eventos que o Cockpit recebe (stdout)

Eventos **nao** tem `id` (so respostas tem). Ordem real de um turno com tool call
(capturada do spike, deepseek):

```
agent_start
turn_start
message_start            (role:user — eco do nosso prompt)
message_end
message_start            (role:assistant, content:[])
message_update  × N      (thinking_delta…)
message_update  × N      (toolcall_start / toolcall_delta / toolcall_end)
message_end
tool_execution_start
tool_execution_update × N (partialResult acumulado)
tool_execution_end
message_start / message_end (role:toolResult)
turn_end
turn_start               (2ª rodada: o assistant responde com o resultado)
message_start (assistant)
message_update × N       (thinking_delta… text_start, text_delta…, text_end)
message_end
turn_end
agent_end
```

### Mapa evento → `RpcEvent` (dominio)

O `RpcEventMapper` (`lib/data/adapters/`) traduz cada linha em um
[`RpcEvent`](../lib/domain/entities/rpc_event.dart) tipado. O que o MVP consome:

| Linha JSON (stdout) | `RpcEvent` | Uso na UI |
|---|---|---|
| `{"type":"agent_start"}` | `RpcAgentStart` | marca `busy` |
| `{"type":"agent_end","messages":[…]}` | `RpcAgentEnd` | libera o composer |
| `{"type":"turn_start"}` / `{"type":"turn_end",…}` | `RpcTurnStart`/`RpcTurnEnd` | reseta buffers do turno |
| `{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"…"}}` | `RpcTextDelta` | streama o texto do assistant |
| `…"assistantMessageEvent":{"type":"text_end","content":"…"}` | `RpcTextEnd` | fecha o bloco de texto |
| `…"assistantMessageEvent":{"type":"thinking_delta","delta":"…"}` | `RpcThinkingDelta` | bloco de raciocinio (dim) |
| `{"type":"tool_execution_start","toolCallId":"…","toolName":"bash","args":{…}}` | `RpcToolStart` | card da tool (spinner) |
| `{"type":"tool_execution_end","toolCallId":"…","toolName":"…","isError":false,"result":{"content":[{"type":"text","text":"…"}]}}` | `RpcToolEnd` | resultado da tool |
| `{"type":"response","command":"prompt","success":true}` | `RpcCommandResponse` | ACK; mostra erro se `success:false` |
| `message_start` com `role:"custom"` + `customType:"outpost-pi:relay-state"` | `RpcRelayState` | status do botao/indicador do relay |
| `message_start` com `role:"custom"` + `customType:"outpost-pi:name-assigned"` | `RpcNameAssigned` | renomeia a aba quando o broker resolve colisao |
| `message_start` com `role:"custom"` + `customType:"outpost-pi:pair-code"` | `RpcPairCode` | evento schema-mapeado; a UI de sessao ignora por enquanto |
| `message_start` com `role:"custom"` + `customType:"outpost-pi:paired"` | `RpcPaired` | evento schema-mapeado; a UI de sessao ignora por enquanto |
| `message_start` com `role:"custom"` + `customType:"outpost-pi:mesh-revoked"` | `RpcMeshRevoked` | evento schema-mapeado; a UI de sessao ignora por enquanto |
| `{"type":"message_end","message":{"stopReason":"error","errorMessage":"Connection error."}}` | `RpcStreamError` | mostra o erro do turno (provider fora do ar etc.) |
| `{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"…"}` | `RpcAutoRetry` | linha "retentando (1/3…)" |
| *(stderr, nao-JSON)* | `RpcDiagnostic` | linha de diagnostico |
| *(processo saiu)* | `RpcProcessExit` | banner "encerrado (code=N)" |
| qualquer outro `type` | `RpcUnknown` | **ignorado** (nunca crasha) |

Tipos emitidos mas **ignorados** no MVP (viram `RpcUnknown`): outros
`message_start`, `message_end`, `tool_execution_update`, e os deltas
`text_start`, `thinking_start`/`thinking_end`,
`toolcall_start`/`toolcall_delta`/`toolcall_end`, `done`/`error`. Tambem:
`queue_update`, `compaction_*`, `extension_error`. Mapear
conforme as waves precisarem. (`auto_retry_*` **nao** esta mais aqui — e
parseado como `RpcAutoRetry`, ver linha acima.)

### Exemplos de linha reais (capturados)

`text_delta` (streaming do texto final):
```json
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":1,"delta":" directory","partial":{…}}}
```

`tool_execution_start` / `tool_execution_end`:
```json
{"type":"tool_execution_start","toolCallId":"call_00_n7…","toolName":"bash","args":{"command":"ls -la"}}
{"type":"tool_execution_end","toolCallId":"call_00_n7…","toolName":"bash","result":{"content":[{"type":"text","text":"total 16\n…"}],"details":{…}},"isError":false}
```

`agent_end`:
```json
{"type":"agent_end","messages":[{"role":"user",…},{"role":"assistant",…}]}
```

## Achados do spike (importam para a UI)

1. **`prompt`, nao `sendUserMessage`.** Wire real `{"type":"prompt","message":…}`.
2. **Fechar o stdin e o encerramento gracioso.** Ao fechar `stdin`, o pi sai com
   **code 0** sozinho — nao precisa de SIGTERM. O `kill()` do gateway fecha o
   stdin e so escala para SIGTERM→SIGKILL se ele nao sair em 3s. Resultado:
   **sem processo orfao** (`pgrep -f "cli.js --mode rpc"` limpo).
3. **`message_update` repete o `partial` inteiro.** Cada delta carrega o
   `message.partial` acumulado (cresce o turno todo). **Renderize pelo `delta`**,
   nao reparseando `partial` a cada tick — senao e O(n²) de payload.
4. **Modelos com reasoning streamam `thinking_*` pelo RPC** mesmo com
   `hideThinkingBlock` na TUI. A UI precisa tolerar (o MVP mostra dim).
5. **stderr ≠ protocolo.** Warnings (ex.: "Model … not found") saem no stderr. Ler
   junto com o stdout quebraria o parser JSONL. Canais separados.
6. **App macOS nao herda o PATH do shell.** O binario `pi` e resolvido por
   caminhos conhecidos (`/opt/homebrew/bin/pi`, `/usr/local/bin/pi`) ou
   `--dart-define=COCKPIT_PI_PATH=…`. Ver `lib/config/env.dart`.
7. **Sandbox do macOS bloqueia spawn + leitura de pasta.** Desligado nas
   entitlements (decisao B, dev tool local — fora da App Store por ora).
8. **Erro de turno nao vem nos deltas — vem na mensagem final.** Quando o
   provider falha (ex.: ollama fora do ar), o conteudo dos deltas e **vazio** e o
   erro esta em `message_end`/`agent_end` como `stopReason:"error"` +
   `errorMessage`, seguido de `auto_retry_start` (se retry ligado). Se a UI so
   olhar `text_delta`, ela fica **muda**. Por isso mapeamos `message_end(error)`
   → `RpcStreamError` e `auto_retry_start` → `RpcAutoRetry`.

## Provider/model no spawn

`pi --mode rpc` usa o provider/model do `~/.pi/agent/settings.json` por padrao.
Para o demo (a maquina tem o default `ollama`, que pode estar fora do ar),
aponte para um provider com chave via `--dart-define`:

```bash
flutter run -d macos \
  --dart-define=COCKPIT_PI_PROVIDER=deepseek \
  --dart-define=COCKPIT_PI_MODEL=deepseek-chat
```

Sem overrides → usa o default do pi. Ver `PiSpawnConfig` em `lib/config/env.dart`.

## Como reproduzir o spike

Headless, sem GUI (o gateway nao depende do Flutter):

```bash
dart run tool/rpc_smoke.dart   # spawn → prompt → stream → kill + checa orfao
```

Fonte oficial do schema (para waves futuras):
`/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/docs/rpc.md`
e os tipos em `dist/modes/rpc/rpc-types.d.ts`.
