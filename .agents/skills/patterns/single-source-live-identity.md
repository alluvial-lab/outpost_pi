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

A message typed in the Pi TUI is owned by the durable SDK-message recorder at
`message_end`; the earlier `pi.on("input")` hook only seeds turn state. The
recorder persists the canonical `user_confirmed` fact before broadcasting its
`user_input` projection, so live and replay paths share the same identity.

**File:** `pi-extension/src/index.ts:1500-1511` (`message_end` handler)

```ts
if (!suppressForSubagent && (m.role === "user" || m.role === "assistant")) {
  _recordSdkMessageTranscriptEvents(m as unknown as SdkTranscriptMessage);
}
```

**File:** `pi-extension/src/index.ts:1280-1300` (`pi.on("input")` handler)

```ts
_applyTurnAndPublish({ type: "local_input", turnId, replyTo: turnId, source: "local" });
// no user_input broadcast here; message_end owns durable identity
```

The app's fallback rule is era-aware: legacy extensions may commit a random-id
fallback when no deterministic `agent_message(ts)` capability is known. Once a
session has latched that capability, a missing live frame suppresses the random
fallback so durable replay remains the sole identity source.

**File:** `app/lib/data/sync/sync_service.dart:1243-1253`

```dart
final deterministicExpectedButDropped =
    !committedViaAgentMessage &&
    _extensionSendsDeterministicAgentMessage;
if (buffered.isNotEmpty &&
    !committedViaAgentMessage &&
    !deterministicExpectedButDropped) {
  terminalEvents.add(/* legacy random-id fallback */);
}
```

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
