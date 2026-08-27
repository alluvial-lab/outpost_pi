# `pi --mode rpc` protocol — schema used by Cockpit

Current-state reference for the RPC protocol spoken by `PiRpcProcess`
(`lib/app/cockpit/data/rpc/pi_rpc_process.dart`) and `pi --mode rpc`.
The contract is checked against the official SDK documentation at
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
middle of an event. Therefore `lib/app/core/data/rpc/jsonl_line_splitter.dart` splits only
on `\n` (rather than Dart's `LineSplitter`).

## Commands the Cockpit sends (stdin)

The Cockpit uses Pi's JSONL RPC protocol and, for the Outpost-Pi overlay, the
schema `protocol/schema/cockpit-control.schema.json`. The schema covers the
`outpost_pi_control` family and the custom `outpost-pi:*` events; the RPC
transport remains a `prompt` line when the command needs to go through the
Outpost-Pi extension's input hook.

### `prompt` — sends a user prompt  ✅ used

```json
{"type": "prompt", "message": "list the files in this project"}
```

The response (`response`) arrives **as soon as the prompt is accepted/enqueued**;
the turn's events then stream in. `success: true` = accepted.

> ⚠️ **Correction vs. plan 26/37**: the command is `prompt` with a `message` field — **not**
> `{type:"command", command:"sendUserMessage", ...}` (an old assumption from plan
> 26). The actual wire in `0.78.1` is `{"type":"prompt","message":...}`.

**During streaming** (agent busy), a new `prompt` is **rejected** unless
`streamingBehavior` is passed:

```json
{"type": "prompt", "message": "...", "streamingBehavior": "steer"}
```

- `"steer"`: delivered after the current turn finishes its tool calls, before
  the next LLM call.
- `"followUp"`: delivered only when the agent stops.

The MVP **disables the composer while busy** (simpler than enqueuing), so it
does not pass `streamingBehavior`. The gateway supports `steerIfBusy` for the
future.

### `outpost_pi_control` overlay — Outpost-Pi control  ✅ used

Relay/rename are not prompts for the LLM. The Cockpit serializes a
schema-compatible control envelope and loads it as a string in the same
`prompt` command that Pi RPC already exposes; the Outpost-Pi extension
intercepts the text, executes the action, and swallows the input so it does not
pollute the transcript.

```json
{"type":"prompt","message":"{\"type\":\"outpost_pi_control\",\"command\":\"relay_status\"}"}
{"type":"prompt","message":"{\"type\":\"outpost_pi_control\",\"command\":\"rename\",\"name\":\"desk-agent\"}"}
```

The receiver still accepts the legacy `\u0000outpost-pi-ctrl:<verb>` as a
compatibility shim, but the Cockpit does not emit that format as the primary
path. The valid commands are those defined in the `cockpit-control` schema:
`relay_on`, `relay_off`, `relay_toggle`, `relay_status`, and `rename` with a
non-empty `name`.

### Request/response commands (correlated by `id`)  ✅ used

Every command accepts an optional `id`; if present, the `response` echoes the
same `id`. `PiRpcProcess` uses this for a request/response channel: it generates
an `id`, registers a `Completer`, sends the command, and completes when the
`response` with that `id` arrives on stdout (these responses **do not** enter
the event stream — they are intercepted). 15s timeout; dead process → pending
requests fail (they don't hang).

Used today by the agent toolbar:

| Command | Wire | Response `data` |
|---|---|---|
| `get_available_models` | `{"type":"get_available_models"}` | `{models:[{provider,id,name,reasoning,contextWindow,…}]}` (≈264 in the deepseek+openrouter setup) |
| `get_state` | `{"type":"get_state"}` | `{model:Model\|null, thinkingLevel, isStreaming, …}` |
| `set_model` | `{"type":"set_model","provider":"…","modelId":"…"}` | the applied `Model` |
| `set_thinking_level` | `{"type":"set_thinking_level","level":"low"}` | — (levels: off/minimal/low/medium/high/xhigh) |
| `get_session_stats` | `{"type":"get_session_stats"}` | `{…, contextUsage:{tokens,contextWindow,percent}}` |

> ⚠️ **`contextUsage.percent` is on a 0–100 scale, not 0–1.** E.g. `tokens
> 8287 / contextWindow 1000000` → `percent: 0.8287` (= 0.83%). The UI uses
> `percent` directly and divides by 100 only for the progress bar.

> The spawn model may **not** be in `get_available_models` (e.g.:
> `deepseek-chat` does not appear in the catalog, which lists `deepseek-v4-*`).
> The toolbar injects the active model into the list so it is never left without
> a selection.

### Other protocol commands (not yet used)

`steer`, `follow_up`, `abort`, `new_session`, `get_messages`, `cycle_model`,
`cycle_thinking_level`, `compact`/`set_auto_compaction`,
`set_auto_retry`/`abort_retry`, `bash`/`abort_bash`, `export_html`,
`switch_session`/`fork`/`clone`, `set_session_name`, `get_commands`, …
Useful next: `abort` → a "stop" button for the turn without killing the process.

## Events the Cockpit receives (stdout)

Events do **not** have an `id` (only responses do). Real order of a turn with a
tool call (captured from the spike, deepseek):

```
agent_start
turn_start
message_start            (role:user — echo of our prompt)
message_end
message_start            (role:assistant, content:[])
message_update  × N      (thinking_delta…)
message_update  × N      (toolcall_start / toolcall_delta / toolcall_end)
message_end
tool_execution_start
tool_execution_update × N (accumulated partialResult)
tool_execution_end
message_start / message_end (role:toolResult)
turn_end
turn_start               (2nd round: the assistant responds with the result)
message_start (assistant)
message_update × N       (thinking_delta… text_start, text_delta…, text_end)
message_end
turn_end
agent_end
```

### Event → `RpcEvent` map (domain)

`RpcEventMapper` (`lib/data/adapters/`) translates each line into a typed
[`RpcEvent`](../lib/domain/entities/rpc_event.dart). What the MVP consumes:

| JSON line (stdout) | `RpcEvent` | UI use |
|---|---|---|
| `{"type":"agent_start"}` | `RpcAgentStart` | marks `busy` |
| `{"type":"agent_end","messages":[…]}` | `RpcAgentEnd` | releases the composer |
| `{"type":"turn_start"}` / `{"type":"turn_end",…}` | `RpcTurnStart`/`RpcTurnEnd` | resets turn buffers |
| `{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"…"}}` | `RpcTextDelta` | streams the assistant text |
| `…"assistantMessageEvent":{"type":"text_end","content":"…"}` | `RpcTextEnd` | closes the text block |
| `…"assistantMessageEvent":{"type":"thinking_delta","delta":"…"}` | `RpcThinkingDelta` | reasoning block (dim) |
| `{"type":"tool_execution_start","toolCallId":"…","toolName":"bash","args":{…}}` | `RpcToolStart` | tool card (spinner) |
| `{"type":"tool_execution_end","toolCallId":"…","toolName":"…","isError":false,"result":{"content":[{"type":"text","text":"…"}]}}` | `RpcToolEnd` | tool result |
| `{"type":"response","command":"prompt","success":true}` | `RpcCommandResponse` | ACK; shows error if `success:false` |
| `extension_ui_request` `method:"notify"` with a schema-owned `outpost-pi:relay-state` JSON payload | `RpcRelayState` | relay button/indicator status; never model context |
| `extension_ui_request` `method:"notify"` with an `outpost-pi:name-assigned` JSON payload | `RpcNameAssigned` | renames the tab when the broker resolves a collision; never model context |
| `extension_ui_request` `method:"notify"` with an `outpost-pi:paired` JSON payload | `RpcPaired` | schema-mapped event; the session UI ignores it for now |
| `extension_ui_request` `method:"notify"` with an `outpost-pi:mesh-revoked` JSON payload | `RpcMeshRevoked` | schema-mapped event; the session UI ignores it for now |
| `{"type":"message_end","message":{"stopReason":"error","errorMessage":"Connection error."}}` | `RpcStreamError` | shows the turn error (provider down, etc.) |
| `{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"…"}` | `RpcAutoRetry` | "retrying (1/3…)" line |
| *(stderr, non-JSON)* | `RpcDiagnostic` | diagnostic line |
| *(process exited)* | `RpcProcessExit` | "terminated (code=N)" banner |
| any other `type` | `RpcUnknown` | **ignored** (never crashes) |

The mapper also accepts the older `message_start`/`role:"custom"` wrapper so a
frozen Cockpit binary can observe status from an older extension during a local
upgrade. New extension status uses the RPC UI channel because `pi.sendMessage`
custom messages always participate in model context, even with `display:false`.

Types emitted but **ignored** in the MVP (become `RpcUnknown`): other
`message_start`, `message_end`, `tool_execution_update`, and the deltas
`text_start`, `thinking_start`/`thinking_end`,
`toolcall_start`/`toolcall_delta`/`toolcall_end`, `done`/`error`. Also:
`queue_update`, `compaction_*`, `extension_error`. Map them as the waves need
them. (`auto_retry_*` is **no longer** here — it is parsed as `RpcAutoRetry`,
see the line above.)

### Real line examples (captured)

`text_delta` (streaming the final text):
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

## Spike findings (matter for the UI)

1. **`prompt`, not `sendUserMessage`.** Actual wire `{"type":"prompt","message":…}`.
2. **Closing stdin and graceful shutdown.** On closing `stdin`, pi exits with
   **code 0** on its own — no SIGTERM needed. The gateway's `kill()` closes
   stdin and only escalates to SIGTERM→SIGKILL if it doesn't exit in 3s. Result:
   **no orphan process** (`pgrep -f "cli.js --mode rpc"` clean).
3. **`message_update` repeats the entire `partial`.** Each delta carries the
   accumulated `message.partial` (grows for the whole turn). **Render by `delta`**,
   don't re-parse `partial` on every tick — otherwise it's O(n²) in payload.
4. **Models with reasoning stream `thinking_*` over RPC** even with
   `hideThinkingBlock` in the TUI. The UI must tolerate it (the MVP shows it dim).
5. **stderr ≠ protocol.** Warnings (e.g.: "Model … not found") go to stderr.
   Reading it alongside stdout would break the JSONL parser. Separate channels.
6. **The macOS app does not inherit the shell PATH.** The `pi` binary is
   resolved via known paths (`/opt/homebrew/bin/pi`, `/usr/local/bin/pi`) or
   `--dart-define=COCKPIT_PI_PATH=…`. See `lib/config/env.dart`.
7. **The macOS sandbox blocks spawning + folder reads.** Disabled in the
   entitlements (decision B, local dev tool — outside the App Store for now).
8. **A turn error doesn't come in the deltas — it comes in the final message.**
   When the provider fails (e.g.: ollama down), the delta content is **empty**
   and the error is in `message_end`/`agent_end` as `stopReason:"error"` +
   `errorMessage`, followed by `auto_retry_start` (if retry is on). If the UI
   only looks at `text_delta`, it goes **mute**. That's why we map
   `message_end(error)` → `RpcStreamError` and `auto_retry_start` →
   `RpcAutoRetry`.

## Provider/model at spawn

`pi --mode rpc` uses the provider/model from `~/.pi/agent/settings.json` by
default. For the demo (the machine has `ollama` as the default, which may be
down), point it at a provider with a key via `--dart-define`:

```bash
flutter run -d macos \
  --dart-define=COCKPIT_PI_PROVIDER=deepseek \
  --dart-define=COCKPIT_PI_MODEL=deepseek-chat
```

Without overrides → uses the pi default. See `PiSpawnConfig` in
`lib/config/env.dart`.

## How to reproduce the spike

Headless, no GUI (the gateway doesn't depend on Flutter):

```bash
dart run tool/rpc_smoke.dart   # spawn → prompt → stream → kill + checks for orphans
```

Official schema source (for future waves):
`/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/docs/rpc.md`
and the types in `dist/modes/rpc/rpc-types.d.ts`.
