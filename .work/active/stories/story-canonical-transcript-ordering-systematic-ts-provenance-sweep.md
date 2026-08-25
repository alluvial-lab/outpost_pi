---
id: story-canonical-transcript-ordering-systematic-ts-provenance-sweep
kind: story
stage: done
tags: [app, pi-extension, bug]
parent: feature-canonical-transcript-ordering
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Systematic ts-provenance sweep (close the single-clock invariant)

Corrective work for `feature-canonical-transcript-ordering` after the standard
review (pass 1) returned REQUEST CHANGES. The core render-sort fix (Unit 3) is
sound but depends on an invariant — **every authoritative rendered bubble
carries a canonical server `ts`** — that three rounds of review have shown is
not fully achieved by incremental patching (deltas → tools → tool-history
divergence + fallback narration + AgentDone producer + error diagnostics).

Operator decision 2026-08-03: do a **systematic enumeration** of every
live-broadcast site (extension) and every authoritative-event-creation site
(app), rather than chasing the current four findings piecemeal — so no fifth
gap is missed.

## Method (enumerate FIRST, then fix)

### Phase 1 — Exhaustive enumeration (record the table in this body before any fix)

**Extension** (`pi-extension/src/index.ts` + the session projection / transcript
event log): for EVERY `_owners.broadcast(...)` of a server→app frame that has a
corresponding transcript/history event, record:

`{frame type, live-broadcast carries ts? (y/n), history event ts source, live ts == history ts? (y/n), gap}`

Key question per site: is there ONE timestamp owner, or does the live broadcast
compute a different `Date.now()` than the history event (which may be discarded
as a duplicate event-id, first-writer-wins)? The known case: `message_end`
records `tool_requested` with the SDK assistant `ts`
(`sdk_session_projection.ts:563-573`), then `tool_execution_start` broadcasts a
fresh `Date.now()` (`index.ts:1341-1362`). Find ALL such divergences.

**App** (`app/lib/data/sync/sync_service.dart`): for EVERY construction of an
authoritative-bubble-producing event (`UserMessageConfirmed`,
`AssistantMessageCommitted`, `ToolRequested`, `ToolFinished`,
`CompactionRecorded`) from a live frame, record:

`{event kind, wire frame carries ts?, app uses wire ts? (y/n), fallback to DateTime.now()? (y/n), is the fallback ever hit when the wire SHOULD carry ts? (the gap)}`

Authoritative bubbles are those that enter `authoritativeMessages` in
`deriveTranscriptProjection` (see `transcript_projection.dart`). Deltas,
optimistic `UserMessageSubmitted`, `AssistantDoneReceived`, `UserMessageFailed`
are non-authoritative — confirm + document, don't fix.

**Schema** (`protocol/schema/app-pi-server.schema.json`): list every live
server→app message type whose app-side event becomes an authoritative bubble,
and whether the schema has an optional `ts`. Flag any authoritative producer
that lacks a wire `ts` (known: error diagnostics, `:188-197`).

### Phase 2 — Fix every gap in the table

Per-site fix rules:
- **One timestamp owner.** Where the extension records a history event AND
  broadcasts a live frame for the same logical event, use ONE `ts` (reuse the
  recorded/request `ts` in the broadcast — do not compute a second `Date.now()`).
  If a later hook records the canonical `ts` (e.g. `message_end` for tools),
  the broadcast must carry that same value (look it up; do not re-stamp).
- **App consumes wire `ts`** for every authoritative producer, with
  `DateTime.now()` ONLY as a backward-compat fallback for old extensions or
  frames that genuinely lack `ts`. No phone-time stamping when a server `ts` is
  available.
- **Schema:** add optional `ts` (integer, min 0) to any authoritative-producer
  message type that lacks it (e.g. error frames), mirroring the existing
  optional-`ts` pattern. Regenerate TS + the Dart fixture (see below). Rust
  unchanged (app-pi excluded from rust codegen).
- **Document, don't fix:** genuinely-non-authoritative paths (deltas, optimistic
  submissions) — record as confirmed-excluded.

### Phase 3 — Verify

- Producer-connected tests (the review flagged synthetic-ts tests that don't
  exercise the real producer): extension asserts the LIVE frame `ts` EQUALS the
  history event `ts` for each fixed site; app asserts the real wire `ts` flows
  through (not an injected value).
