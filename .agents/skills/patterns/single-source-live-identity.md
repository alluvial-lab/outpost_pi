# Pattern: Single-Source Live Identity (Remove the Legacy Broadcast)

## Rationale

Remote Pi's mobile transcript dedupes Hive rows by `eventId` (the box key),
and the projection dedupes rendered bubbles by `messageId`. For a live
streaming frame and a `session_history` replay of the same logical message
to collapse to one row, **both paths must stamp the same deterministic
identity.** The single source of that identity is the extension's
`message_end` hook: it has the SDK assistant `timestamp` and the block
index, and it already produces the canonical `assistant_committed` /
`user_confirmed` transcript events that `session_history` replays derive
from.

The recurring failure: **adding the `message_end`-driven deterministic
broadcast without removing the pre-existing live broadcast that used a
random id.** Both reach the phone; the app commits both under different
`eventId`s; Hive keeps both rows; the projection renders two bubbles. This
has bitten assistant messages, user messages, and nearly the early
delivery-time echo. It is the dominant cause of mobile "double messages."

## The rule

> When you introduce a deterministic-identity live broadcast (from
> `message_end` or any single-source hook), **audit for and remove every
> other broadcast of the same message type** that stamps a different id
> scheme. `message_end` owns live identity; anything else that emits
> `agent_message` / `user_input` with a non-matching id is a dupe source.

Concretely: the live broadcast and the replay must derive `eventId` /
`messageId` from the **same** `(sessionId, stableKey, ts)` tuple. The
`stableKey` is `messageId` when present (multi-block assistant messages
need the block index in the key), else `inReplyTo` / `clientMessageId`.

## When to apply

- Adding or changing any live broadcast of `agent_message`, `user_input`,
  `agent_done`, or a new message type that also replays via
  `session_history`.
- Reviewing a "double messages on mobile" bug — check whether two
  broadcasts fire for the same logical message with different id schemes.
- Adding a new SDK hook that mirrors content an existing hook already
  broadcasts.

## When not to apply

- A live broadcast that fires **before** the deterministic source and uses
  a *different, deliberately temporary* purpose (e.g. an optimistic
  pending row keyed by the app's own `cli_` id, confirmed later by the
  echo). Those are fine as long as the confirm/echo collapses the
  optimistic row by the same id — see the `UserInput` echo path.
- Broadcasts of genuinely different message types (e.g. `user_message`
  ack vs `user_input` echo) that serve different roles.

## Examples of the failure (all real, all from the mobile dup cluster)

### Assistant messages — `ToolRequest` flush (fixed 2026-07-08)

The SDK fires `message_end` (→ deterministic `agent_message(ts,
message_id)` broadcast) **before** `tool_execution_start` (→ app receives
`ToolRequest`). The `ToolRequest` handler flushed the streaming buffer
with a random `uuid7()` eventId, duplicating the deterministic commit.

**File:** `app/lib/data/sync/sync_service.dart` (`ToolRequest` case)

```dart
// WRONG — re-commits the same text under a random id even though
// message_end's agent_message(ts) already committed it deterministically.
_appendTranscriptEvent(
  AssistantMessageCommitted(
    eventId: 'server:assistant_committed:$toolCallId:${uuid7()}',
    messageId: 'agent_${uuid7()}',
    ...
  ),
);

// RIGHT — guard with the same flag AgentDone uses; clear the buffer
// (streaming UI) but skip the random-id commit when deterministic
// identity already landed.
final committedViaAgentMessage = _agentMessageCommittedThisTurn;
_emitStreaming(null);
if (!committedViaAgentMessage) {
  _appendTranscriptEvent(... random-id fallback ...);
}
```

### User messages — `pi.on("input")` broadcast (fixed 2026-07-08)

A message typed in the Pi TUI fired **two** `user_input` broadcasts:
`pi.on("input")` (id=`turnId`=`local_<uuid>`, no `ts`) and `message_end`
(id=`sync_<ts>`, with `ts`). Different ids → different eventIds → two
rows.

**File:** `pi-extension/src/index.ts` (`pi.on("input")` handler)

```ts
// WRONG — the input handler mirrors workstation-typed input live, but
// message_end (milliseconds later, before agent streaming) also
// broadcasts user_input with a different id.
_owners.broadcast({ type: "user_input", id: turnId, text: event.text });

// RIGHT — remove the broadcast; message_end owns it. The input handler
// still seeds the turn projection (so agent_chunk.in_reply_to resolves)
// but does NOT broadcast user_input.
_applyTurnAndPublish({ type: "local_input", turnId, replyTo: turnId, source: "local" });
// no broadcast here — message_end's appendLegacySdkMessageToTranscript does it
```

### The early delivery-time echo (deliberately tolerated)

The `_deliverUserMessage` path (phone-originated) broadcasts a `user_message`
ack at delivery time, **before** `message_end`. It does not carry `ts`, so
it commits under `'server:user_confirmed:$id'` while the `message_end`
echo commits under the deterministic id. This is tolerated because the
projection dedupes user rows by `ChatMessage.id` (the `clientMessageId`),
so the two event-store rows collapse to one visible bubble. A future
cleanup could suppress the early echo's commit when `ts` is expected,
mirroring the `AgentDone` skip.

## The audit checklist (run this when touching transcript identity)

1. Enumerate **every** broadcast site for the message type
   (`agent_message` / `user_input` / `agent_done` / ...).
2. For each, what `id` / `ts` / `message_id` does it stamp?
3. Does it match the `message_end`-driven deterministic scheme exactly?
4. If a broadcast fires **before** `message_end` and uses a different id
   scheme, either remove it or guard its commit (like `AgentDone` /
   `ToolRequest` do with `_agentMessageCommittedThisTurn`).
5. Does the replay path (`session_history_replay.dart` /
   `transcript_projection.ts`) derive the same `(sessionId, stableKey, ts)`
   tuple? A mismatch here is the same class.

## Related

- `snapshot-replay-event-mappers.md` — the replay side of this: convert
  snapshots to canonical events with deterministic ids. This pattern is
  the live side: make sure the live broadcast converges with the replay.
- `.agents/rules/code-design.md` § Single Source of Truth — the
  principle this pattern operationalizes for transcript identity.
- `story-mobile-assistant-message-duplicated-live-replay` — the
  investigation that established `message_end` as the single source and
  the three dupe paths this pattern generalizes.

## Index entry

- **single-source-live-identity**: When adding a deterministic-identity
  live broadcast (from `message_end`), remove or guard every other
  broadcast of the same message type that stamps a different id scheme —
  otherwise both survive as duplicate Hive rows.
