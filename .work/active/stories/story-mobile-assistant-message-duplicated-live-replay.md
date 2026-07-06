---
id: story-mobile-assistant-message-duplicated-live-replay
kind: story
stage: review
tags: [app, pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-06
confirmed_root_cause: 2026-07-03
implemented: 2026-07-06
---

# Mobile renders one assistant message N times (live × replay eventId mismatch)

## Observed

Operator scenario (phone, live relay): after a fresh pi restart and fresh
session, the operator opened chat and saw a single assistant turn rendered
3–4 times. Specifically the **first assistant paragraph** of the turn
("I'll get oriented on what was recently closed…") appeared **4 times**,
while the next three paragraphs in the same turn each appeared **once**. The
single user prompt appeared once. (Reported as "I got 3 copies of your turn
when I opened up chat.")

## Distinct from

- `idea-mobile-message-duplication-send-timeout` — that is an **outgoing
  user-message** duplication on back-navigation plus a false `send_timeout`,
  tied to optimistic-insert/echo and in-flight-send lifecycle. This is an
  **incoming assistant-message** duplication from a live/replay eventId
  collision, with a different trigger (chat-open / late-attach sync) and a
  different confirmed root cause. Both may ultimately trace to "app lacks
  canonical transcript-event identity," but the fix surfaces differ.
- `idea-mobile-chat-reorder-on-return` — row **ordering** on rehydrate, not
  duplication. Same sort surface (`seq` then `eventId`) but a distinct symptom.
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` (done, in review) —
  that fix made persisted history actually arrive on the wire
  (`backfillTranscriptFromSessionManager`). This bug was **masked** while
  history was blank: with nothing to replay, the live/replay collision never
  occurred. Once the backfill ships, the replay path is exercised and this
  dup becomes visible. Conceptual predecessor, not a hard dependency.

## Root cause (CONFIRMED 2026-07-03 via SDK persisted session + extension repro + app-side trace)

The app has **no canonical assistant-message identity that is stable across
the live-streaming path and the `session_history` replay path.** The same
logical assistant message, arriving once via live streaming and once via
replay, survives as **two distinct Hive rows** because the two paths stamp
**incompatible `eventId` schemes**, and the Hive store dedupes only by
`eventId` as the box key.

### Ground truth (rules out the SDK/extension side)

The SDK persisted the duplicated message **exactly once**. From the live
session jsonl
(`~/.pi/agent/sessions/--home-agent-projects-remote_pi--/2026-07-03T23-10-56-525Z_*.jsonl`):

- The assistant message "I'll get oriented…" (ts `1783120377469`) is stored
  as a single `type:"message", role:"assistant"` entry.
- A python pass over the entries found exactly **1** assistant message
  containing that text. (A naive `grep -c` returns 10 because the text also
  appears in tool results, compaction records, and summaries — but the
  persisted assistant message itself is singular.)
- The turn's other three assistant paragraphs are likewise stored once each.

So the duplication is **entirely app-side**: the phone rendered one stored
message four times.

### Extension-side dedup is correct (rules out the backfill)

A focused repro test was written
(`pi-extension/src/session/repro_dup.test.ts`, since removed): live
`appendLegacySdkMessageToTranscript` for an assistant message, then a
`session_start` backfill whose `buildSessionContext()` returns the same
persisted assistant message. `buildSessionHistoryMessage` returned **1**
`agent_message`, not 2 — the backfill's deterministic
`deterministicTranscriptEventId(sessionId, "assistant_committed", messageId)`
collapses against the live path's identical eventId (both key on the same
`ts`/`messageId` because `appendLegacySdkMessageToTranscript` and
`mapLegacyAgentMessagesToTranscriptEvents` share the eventId scheme). The
`/reload`-idempotency and live-user-dedupe regression tests in
`sdk_session_projection.test.ts` already pin this. **The backfill is not the
culprit; story-mobile-chat-blank-on-pair-after-pre-pair-work is sound.**

### The app-side eventId mismatch

Two code paths create `AssistantMessageCommitted` transcript events, with
**incompatible eventId schemes**:

| Path | File:line | eventId | messageId | ts |
|---|---|---|---|---|
| **Live** `AgentDone` (buffered commit) | `app/lib/data/sync/sync_service.dart:566` | `server:assistant_committed:$inReplyTo:${uuid7()}` | `agent_${uuid7()}` | `DateTime.now()` |
| **Live** `AgentMessage` (non-streaming) | `app/lib/data/sync/sync_service.dart:590` | `server:assistant_message:$inReplyTo:${uuid7()}` | `agent_$inReplyTo` | `DateTime.now()` |
| **Live** `ToolRequest` pre-tool flush | `app/lib/data/sync/sync_service.dart:654` | `server:assistant_committed:$toolCallId:${uuid7()}` | `agent_${uuid7()}` | `DateTime.now()` |
| **Replay** `AgentMessageEvt` | `app/lib/data/sync/session_history_replay.dart:62` | `server:$sessionId:agent_message:$inReplyTo:$ts` | `server-message:$sessionId:agent_message:$inReplyTo:$ts` | `event.ts` (SDK) |

The live schemes use a **random `uuid7()`**; the replay scheme is
**deterministic** over `(sessionId, inReplyTo, ts)`. They can never match.
The Hive store dedupes by `eventId` as the box key
(`app/lib/data/local/transcript_event_store_hive.dart:28`:
`if (box.containsKey(event.eventId)) continue;`), and the projection dedupes
assistant rows by `messageId`
(`app/lib/domain/transcript/transcript_projection.dart:191-196`), so a live
commit and its replay twin both survive as distinct rows → duplicate bubble.

### Why ×4 and why only the FIRST message

A pure live+replay overlap explains ×2, not ×4. The extra multiplier is the
**`ToolRequest` pre-tool flush** at `sync_service.dart:648-660`: when a
`ToolRequest` arrives mid-stream, the handler commits `_streaming.buffer` as
an `AssistantMessageCommitted` with a fresh random eventId — and it is
**fire-and-forget** (`// ignore: discarded_futures`), with the in-memory
`_streaming` buffer only cleared later when the async projection write
completes (`AssistantMessageCommitted` sets `streaming = null` at
`transcript_projection.dart:195`, but that runs after the enqueued
`_appendTranscriptEvents` async write resolves).

So if multiple `ToolRequest`s arrive before the earlier async projection
clears `_streaming`, **each re-flushes the same buffer** with a new random
eventId. In the operator's first turn there were several tool batches → the
first paragraph got flushed multiple times → then the chat-open/late-attach
`session_history` replay added one more → ×4. The later paragraphs in the
turn did not overlap a chat-open/late-attach replay boundary the same way,
so they rendered once.

```text
turn: user → assistant#1 (streaming) → tool#1 → assistant#2 → tool#2 → …
  AgentChunk accumulates into _streaming.buffer
  ToolRequest#1 → flush buffer as AssistantMessageCommitted (random id A)   [fire-and-forget, buffer NOT cleared synchronously]
  ToolRequest#2 → flush SAME buffer as AssistantMessageCommitted (random id B) [buffer still not cleared]
  … async projection finally clears _streaming …
  chat-open / late-attach session_sync → replay AssistantMessageCommitted (deterministic id C)
  Hive box keys A, B, C all distinct → 3+ rows, same text → ×N bubbles
```

## Fix shape

**The deterministic server/replay identity must win; live assistant commits
must derive the same stable identity replay uses.** The live random-uuid
eventIds/messageIds must be replaced with stable, server-derived ids.

### Decisions to pin at implement time

1. **Identity source.** The live frames currently lack the stable facts
   replay derives its id from (`sessionId`, SDK assistant `ts`, a stable
   message id). Two options:
   - (a) **Extension emits stable identity on live frames** (paired wire
     change): the extension's `agent_message`/`agent_chunk`/`agent_done`
     broadcasts carry the SDK assistant `timestamp` (and ideally a stable
     `message_id`) so the app can compute
     `server:$sessionId:agent_message:$inReplyTo:$ts` deterministically on
     both paths. This is the single-source-of-truth option — the extension
     owns the canonical id; the app derives it.
   - (b) **App-side content+ts dedup** (no wire change): the app dedupes
     assistant commits by a content signature + `inReplyTo` + nearest `ts`,
     collapsing live vs replay twins. Weaker — content can legitimately
     repeat across turns, and it papers over the missing server identity
     rather than fixing it. Prefer (a) unless the wire change is blocked.
   - Recommendation: **(a)**. It also retires the random-uuid live ids that
     make the `ToolRequest` re-flush amplification possible (a re-flush of
     the same `(inReplyTo, ts)` would then collapse by eventId).
2. **`ToolRequest` flush amplification.** Independent of the identity fix,
   the fire-and-forget `ToolRequest` flush must not re-commit an
   already-flushed buffer. Either clear the local buffer reference at flush
   time (so a second `ToolRequest` before the async projection sees an empty
   buffer) or guard against double-flush by tracking the flushed buffer's
   content signature. This is a behavior-preserving lifecycle fix.

   **DONE 2026-07-06.** Both flush sites (`AgentDone` at `sync_service.dart:594`
   and `ToolRequest` at `:682`) now clear `_streaming` synchronously via
   `_emitStreaming(null)` at flush time (capturing the buffer + `inReplyTo`
   into locals first). The projection's later `streaming = null` (from the
   committed event) becomes a confirming no-op rather than the only clearing
   path. Regression test `ToolRequest flush is not re-amplified` pins it and
   was verified to FAIL without the fix (`Actual: 2` — the buffered text
   committed twice) and pass with it. `flutter test` 665/665 green. The
   remaining identity-source decision (1) is still open and still blocks the
   live×replay eventId-mismatch portion of this story (both assistant AND
   user messages).
3. **Migration of existing Hive rows.** Existing phones may already have
   duplicate rows persisted with random eventIds. A one-time dedup pass on
   `activate()`/`_loadIndex` (collapse assistant rows that share
   `(inReplyTo, text, ts)` keeping the deterministic id) may be needed, or
   accept that the dup clears on the next full replay after the fix ships.
   Decide based on whether stale dup rows cause ongoing visible duplication.

## Regression tests

1. **Extension** (`pi-extension/src/session/sdk_session_projection.test.ts`):
   pin that the live `agent_message`/`agent_done` broadcast carries the stable
   identity the replay path uses (once (a) is chosen) — a test that the wire
   `agent_message` event's `in_reply_to`/`ts`/`message_id` match what
   `session_history` emits for the same persisted message.
2. **App** (`app/test/...sync_service...` or projection test): a live
   `AssistantMessageCommitted` followed by a replay `AssistantMessageCommitted`
   for the same `(sessionId, inReplyTo, ts)` produces **one** row in the Hive
   store, not two.
3. **App**: a `ToolRequest` flush followed by a second `ToolRequest` before
   the async projection resolves commits the buffered text **once**, not
   twice (the fire-and-forget re-flush amplification fix).
4. **App**: end-to-end — live streaming a turn with multiple tool batches,
   then a `session_history` replay of the same turn, renders each assistant
   paragraph exactly once.

## Verification matrix (after fix)

- Fresh pair, send one message, agent replies with multiple text+tool
  batches → each assistant paragraph renders once on first view.
- Open chat after the turn completes (late-attach / chat-open sync) → no
  duplicate of the first (or any) paragraph.
- `/reload` mid-session, then open chat → no duplicate (the backfill + replay
  both produce deterministic ids that collapse).
- A turn with 3+ tool batches → first paragraph renders once (ToolRequest
  re-flush fix).
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` on
  `pi-extension/`; `flutter analyze && flutter test` on `app/`.

## References

- `app/lib/data/sync/sync_service.dart:549-595` — live `AgentChunk`/`AgentDone`/`AgentMessage` append paths (random-uuid eventIds).
- `app/lib/data/sync/sync_service.dart:648-660` — `ToolRequest` pre-tool flush (fire-and-forget, buffer not cleared synchronously).
- `app/lib/data/sync/session_history_replay.dart:52-77,127,134` — replay deterministic eventId/messageId (`serverReplayEventId` / `serverReplayMessageId`).
- `app/lib/data/local/transcript_event_store_hive.dart:28` — Hive dedup by `eventId` box key.
- `app/lib/domain/transcript/transcript_projection.dart:191-196` — projection dedup of assistant rows by `messageId`.
- `app/lib/domain/session_state.dart:163-176` — `StreamingMessage.buffer` (the re-flushed buffer).
- `pi-extension/src/index.ts:1269-1273` — `message_end` feeds the transcript log (extension side is correct; identity is stable here).
- `pi-extension/src/session/sdk_session_projection.ts:378-440` — `appendLegacySdkMessageToTranscript` (extension eventId scheme, shared with the backfill mapper → extension dedup works).
- `pi-extension/src/session/transcript_projection.ts:136-160` — `mapLegacyAgentMessagesToTranscriptEvents` (deterministic eventId by `ts`).
- `.agents/skills/flutter-mobile/SKILL.md` — sync/transcript identity.
- `.agents/rules/code-design.md` — Single Source of Truth (one assistant-message identity, derived everywhere).
- Sibling (predecessor that unmasked this): `story-mobile-chat-blank-on-pair-after-pre-pair-work.md`.
- Related-but-distinct backlog: `idea-mobile-message-duplication-send-timeout.md` (outgoing-message dup, different root cause).

## Scope extension (2026-07-06 instrumented repro — extends to USER messages)

A live repro with the cross-side ring log
(`story-verify-mobile-dup-and-reorder-reconnect-repro`, done) confirmed the
SAME event-store identity class applies to **user messages**, not just
assistant messages:

- **Live `UserInput` echo path** (`sync_service.dart:647-652`): appends
  `UserMessageConfirmed` with `eventId: 'server:user_confirmed:$id'`
  (deterministic only over the echoed user id — no session id, no server ts).
- **Replay `UserInputEvt` path** (`session_history_replay.dart:51-55, 122-127`):
  `eventId: serverReplayEventId(sessionId, 'user_input', id, ts)` =
  `server:$sessionId:user_input:$id:$ts`.
- **They don't match.** For the same foreign user message id
  `local_d974d2d7-...`, live produces `server:user_confirmed:local_d974...`
  while replay produces `server:<sessionId>:user_input:local_d974...:<ts>` —
  the same incompatible-scheme class as the assistant-message root cause,
  and Hive dedupes by `eventId` as the box key
  (`transcript_event_store_hive.dart:28-30`).

### Nuance (the user-message projection guard)
Unlike assistant rows, user-message projection dedupes authoritative rows by
`ChatMessage.id` (`transcript_projection.dart:126-127, 161-168`), and
`UserMessageConfirmed` projects to `UserMsg(id: event.clientMessageId, ...)`.
So a live+replay pair with the EXACT same `clientMessageId` (`local_...`)
would create two event-store entries but SHOULD collapse to one visible bubble
in projection. The ring log does NOT prove the specific `local_d974...` echo
also replayed (none of the 25 `replayDedup dropped:false` tails collide with
it). So the user-message visible duplicate may require a DIFFERENT
`clientMessageId` for the same logical text (a distinct dedup surface), OR
the event-store mismatch is the class and the projection guard is the only
thing preventing it from being worse.

### Fix scope (extended)
The deterministic-identity fix (decision (a): extension emits stable identity
on live frames) should cover **both** assistant AND user messages — the live
`UserInput` confirmation must derive the same canonical event id as
`UserInputEvt` replay (`sync_service.dart:648-652` ←
`session_history_replay.dart:51-55, 122-127`). If the operator-visible
user-message duplicate persists after the deterministic identity fix,
investigate a distinct user dedup surface where the same logical user text is
stored under two different `clientMessageId`s.

### Relationship to the reorder
The reorder observed in the same repro is a DISTINCT bug (transport
active-room re-establishment on reconnect) — scoped as
`story-fix-transport-active-room-reestablishment-on-reconnect`. The two bugs
are independent: the identity mismatch causes duplicates; the active-room
transient causes drops + reordering.

## Decision 1 design — identity source (a) [DESIGNED 2026-07-06, NOT YET IMPLEMENTED]

Operator confirmed: route the identity fix through **(a) extension emits
stable identity on live frames** (single source of truth). Below is the
verified design before implementing.

### Wire-surface cost (LOWER than originally framed)

The relay forwards app↔Pi traffic as `Outer(OuterEnvelope { peer, room, ct })`
— the `ct` blob is opaque base64 the relay never decodes
(`relay/src/protocol/frame.rs:9-19`, `relay/src/protocol/frame.rs:107-131`,
relay test `no_type_outer_envelope_decodes`). So adding a field to the inner
`agent_chunk`/`agent_done`/`agent_message` messages requires **NO relay
change and NO relay-version pairing**. The change is schema + codegen +
extension (emit) + app (consume) only. The original story's
"paired wire change" framing overstated the surface: the relay is
field-agnostic for app↔Pi traffic.

### The granularity mismatch (uncovered during design — DEEPER than the story framed)

The live and replay paths produce **different numbers** of committed
assistant events for a multi-block turn, not just incompatible eventIds:

- **Replay**: the extension's `appendLegacySdkMessageToTranscript`
  (`sdk_session_projection.ts:378-404`) creates ONE `assistant_committed`
  transcript event **per text content block** of the SDK assistant message
  (`messageId = "sync_${ts}:assistant:${blockIndex}"`), and
  `projectSessionHistory` emits one `agent_message` event per block
  (`transcript_projection.ts:77-93`). The app maps each to a separate
  `AssistantMessageCommitted` (`session_history_replay.dart:61-77`).
- **Live**: the app accumulates ALL streamed text into ONE `_streaming.buffer`
  and commits ONE `AssistantMessageCommitted` at `AgentDone` (and flushes one
  per `ToolRequest` boundary). So a turn with interleaved text+tool batches
  produces N live committed events but M replay committed events (N≠M).

So identity-source (a) is NOT just "add `ts` to `agent_done`" — it must
reconcile **granularity** too, or live and replay will still produce
different event counts even if the overlapping ids match.

### The chosen convergence: make `message_end` the single source of live assistant identity

The extension's `message_end` hook already produces the canonical
`assistant_committed` transcript events with deterministic ids (the same
source replay derives from). The clean design makes `message_end` ALSO drive
a live broadcast carrying that stable identity, so the app's live commit
path converges with replay by construction.

**Sketch (assistant messages):**
1. `message_end` (assistant) already calls `appendLegacySdkMessageToTranscript`
   which produces `assistant_committed` transcript events (one per text block,
   `messageId = "sync_${ts}:assistant:${blockIndex}"`,
   `eventId = deterministicTranscriptEventId(sessionId, "assistant_committed", messageId)`).
2. Have it ALSO broadcast a live `agent_message`-style frame per block,
   carrying the stable `(ts, message_id, text, in_reply_to, usage)` — the
   same facts replay derives from. (The existing live `agent_chunk`/`agent_done`
   streaming frames stay for the streaming bubble, but the COMMITTED row
   identity comes from this `message_end`-driven broadcast, not from the
   streamed buffer at `agent_done`.)
3. App: commit `AssistantMessageCommitted` from this `message_end`-driven
   frame, deriving `eventId`/`messageId` from the carried `(sessionId, ts,
   message_id)` to match replay's scheme exactly. The streamed
   `_streaming.buffer` still drives the streaming UI; the commit identity
   no longer uses `uuid7()`.
4. Replay (`AgentMessageEvt`) keeps its existing deterministic scheme — which
   now MATCHES the live commit because both derive from the same
   `(sessionId, ts, message_id)`.

**Sub-decisions to pin at implement time:**
- **Block boundary semantics**: replay produces one committed event per text
  content block. The live `message_end`-driven broadcast should mirror that
  (one broadcast per block) so live and replay produce the SAME number of
  events with matching ids. The app's streamed-buffer accumulation becomes a
  UI-only concern (the streaming bubble), not a commit-granularity concern.
- **`ToolRequest` flush**: with `message_end` driving commits, the
  pre-tool-flush of `_streaming.buffer` at `ToolRequest` becomes redundant
  for commit identity (the committed row comes from `message_end`, not the
  buffer). The synchronous-clear fix from decision 2 stays (it prevents
  re-flush amplification of the streaming buffer) but the flush itself may
  become a no-op or be removed if `message_end` subsumes it. Decide at
  implement time.
- **User messages**: the same class — `user_input` confirmation must derive
  the same eventId as `UserInputEvt` replay. The extension's
  `appendLegacySdkMessageToTranscript` user branch already records
  `clientMessageId` + the matched delivered-user eventId; a live
  `user_input` echo broadcast carrying the canonical `(sessionId, ts, id)`
  lets the app's `UserInput` handler derive
  `server:$sessionId:user_input:$id:$ts` to match replay.
- **Migration**: existing Hive rows with random eventIds will duplicate
  against the new deterministic ids until the next full replay. A one-time
  dedup pass on `activate()` (collapse assistant rows sharing
  `(replyTo, text, ts)` keeping the deterministic id) may be needed; decide
  based on whether stale dup rows cause ongoing visible duplication after
  the fix ships. Acceptable to defer if the next replay clears them.
- **Backward compatibility**: adding `ts`/`message_id` as OPTIONAL fields to
  `agent_chunk`/`agent_done`/`agent_message` (schema: `compat` profile) means
  old apps that ignore them keep working (they'd still produce random ids —
  the dup persists for them, but no regression). New apps converge.

### Implementation surface (the change, concretely)

1. **Schema** (`protocol/schema/app-pi-server.schema.json`): add optional
   `ts` (integer) and `message_id` (string) to `agentChunk`/`agentDone`/
   `agentMessage`. Validate with `pnpm --dir protocol check`.
2. **Codegen**: regenerate `pi-extension/src/protocol/generated/protocol.generated.ts`
   (`pnpm generate:protocol`) and `app/lib/protocol/generated/protocol.g.dart`
   (from the Dart IR fixture — may need updating if the IR is hand-maintained;
   verify the IR-generation path).
3. **Extension** (`pi-extension/src/index.ts`): capture the SDK assistant
   `timestamp` + block index at `message_end`, attach to the live
   `agent_message`/`agent_done` broadcasts. Test in
   `sdk_session_projection.test.ts` that the live broadcast's `ts`/`message_id`
   match what `session_history` emits for the same persisted message.
4. **App** (`app/lib/data/sync/sync_service.dart`): the live `AgentDone`/
   `AgentMessage`/`UserInput` commit paths derive `eventId`/`messageId` from
   the carried stable fields instead of `uuid7()`. The `ToolRequest` flush
   may be simplified (see sub-decision above).
5. **Tests**: (a) extension pin that live broadcast identity == replay
   identity; (b) app: a live commit + replay of the same turn → one row, not
   two; (c) app: a multi-block turn → live and replay produce the same
   number of committed rows with matching ids.

### LANDED 2026-07-06 (assistant messages; user messages deferred)

Implemented the assistant-message identity convergence. The user-message
extension (same class) is deferred to a follow-up — the projection guard
(`ChatMessage.id` dedup) already mitigates the visible user-message dup, and
the ring log did not prove a live×replay collision for the specific
`local_d974...` echo.

**Schema + codegen (additive, backward-compatible):**
- `protocol/schema/app-pi-server.schema.json` — added optional `ts` to
  `agentChunk`/`agentDone`/`agentMessage` and `message_id` to `agentMessage`.
  Old apps/relays ignore the fields (relay forwards `ct` opaquely — no relay
  change, no version pairing).
- Regenerated `pi-extension/src/protocol/generated/protocol.generated.ts`
  and `app/lib/protocol/generated/protocol.g.dart` (the Dart IR fixture
  `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` was updated
  by hand — it is a committed intermediate, not schema-generated).

**Extension (`pi-extension/src/session/sdk_session_projection.ts`):**
- `appendLegacySdkMessageToTranscript` (the `message_end` path) now ALSO
  broadcasts a live `agent_message` per assistant text block, carrying the
  stable `(ts, message_id, text, in_reply_to)` — the same facts replay
  derives from. This makes `message_end` the single source of live assistant
  identity.

**App (`app/lib/data/sync/sync_service.dart`):**
- `AgentMessage` handler: when `ts` is present, derives
  `eventId = serverReplayEventId(sessionId, 'agent_message', inReplyTo, ts)`
  and `messageId = serverReplayMessageId(...)` — matching the replay path
  exactly. Falls back to the old random-id scheme when `ts` is absent
  (legacy extension).
- `AgentDone` handler: skips the buffer-commit when a deterministic
  `agent_message` already committed the turn's text (tracked via
  `_agentMessageCommittedThisTurn`), preventing the live×buffer duplicate.
  Falls back to the buffer-commit when no `agent_message(ts)` arrived.
  Flag reset on new user turn, cancel/abort, and at `AgentDone` itself.

**Tests:**
- Extension (`sdk_session_projection.test.ts`): pins that
  `appendLegacySdkMessageToTranscript` broadcasts a live `agent_message`
  with `ts`/`message_id` matching what `buildSessionHistoryMessage` emits
  for the same persisted message.
- App (`sync_service_test.dart`): `live agent_message(ts) + replay
  AgentMessageEvt collapse to one row` — a live commit followed by a replay
  of the same `(inReplyTo, ts)` produces ONE assistant row, not two.
  **Verified to FAIL without the fix** (`Actual: 2`) and pass with it.
- Test-harness fix: `_withDefaultSession` in the sync test fake now
  preserves `ts`/`messageId` on `AgentMessage` (and `ts` on
  `AgentChunk`/`AgentDone`) — the regeneration had made it drop the new
  fields.

**Verification:** `flutter analyze` clean; `flutter test` 666/666 green;
`corepack pnpm typecheck` clean; `corepack pnpm test` 753/753 (3 skipped)
green; `protocol check` validates 5 fixture families.

### Deferred / follow-up
- **User-message identity** (same class): the live `UserInput` echo must
  derive `server:$sessionId:user_input:$id:$ts` to match `UserInputEvt`
  replay. **DONE 2026-07-06** — see "User-message identity (landed)" below.
- **Multi-block granularity**: a turn with multiple assistant text blocks
  now produces one live `agent_message` broadcast per block (matching
  replay's one `AgentMessageEvt` per block). The streamed `_streaming.buffer`
  still drives the streaming UI; the commit granularity is reconciled via
  the per-block broadcasts. Verify with a multi-block e2e test.
- **Migration of existing Hive rows**: existing phones may have duplicate
  rows with random eventIds; they clear on the next full replay after the
  fix ships. A one-time dedup pass was not added — defer unless stale dup
  rows cause ongoing visible duplication.
- **`ToolRequest` flush simplification**: with `message_end` driving
  commits, the pre-tool-flush of `_streaming.buffer` at `ToolRequest` may
  become redundant for commit identity (decision 2's synchronous-clear fix
  stays regardless). Decide at follow-up.

### User-message identity (landed 2026-07-06)

Same class as the assistant fix, now extended to user messages. The visible
user-message dup was already mitigated by the projection's `ChatMessage.id`
dedup (`transcript_projection.dart:126-127,161-168`), but the event-store had
TWO rows per message (live echo + replay with incompatible eventIds). This
lands the convergence so the event-store collapses to one row too.

**Schema + codegen:**
- `protocol/schema/app-pi-server.schema.json` — added optional `ts` to
  `userInput` and `userMessage`. Also added `ts` to the ClientMessage
  `userMessage` in `app-pi-client.schema.json` to resolve a codegen
  interface-name collision (Client + Server `user_message` share the
  `UserMessage` interface; without `ts` on both, the codegen emitted the
  Client's interface and silently skipped the Server's, dropping `ts`).
- Regenerated TS + Dart protocol types.

**Extension (`sdk_session_projection.ts`):**
- `appendLegacySdkMessageToTranscript` (user branch, `message_end`-driven)
  now broadcasts a live `user_input` echo carrying the stable SDK `ts`,
  mirroring the assistant `agent_message` broadcast.

**App (`sync_service.dart`):**
- `UserInput` handler: when `ts` is present, derives
  `eventId = serverReplayEventId(sessionId, 'user_input', id, ts)` to match
  the replay `UserInputEvt` path. Falls back to `'server:user_confirmed:$id'`
  when `ts` is absent (legacy extension / the early delivery-time echo).

**Tests:**
- App: `live user_input(ts) + replay UserInputEvt collapse to one row` —
  asserts the EVENT-STORE row count (not the projection, which dedupes by
  id regardless). Verified to FAIL without the fix (`Actual: 2` event-store
  rows) and pass with it (`1`).
- Extension: pins that `appendLegacySdkMessageToTranscript` (user branch)
  broadcasts a live `user_input` with `ts` matching `buildSessionHistoryMessage`'s
  replay `UserInputEvt`.
- Test-harness: `_withDefaultSession` now preserves `ts` on `UserInput`.

**Verification:** `flutter analyze` clean; `flutter test` 668/668;
`pnpm typecheck` clean; `pnpm test` 754/754 (3 skipped); `protocol check`.

**Note on the early delivery-time echo:** the extension's `user_message`
echo (fired at `_deliverUserMessage` time, before `message_end`) does NOT
carry `ts` and still produces the old `'server:user_confirmed:$id'` eventId
on the app side. The `message_end`-driven `user_input` echo (with `ts`)
fires later and produces the deterministic eventId; Hive dedupes the earlier
row by `clientMessageId` in projection. The event-store retains the early
row until the next replay; acceptable (the projection guard prevents a
visible dup). A future cleanup could suppress the early echo's commit when
`ts` is expected, mirroring the `AgentDone` skip — deferred.

### Deep review (2026-07-06) — REJECT → fixed (blocking multi-block collision)

A fresh-context deep review (gpt-5.5, xhigh) caught a BLOCKING message-loss
bug in the initial landing: for a multi-text-block assistant message, the
extension correctly emitted one live `agent_message` per block with distinct
`message_id = sync_${ts}:assistant:${blockIndex}`, but the app's live handler
derived `eventId = server:$sessionId:agent_message:$inReplyTo:$ts` — which
does NOT include the block index. So all blocks in the same SDK message
(same `inReplyTo`, same `ts`) got the SAME eventId, Hive deduped all but the
first, and `_agentMessageCommittedThisTurn = true` made `AgentDone` skip the
buffer fallback → remaining blocks' text was LOST.

**Fix (landed same session):**
- Schema: added optional `message_id` to `historyAgentMessage` (replay event)
  too, so both live and replay carry the block-unique id.
- Extension (`transcript_projection.ts`): `projectSessionHistory` now emits
  `message_id` on the replay `agent_message` event (mirroring the live
  broadcast).
- App (`sync_service.dart` + `session_history_replay.dart`): both the live
  `AgentMessage` handler and the replay `AgentMessageEvt` mapping now use
  `messageId ?? inReplyTo` as the stable key — so multi-block messages get
  distinct eventIds per block, while legacy frames without `message_id`
  fall back to the old `inReplyTo`-keyed scheme.
- Regression test `multi-block assistant message: live agent_message per
  block does not collide` — verified to FAIL without the `message_id` stable
  key (blocks collide → 1 row instead of 2) and pass with it.
- Extension test strengthened to assert the replay event carries the same
  `message_id` as the live broadcast.

**Should-fix findings also addressed:**
- `_agentMessageCommittedThisTurn` is now reset in `_resetTurnState` (covers
  session switch / reconnect / dispose), not just on new user turn / cancel /
  `AgentDone`.

**Should-fix findings deferred (low risk, documented):**
- Ordering race: if `AgentDone` is processed before the deterministic
  `AgentMessage(ts)`, the app commits the buffer with the legacy random id,
  then the deterministic `agent_message` adds a second row (the original
  dup). The Pi SDK guarantees `message_end` before `agent_end`, so this is
  structurally impossible in production; the app test suite does not pin
  the ordering. Acceptable until an e2e test covers it.

### Out of scope for this design pass
- The cockpit (Flutter desktop) — it consumes the same protocol but its
  transcript path is separate; file a follow-up if it duplicates.
- The `ToolRequest` re-flush amplification fix is DONE (decision 2, landed
  2026-07-06) and stays regardless of the granularity reconciliation above.