- Extension: `check:protocol`, `typecheck`, `test` (the full suite's only known
  nonzero-exit is the pre-existing parked hot-reload flake — not this item).
- App: `flutter test --concurrency=2 --exclude-tags e2e test/domain test/data
  test/ui/chat` green; the 3 `streaming`-convergence guards stay green;
  `flutter analyze` clean.

## Dart regen (the fixture is the dart source-of-truth)

Edit `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` (maintained in
lockstep with the schema) for any schema `ts` addition, then regenerate:
```
node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart \
  --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json \
  --out app/lib/protocol/generated/protocol.g.dart
```
TS: `corepack pnpm generate:protocol` (from `pi-extension/`, with
`COREPACK_HOME=/tmp/corepack-home corepack pnpm --store-dir /tmp/pnpm-store …`
because `/home/agent/.local-state` is read-only).

## Out of scope

The projection render sort (`transcript_projection.dart`) — Unit 3, done; do not
touch. The store. Unrelated code.

## Acceptance

- [ ] Complete Phase-1 table in this body (every extension broadcast site +
      every app authoritative-creation site), with each gap marked.
- [ ] Every gap fixed (one ts owner; app consumes wire ts) OR documented as
      confirmed-excluded (non-authoritative).
- [ ] Producer-connected tests for each fixed site.
- [ ] Extension + app verification green (per Phase 3).
- [ ] The feature's single-clock invariant now actually holds (defensible
      against the table).

## Phase 1 — exhaustive ts-provenance enumeration

Enumeration was performed read-only before any production or test edit. “History
`ts`” below means the timestamp that survives `TranscriptEventLog`'s
first-writer-wins `eventId` dedupe and is later projected by `session_history`.

### Extension live/history table

