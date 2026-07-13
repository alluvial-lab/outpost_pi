---
id: story-extension-user-message-ingress-idempotency
kind: story
stage: review
tags: [pi-extension, bug, lifecycle, security]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-13
updated: 2026-07-13
implemented: 2026-07-13
unblocks: story-app-reattempt-held-pending-on-reconnect
---

# Dedupe `user_message` ingress by `(session_id, msg.id)` before `_wakeAgent`

## Brief

The extension's `user_message` ingress has **no idempotency guard by
`clientMessageId`**. A duplicate `user_message` frame — from any re-delivery
scenario — calls `_wakeAgent` again, triggering a **second agent turn** before
the transcript dedupe can suppress it. The transcript/UI dedupes by
`clientMessageId` (`transcript_projection` confirmedUsers/failedUsers keyed
by id; `session_history_replay` preserves the original id), but that dedupe is
*display-only* — it collapses duplicate rows, it does not prevent the agent
from being invoked twice.

This was surfaced by the option-4 review
(`story-app-reattempt-held-pending-on-reconnect`, parked): re-sending a
held-pending message that already reached the Pi (race window) would
double-execute the agent. But the risk is broader than option 4 — ANY
re-delivery can double-execute:

- **Reconnect flush:** a half-open socket's dead send buffer flushes on
  reconnect (the original half-open bug, ring `e4f-11f1`) — if the app also
  re-sent or the relay re-fanned-out, the Pi sees the message twice.
- **Relay fan-out:** `send_to_room` fans out to all conns at a `(peer, room)`
  key; a same-device reconnect window could deliver to both the old and new
  conn's Pi-side handler.
- **Cross-PC mesh:** `agent_send` / `agent_request` re-delivery.
- **Option 4 (parked):** the app re-sending held-pending messages on
  reconnect.

## Root cause (verified 2026-07-13 against `pi-extension/src`)

`_deliverUserMessage` (`index.ts:2442`) → `_attemptUserDelivery`
(`index.ts:2287`) calls `_wakeAgent` (invokes the agent) **before**
`_confirmUserDelivery` (`index.ts:2325`) records the confirmation. The
`user_message` ingress (`index.ts:2525-2534`) calls `_deliverUserMessage`
unconditionally — no check whether `msg.id` was already delivered in the
current session.

The existing `deliveredUserEventIds` map (`sdk_session_projection.ts:129`)
is keyed by **content signature** (`userContentSignature(text, images)`), not
by `clientMessageId` — it serves a different purpose (matching SDK-emitted
user messages back to app-submitted ids). It cannot be used directly as an
ingress dedupe guard.

## Design (to lock in during the design pass)

### The guard

Add a `clientMessageId`-keyed dedupe check at the top of `_deliverUserMessage`
(or in the `user_message` case before calling it): if `msg.id` was already
delivered in the current session, **do not re-invoke the agent** — re-emit the
echo (idempotent confirmation) and return.

```ts
// pseudo-code — at the top of _deliverUserMessage, before _attemptUserDelivery
const sessionId = _currentRemoteSessionId();
if (_sdkSessionProjection.wasUserMessageDelivered(sessionId, msg.id)) {
  // Already delivered — re-echo (idempotent) but do NOT re-invoke the agent.
  // The app's optimistic bubble may still be pending (it didn't see the first
  // echo), so re-broadcasting the echo confirms it without double-executing.
  _reEchoUserMessage(msg, sender);
  _deliveryDebugLog.log({ tag: "ingress_dedupe", id: msg.id, sessionIdTail: idTail(sessionId) });
  return;
}
```

### Where to store the delivered-id set

Two options:
1. **A dedicated `Set<string>` per session** on `SdkSessionProjection`
   (`deliveredUserMessageIds: Map<sessionId, Set<clientMessageId>>`), populated
   in `_confirmUserDelivery` (alongside the existing
   `rememberDeliveredUserEvent`). O(1) lookup. Must be cleared on session
   replacement (`/new`, `/resume`, `/fork`, `/reload`) — same lifecycle as the
   transcript log.
2. **Scan the transcript log** `forSession(sessionId)` for a `user_confirmed`
   with matching `clientMessageId`. O(n) per message, but no new state to
   lifecycle. The log is already the source of truth for what was delivered.

**Lean: option 1** (dedicated set). The ingress path is hot (every user
message), and O(1) matters. The lifecycle is the same as `transcriptLog`
(clear on session replacement), so it's not a new lifecycle burden.

### The re-echo

When a duplicate is detected, re-emit the `user_message` echo
(`_owners.broadcast(echo)`) so the app's optimistic bubble confirms — but do
NOT call `_wakeAgent`. This makes the duplicate delivery idempotent: the app
sees one confirmed row (transcript dedupe), and the agent runs once.

### Session scoping

The guard is `(sessionId, msg.id)`. A `clientMessageId` is app-generated and
unique per send, so the same `msg.id` in a *different* session is a different
message (e.g. after `/new`, the app generates a fresh id). The guard must use
the *current* session id, and the delivered-id set must be cleared on session
replacement so a stale id from an old session doesn't falsely suppress a new
send (though app-generated ids make this unlikely).

## Acceptance

- A duplicate `user_message` frame with the same `id` in the same session
  does NOT trigger a second `_wakeAgent` call — the agent runs once.
- The duplicate re-emits the echo so the app's optimistic bubble confirms
  (idempotent confirmation).
- A genuinely new `user_message` (different `id`) is delivered normally.
- After session replacement (`/new`), the delivered-id set is cleared — a
  fresh send is not falsely suppressed.
- A test simulating duplicate delivery (same `id`, same session) asserts the
  agent is invoked once, not twice.

## Out of scope

- The app-side re-send (option 4) — this story is the prerequisite that
  unblocks it. Once this lands, option 4's re-send becomes safe.
- Bounding the delivered-id set size (memory). In practice a session has
  bounded user messages; if needed, an LRU cap can be added later.

## References

- `pi-extension/src/index.ts:2442` — `_deliverUserMessage` (the guard hook point).
- `pi-extension/src/index.ts:2287` — `_attemptUserDelivery` → `_wakeAgent` (the double-execution).
- `pi-extension/src/index.ts:2325` — `_confirmUserDelivery` (records confirmation AFTER wake).
- `pi-extension/src/index.ts:2525-2534` — `user_message` ingress (no dedupe).
- `pi-extension/src/session/sdk_session_projection.ts:129` — `deliveredUserEventIds` (content-keyed, different purpose).
- `pi-extension/src/session/sdk_session_projection.ts:427` — `rememberDeliveredUserEvent` (where to also record the clientMessageId-keyed set).
- `pi-extension/src/session/transcript_event_log.ts` — `TranscriptEventLog` (lifecycle model; `clear()` on session replacement).
- `.work/backlog/story-app-reattempt-held-pending-on-reconnect.md` — option 4 (parked; this story unblocks it).
