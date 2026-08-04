---
id: story-canonical-transcript-timestamp-ownership-ownership-foundation
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Timestamp-ownership foundation (extension owns the canonical ts)

Unit A of `feature-canonical-transcript-timestamp-ownership` — the foundation.
Make the execution/delivery hook the single canonical `ts` owner per event so
live broadcast == history == durable replay. Q1 decision = B; governing
principle: the extension is the sole authoritative `ts` owner.

## Change

- `pi-extension/src/session/transcript_event_log.ts` — add a recorded-`ts`
  lookup (e.g. `recordedTsFor(eventId)`) over the existing append-only,
  first-writer-wins `events`/`seen` (it exposes no ts lookup today).
- `pi-extension/src/session/sdk_session_projection.ts` (~`:563-573` + the
  `toolResult` arm) — `message_end`-driven recording REUSES the already-recorded
  `ts` (via the new lookup) for `tool_requested`/`tool_finished`/
  `user_confirmed`, instead of stamping the SDK block `ts`, so the late hook no
  longer competes with the earlier execution/delivery hook.
- `pi-extension/src/index.ts` — `tool_execution_start`/`tool_execution_end`,
  `_confirmUserDelivery` compute ONE `Date.now()` per logical event and share it
  across the history append and the live broadcast (no second stamp).

## START with the durability spike (riskiest assumption)

`TranscriptEventLog` is process-local; the SDK owns the DURABLE record that
backfills on restart. Unit A must FIRST spike whether the durable record can
carry the execution-hook `ts` (so live == durable across restart). If the SDK
cannot be made to agree durably, fall back to: the app re-syncs from
`session_history` on reconnect (canonical by then), so the render sort tolerates
a transient live≠durable pre-reconnect — document + accept that residual.

## Acceptance

- [ ] For tool-request, tool-result, and app-origin user-confirmed, the LIVE
  broadcast `ts` EQUALS the history/replay `ts` (producer-connected extension
  test, NOT an injected value).
- [ ] `TranscriptEventLog` exposes the recorded-`ts` lookup; no second
  `Date.now()` per logical event.
- [ ] Durability outcome documented (agreement achieved OR the accepted residual).

## Ordering

`depends_on: []` (foundation). Unlocks B and C.

## Durability spike finding

### Verdict: FEASIBLE, with a required durable custom-entry overlay

The SDK does **not** immutably own the inner message timestamp. A `message_end`
handler may return a same-role replacement message
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts:783-785`);
the runner adopts that replacement
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/runner.js:562-599`),
mutates the finalized agent message before persistence
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:396-400,453-468`),
and only then calls `SessionManager.appendMessage(event.message)`
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:324-339`).
`appendMessage` preserves that inner message object verbatim; it separately stamps
an SDK-owned ISO timestamp on the containing JSONL entry
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js:705-713`).
Backfill uses the inner `message.timestamp`, not the containing entry timestamp:
`buildSessionContext` returns the stored message
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js:166-175,232-236`),
and Outpost maps `message.timestamp` into transcript `ts`
(`pi-extension/src/session/transcript_projection.ts:145-149,201-217`).

There is one load-bearing correction to the feature's assumed ordering:
**assistant `message_end` precedes `tool_execution_start`**, not vice versa.
The agent loop awaits the completed assistant response, whose stream emits
`message_end`, before extracting/executing its tool calls
(`pi-extension/node_modules/.pnpm/@earendil-works+pi-agent-core@0.80.6_@modelcontextprotocol+sdk@1.29.0_zod@4.4.3__ws@8.21.0_zod@4.4.3/node_modules/@earendil-works/pi-agent-core/dist/agent-loop.js:105-122,240-253`);
tool execution starts later (`.../pi-agent-core/dist/agent-loop.js:287-304,332-340`).
Therefore a request hook cannot retroactively replace the already-appended
assistant message's timestamp. One assistant message can also contain multiple
tool calls (`.../pi-agent-core/dist/agent-loop.js:113-122,287-300`), each with a
different execution-start clock, so the single assistant-message timestamp is
not a sufficient durable representation.