| Live producer / frame | Live `ts`? | History fact and `ts` owner | Live equals history? | Phase-1 disposition |
|---|---:|---|---:|---|
| `SdkSessionProjection.appendLegacySdkMessageToTranscript` → `user_input` for workstation/RPC input | yes | `user_confirmed`; SDK user-message `timestamp` | yes | Sound. `message_end` owns both paths. |
| Same `user_input` site for app-origin input | yes | The earlier `_confirmUserDelivery` append already owns the same deterministic event id with its own `Date.now()`; the SDK-timestamp append is discarded | **no** | **Gap not present in pass-1 findings.** Live/replay can shift because two hooks stamp the same logical event. |
| `_confirmUserDelivery` → initial `user_message` echo | no | `user_confirmed`; `_confirmUserDelivery`'s `Date.now()` | no | **Gap not present in pass-1 findings.** A current extension makes the app take the phone-clock fallback. |
| `_attemptUserDelivery` delivered-id dedupe → repeated `user_message` echo | no | Existing `user_confirmed` event | no | **Gap not present in pass-1 findings.** The canonical history timestamp exists but is not looked up for the re-echo. |
| `SdkSessionProjection.appendLegacySdkMessageToTranscript` → `agent_message` | yes | `assistant_committed`; SDK assistant-message `timestamp` | yes | Sound. One `message_end` timestamp is appended and broadcast. |
| `tool_execution_start` → `tool_request` | yes | `tool_requested`; normally the earlier assistant `message_end` SDK timestamp (the start hook's fresh append loses first-writer-wins dedupe) | **no** | **Known review gap.** The broadcast stamps a second `Date.now()` instead of looking up the recorded request. |
| `tool_execution_end` → `tool_result` | yes | In the current process, `tool_finished`; the end hook's `Date.now()` wins and equals live. The later SDK `toolResult` `message_end` timestamp is discarded. After process restart, durable SDK backfill recreates the fact with the different SDK timestamp. | yes in-process; **no across restart** | **Gap not present in pass-1 findings.** There are still two timestamp owners for one logical result; restart can move the bubble. |
| assistant error `message_end` → `error(provider_error)` | no | `provider_error`; the handler's `Date.now()` | no | **Known review gap.** The canonical server timestamp is recorded but omitted from live. |
| Other current-extension `error` producers whose codes are rendered as diagnostics (`internal_error`, future renderable codes) | no | No replay fact; producer time must own the live-only diagnostic | n/a | **Known schema-family gap, broader than provider errors.** All renderable current-extension errors need server `ts`; `unknown_peer`, `session_mismatch`, and `delivery_pending` are app control paths and do not create bubbles. |
| `agent_end` → `agent_done` | no | `assistant_done`; `agent_end`'s `Date.now()` | no | **Known review gap.** This frame owns the legacy buffered-assistant fallback timestamp. |
| `session_compact` → `compaction` | yes | `compaction_recorded`; one local `ts` variable | yes | Sound. |
| `message_update` → `agent_chunk` | no | No authoritative history fact | n/a | Confirmed excluded: creates only `AssistantDeltaReceived`/streaming state, never an authoritative bubble. |
| queued-state and reset/session-history broadcasts | n/a | State/snapshot messages, not a paired live transcript fact | n/a | Confirmed excluded from the live-producer comparison. Replay events themselves all require server `ts`. |
| `_deliverMeshMessageToAgent` → `tool_request` + `tool_result` (`tool="agent-network"`) | no | No history fact | n/a | **Blocking discovery.** Despite the task's “Pi↔Pi, not app-facing” parenthetical, this function explicitly broadcasts both frames to `_owners`; the app persists them as `ToolRequested`/`ToolFinished`, and both enter `authoritativeMessages`. They therefore use phone time today. The path is also explicitly forbidden write scope, so it cannot be fixed in this story without operator/design re-alignment. |

No other direct `_owners.broadcast(...)` site both produces a live transcript
frame and has a corresponding transcript/history fact. The composition-root
`broadcast` adapters merely forward the `SdkSessionProjection` sites listed
above.

### App live-construction table

| App construction from live frame | Wire `ts` available? | Uses wire `ts`? | `DateTime.now()` fallback? | Phase-1 disposition |
|---|---:|---:|---:|---|
| `UserInput` (`user_input` or decoded `user_message`) → `UserMessageConfirmed` | optional | yes | yes | Consumer is correct, but the fallback is hit by current initial/dedupe `user_message` producers: extension gaps above. |
| `AgentMessage` → `AssistantMessageCommitted` | optional | yes | yes | Sound for current deterministic `agent_message`; fallback is genuine old-extension compatibility. |
| `AgentDone` buffered narration → `AssistantMessageCommitted` | optional | yes | yes | Consumer is correct, but current extension omits `ts`: producer gap. Its accompanying `AssistantDoneReceived` uses phone time but is non-authoritative. |
| `ToolRequest` buffered fallback narration → `AssistantMessageCommitted` | optional | **no** | unconditional | **Known review gap.** It must share one derived `requestTs` with the tool request. |
| `ToolRequest` → `ToolRequested` | optional | yes | yes | Consumer is correct; normal tools expose the extension provenance gaps above. Agent-network currently always hits the fallback. |
| `ToolResult` → `ToolFinished` | optional | yes | yes | Consumer is correct; normal live result is server-timed, but durable replay can use the second owner identified above. Agent-network currently always hits the fallback. |
| `ErrorMessage` → diagnostic `AssistantMessageCommitted` | no in current schema | no | unconditional | **Known review gap.** Add optional wire `ts`; use it for the diagnostic and its non-authoritative done boundary. Control-only error codes exit before construction. |
| `Compaction` → `CompactionRecorded` | optional | yes | yes | Sound; current extension always sends it. |
| `SessionHistory` events → all five authoritative event kinds | required per history-event schema | yes | no | Sound replay boundary. |

Confirmed non-authoritative constructions/exclusions: `AgentChunk` creates
`AssistantDeltaReceived`; optimistic `UserMessageSubmitted`, `UserMessageFailed`,
`AssistantDoneReceived`, cancellation terminals, and debug/index timestamps do
not enter `authoritativeMessages` and therefore do not participate in render
ordering.

### Schema table

| Live server→app type that can produce an authoritative bubble | Optional `ts` in schema? | Phase-1 disposition |
|---|---:|---|
| `user_input` | yes | Producer gaps on app-origin identity convergence, not a schema gap. |
| `user_message` | yes | Current initial/dedupe producers omit it. |
| `agent_message` | yes | Sound current producer. |
| `agent_done` | yes | Current producer omits it. |
| `tool_request` | yes | Normal request can diverge; agent-network omits it. |
| `tool_result` | yes | Normal result has two owners across restart; agent-network omits it. |
| `compaction` | yes | Sound current producer. |
| `error` | **no** | **Schema gap.** Add optional non-negative integer `ts` and regenerate TS/Dart. |
| `session_history` event union | required `ts` on every variant | Sound replay contract. |

`agent_chunk` also has an optional `ts`, but it is confirmed excluded because it
never directly creates an authoritative bubble.

## Implementation discovery

Phase 1 found a design/scope contradiction that prevents honest completion of
the acceptance criterion. `_deliverMeshMessageToAgent` is not merely an opaque
Pi↔Pi transport path: it deliberately sends app-facing `tool_request` and
`tool_result` frames (the source comment says the app renders them in the tool
timeline). `SyncService` persists those frames as authoritative tool events, so
they are covered by the feature's own definition of an authoritative rendered
bubble. They have no wire `ts`, and the app therefore assigns phone time.

The task explicitly forbids editing the agent-network mesh path. Consequently,
this story cannot both respect its write boundary and establish “every
authoritative rendered transcript bubble has canonical server `ts`.” Per the
design-flaw escape hatch, no Phase-2 code fix was attempted, the item returned
to `stage: drafting`, and operator/design re-alignment is required: either allow
timestamping/persisting those two app-facing mesh notifications, or explicitly
redesign them as non-authoritative UI state that does not enter the canonical
transcript projection.

The sweep also found two additional multi-owner cases beyond the review's four:
app-origin user confirmation (`_confirmUserDelivery` versus SDK `message_end`)
and tool-result restart backfill (`tool_execution_end` versus SDK
`message_end`). A revised design must name the durable SDK timestamp owner for
early/late hooks rather than relying only on first-writer-wins process-local
dedupe.

## Completion note — absorbed into durable transcript ownership (2026-08-25)

The enumeration is complete and its findings are now routed into the durable
transcript epic rather than remaining a second implementation item:

- F3 `epic-durable-transcript-ownership-durable-native-events` covers every
  native-event discovery: authoritative mesh request/result cards, distinct
  execution-hook tool request/result facts, compaction markers, and steering
  provenance. Its feature body records the per-kind durable migration, reopen
  behavior, and mixed-era fallback.
- F2 `feature-canonical-transcript-timestamp-ownership` retains the non-native
  residuals: ordinary user-confirmation/tool timestamp ownership, missing
  producer `ts` on echoes/agent_done/errors, schema and app consumption, plus
  live timestamp equality for the now-durable mesh cards.
- F1 already landed the v1 codec, persistence-before-visibility event log, SDK
  append binding, and durable-first mixed-era reconciliation on which both
  migrations depend.

This story closes as the ground-truth enumeration/design input.

## F2 closure update (2026-08-25)

The F2 implementation walked the table above against F1's landed durable APIs.
Every authoritative current-extension path is now closed:

| Former gap | Final owner/consumer disposition |
|---|---|
| App-origin initial, duplicate, and `message_end` echoes | Delivery hook persists one `user_confirmed.ts`; every echo reuses it. |
| Ordinary tool request/result | Execution hooks persist their lifecycle timestamp; live and reopen history use the durable fact. |
| Agent-network cards | The admitted request/result pair is persisted and each live frame reuses its event timestamp. |
| `agent_done` buffered fallback | `agent_end` persists and sends one timestamp; both fallback commit and terminal fact consume it. |
| Renderable errors | Provider facts are durable; optional `error.ts` covers provider/internal producers and the app consumes it. |
| Buffered pre-tool narration | One derived `requestTs` is shared with `ToolRequested`. |
| Compaction and deterministic assistant/user history | Already sound; unchanged. |
| Deltas, optimistic submissions, cancellation/debug state | Confirmed non-authoritative; excluded from render ordering. |

The remaining `DateTime.now()` branches beside authoritative constructions are
explicit compatibility fallbacks for ts-less pre-durable frames. Mixed-era tests
cover tools and errors, so compatibility is preserved without leaving a current
producer on the phone clock. The authoritative phone-`ts` residual count is now
zero.