The official SDK escape hatch makes full agreement feasible: `ExtensionAPI.appendEntry`
is explicitly a persistence API (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts:895-907`), delegates to
`SessionManager.appendCustomEntry` (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:1840-1844`), and stores caller data in
the append-only session JSONL (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js:663-697,757-767`). Custom entries are
specifically intended to reconstruct extension state after reload and are ignored
by LLM context (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.d.ts:56-63`). The read-only session surface exposes the
active, compaction-aware `buildContextEntries()` list, including custom entries
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.d.ts:136,258-261`). Thus Unit A can persist each hook-owned canonical event
inside the SDK session and prefer it over the ordinary SDK-message projection
during restart backfill. The standard user/tool-result messages can additionally
receive the owner `ts` through the `message_end` replacement API; tool requests
use the durable custom entry because of the ordering above.

### Current single-tool timestamp trace

Let `A` be the provider-created assistant message's `timestamp`, `S` the
`Date.now()` in `tool_execution_start`, `E` the `Date.now()` in
`tool_execution_end`, and `R` the tool-result message's later `Date.now()`.
These are four separate reads in the current code.

1. **Live wire (a):** `tool_request.ts = S`; the start handler computes `S`,
   appends, and broadcasts it (`pi-extension/src/index.ts:1341-1362`).
   `tool_result.ts = E`; the end handler computes, appends, and broadcasts `E`
   (`pi-extension/src/index.ts:1365-1392`).
2. **Process-local `TranscriptEventLog` (b):** request `ts = A`, not `S`.
   Real SDK order delivers assistant `message_end` first; Outpost records the
   assistant tool-call block with its SDK timestamp
   (`pi-extension/src/index.ts:1402-1424`;
   `pi-extension/src/session/sdk_session_projection.ts:484-486,563-572`). The
   later start append has the same deterministic event id and loses the log's
   first-writer-wins check (`pi-extension/src/session/transcript_event_log.ts:14-17`).
   Result `ts = E`: tool-execution end is emitted before the core creates the
   `toolResult` message (`.../pi-agent-core/dist/agent-loop.js:318-320,519-543`),
   so the end hook wins the event id and the later result `message_end` loses.
3. **SDK durable JSONL (c):** the assistant's inner message keeps `A`; the
   tool-result inner message keeps `R`. The result object is created only after
   `tool_execution_end` and receives a fresh `Date.now()`
   (`.../pi-agent-core/dist/agent-loop.js:519-543`). Outpost's current
   `message_end` handler returns no replacement (`pi-extension/src/index.ts:1402-1449`),
   so the SDK persists those original inner messages after extension dispatch
   (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:324-339`).
   The containing entries also have separate SDK ISO timestamps, but those do
   not feed transcript replay (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js:705-713`).
4. **Post-process-restart `session_history` (d):** request `ts = A`; result
   `ts = R`. `session_start` backfills the empty process-local log from
   `buildSessionContext().messages` (`pi-extension/src/session/sdk_session_projection.ts:239-304`),
   the mapper copies each inner `message.timestamp`
   (`pi-extension/src/session/transcript_projection.ts:145-149,201-217`), and
   `session_sync` projects that log into the reply
   (`pi-extension/src/session/sdk_session_projection.ts:628-641`;
   `pi-extension/src/index.ts:3075-3089`).

So current request disagreement is `live S != in-process history A == restart
history A`; current result disagreement is `live E == in-process history E !=
durable/restart R`. The root causes are, respectively, assistant `message_end`
running before execution start plus first-writer-wins dedupe, and the core
creating a fresh tool-result message timestamp after execution end.

The same shape exists for app-origin user confirmation. `_confirmUserDelivery`
records a fresh delivery `ts` but its initial `user_message` echo omits it
(`pi-extension/src/index.ts:2412-2431`); later user `message_end` broadcasts the
SDK timestamp (`pi-extension/src/session/sdk_session_projection.ts:484-520`),
while first-writer-wins leaves the earlier delivery timestamp in the in-process
log. The unmodified SDK user message is what survives restart. The SDK creates
that user timestamp before starting the run
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:853-856`),
while `ExtensionAPI.sendUserMessage` is a void dispatch wrapper
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts:895-905`),
so delivery confirmation and SDK-message time are independent reads.

### Replay/reconnect source

`session_history` is not read directly from the SDK on each request. It is built
from `TranscriptEventLog.forSession(...)`
(`pi-extension/src/session/sdk_session_projection.ts:628-641`) and sent by the
`session_sync` handler (`pi-extension/src/index.ts:3075-3089`). The SDK record is
consulted only at `session_start` to backfill that process-local log
(`pi-extension/src/session/sdk_session_projection.ts:231-235,239-304`).

The app does request this authoritative replay after reconnect: online status
binds the new channel (`app/lib/data/sync/sync_service.dart:708-716`), then
`_onlineActivated` debounces and calls `requestSync`
(`app/lib/data/sync/sync_service.dart:733-749`), which sends `SessionSync`
(`app/lib/data/sync/sync_service.dart:647-655`). A returned `SessionHistory` is
routed to `_replayHistory` (`app/lib/data/sync/sync_service.dart:1261-1264`),
which converts its events (`app/lib/data/sync/sync_service.dart:1723-1735`);
tool request/result projections consume the wire `event.ts` directly
(`app/lib/data/sync/session_history_replay.dart:53,90-113`).

### Concrete Unit A implementation plan

1. **`pi-extension/src/session/transcript_event_log.ts`** — add an event-id
   index (or equivalent) and `recordedTsFor(eventId)`. `append` installs the
   index only for the winning event; `clear`/`replace` clear/rebuild it. Test
   that a duplicate with a different `ts` cannot change the returned owner.
2. **Add `pi-extension/src/session/durable_transcript_event.ts`** — define one
   versioned custom-entry discriminator (for example
   `outpost-pi.transcript-event.v1`), an encoder for the canonical
   `user_confirmed`/`tool_requested`/`tool_finished` event, and a strict parser
   from unknown SDK custom-entry data. Persist the canonical event, not only a
   timestamp, so app client identity, enriched tool args, and normalized result
   text survive restart together with `ts`.
3. **`pi-extension/src/session/sdk_session_projection.ts`** — bind the SDK
   `appendEntry` capability alongside the existing message API and add one
   method that persists the versioned custom entry and appends that same event
   to `TranscriptEventLog`. Change restart backfill to read
   `ctx.sessionManager.buildContextEntries()` rather than only
   `buildSessionContext().messages`: first collect/validate durable Outpost
   entries, then walk the active compaction-aware entry order, suppress the
   corresponding SDK-derived user/tool event, and insert the durable canonical
   event. Continue mapping ordinary terminal user and assistant text messages
   from SDK messages. This is the merge that makes post-restart history prefer
   `S`/`E`/delivery time over `A`/`R`/SDK user time.
4. **`pi-extension/src/session/sdk_session_projection.ts` message recording** —
   make live assistant `message_end` record/broadcast text blocks but defer
   `toolCall` transcript events to `tool_execution_start`; actual SDK ordering
   means there is no recorded start timestamp to reuse at assistant
   `message_end`. For user and `toolResult`, resolve their deterministic event
   id, read `recordedTsFor`, use that `ts` for transcript/live output, and return
   it to the caller so the standard SDK message can be replaced before
   persistence.
5. **`pi-extension/src/index.ts`** — in `tool_execution_start`,
   `tool_execution_end`, and `_confirmUserDelivery`, compute one `Date.now()`,
   build one canonical event, pass it through the durable-record+log method,
   and broadcast that exact `event.ts`. Include it on the initial
   `user_message` confirmation. Make the `message_end` handler return
   `{ message: { ...event.message, timestamp: recordedTs } }` for matched user
   and tool-result messages; do not replace the assistant timestamp for tool
   requests, because their per-call canonical timestamps live in the custom
   entries.
6. **Tests** — add a producer-order regression that drives assistant
   `message_end -> tool_execution_start -> tool_execution_end -> toolResult
   message_end` and asserts live request/result `ts` equal in-process history.
   Add a real-file `SessionManager` integration test: persist one tool turn plus
   the versioned custom entries, reopen the session in a fresh
   `SdkSessionProjection`, issue `session_sync`, and assert request `S` and
   result `E` survive exactly (also cover two tool calls in one assistant
   message). Add the analogous app-user delivery test and assert the
   `message_end` replacement written by the SDK carries the recorded delivery
   timestamp.

After this plan, the standard assistant message still internally carries `A`
(the SDK has one timestamp per assistant message), but the same SDK JSONL also
carries each authoritative per-tool event with `S`; restart backfill explicitly
prefers that durable Outpost record. Therefore the app-visible invariant has no
residual: live broadcast, in-process `session_history`, and post-restart
`session_history` all use the hook-owned canonical timestamp.
