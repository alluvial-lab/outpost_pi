---
id: story-fix-stale-ctx-messageapi-rearm-on-reload
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-08
reverted_misguided_fix: 2026-07-03
---

# `internal_error: Agent rejected incoming message: …ctx is stale…` (reopened — prior fix was wrong)

## Status: REOPENED. The `factoryApi` re-arm fix was REVERTED — its premise was false.

A first fix attempt (retaining the factory `pi` as `factoryApi` and re-arming
`messageApi` from it on `session_start`) shipped, passed tests, and was
deployed — but **did not fix the symptom**. Operator still hit the stale
`internal_error` on a fresh restart with a peer session in the same CWD,
followed by `agent session not bound yet` (the null-`messageApi` fallback).
The fix was reverted; the bug is open.

## Why the prior fix was wrong (corrected root cause)

The prior fix assumed the factory `pi` (`ExtensionAPI`) is **session-stable**
because it routes `sendMessage`/`sendUserMessage` through `runtime`, claimed to
be rebound on every session start. **This is false.** Verified in the SDK
source (`core/extensions/loader.js:175-227` `createExtensionAPI`):

```js
sendUserMessage(content, options) {
    runtime.assertActive();          // ← throws stale HERE
    runtime.sendUserMessage(content, options);
}
```

`runtime` IS the `ExtensionRunner`, and `assertActive()` throws the stale error
if the runner was invalidated — **before** delegating to `runtime.sendUserMessage`.
So the factory `pi` is **not** session-stable; `pi.sendUserMessage` throws the
same stale error as a captured ctx after a replacement. Re-arming from
`factoryApi` just re-armed a *different stale object*, then `wakeAgent`'s catch
`forget()`-ed it (nulling `messageApi`) → next message returned
"agent session not bound yet". That matches the two errors the operator saw in
sequence.

## The real architectural constraint

The ONLY SDK surface that carries a working `sendUserMessage` bound to the
*current* live session is a **`ReplacedSessionContext`** from
`createReplacedSessionContext()` (`agent-session.js:2541`), which binds
`sendUserMessage` to the AgentSession's own method. That ctx is handed out
**only** inside the `withSession` callback during an SDK-driven replacement
(`newSession`/`fork`/`switchSession`/`resume`). The plain `session_start` ctx
carries ui/cwd/abort/compact/sessionManager but **NO `sendUserMessage`**.

So any `messageApi` we capture goes stale on the NEXT replacement (peer `/new`
in same CWD, `/reload`, `/resume`, daemon respawn). There is no
session-stable "deliver a message to the current session" entry point on the
plain ctx. **This is the core gap.** The 0.5.4 stale-context work and the
active `story-stale-action-boundary-regression-tests` did not solve
out-of-band message delivery after an uncommanded replacement.

## What needs to happen (design, not yet implemented)

The fix cannot be "re-arm from a cached object" — every cached object goes
stale. Options to evaluate at design time:

1. **Re-capture on every `session_start` via `withSession`-equivalent.** The
   SDK only hands a `ReplacedSessionContext` during an SDK-driven switch. For
   a plain `session_start` (reload/resume/peer-replacement), there may be no
   `withSession` callback. Investigate whether the extension can request a
   fresh `ReplacedSessionContext` from the new session/runner on
   `session_start` (e.g. via `ctx.sessionManager` → session →
   `createReplacedSessionContext`), or whether the SDK needs a hook for it.
2. **Tolerate the gap gracefully.** When `messageApi` is stale/null, instead
   of `internal_error`, return a recoverable "session replacing, retry"
   signal so the phone retries after the next `session_start` rebinds. Does
   not fix delivery but removes the broken UX. Pairs with the parked
   `idea-mobile-restart-pi-session-affordance`.
3. **Peer-same-CWD specific:** confirm whether a peer `/new` in the same CWD
   is a separate process (then our extension instance is the wrong one
   entirely — a routing problem) or the same process with a replaced session
   (then option 1 applies). This needs live-process inspection; could not be
   determined from the sandbox.

### Mobile lockout cost (confirmed 2026-07-08, live)

This is not a "one dropped message during the reload dead window" bug — for
a mobile-only operator it is a **session lockout**. When a session
replacement (`/new`, `/resume`, `/fork`, `/reload`, daemon respawn) on the
pi invalidates `messageApi`, the phone cannot deliver any message to that
session until a `session_start` rebinds a working ctx. The phone's only
session-control affordance is the quick-action "new session" (`session_new`
→ `withSession` → `_bindReplacementContext` → rebinds `messageApi` from a
fresh `ReplacedSessionContext`), which **does** recover delivery — but it
**starts a fresh session and discards the current conversation.** So the
mobile recovery choice is "can't send anything" or "blow away the session to
get delivery back." A workstation `/reload` (factory re-init re-arms a
working `messageApi`) is the context-preserving recovery, but it is not
reachable from mobile (parked as `idea-mobile-session-control` §"`/reload`
button"). The self-heal in option 1 is the real fix — neither `/reload` nor
`session_new` should be required to recover delivery after a replacement.

### Stuck "not delivered" bubble (folded in 2026-07-08)

The recoverable-wake-failure path (`index.ts:2152-2160`) does `console.warn`
+ returns **without sending anything to the phone.** So a message that hit
the stale ctx gets no echo and no error; the phone waits the full 20s
`send_timeout`, then shows a permanent "not delivered" bubble with no retry.
The operator observed this live: the first message after a `/reload` (sent
during the dead window) is now stuck as "not delivered" in the mobile chat
with no way to clear or retry it. This UX gap is part of this story's
acceptance criteria — the recoverable path must not leave a permanent,
unretryable "not delivered" scar:

- **AC (stuck bubble):** a recoverable wake failure (stale ctx / null
  `messageApi`) must either (a) signal the phone to retry after the next
  `session_start` rebinds, or (b) surface a transient "session replacing —
  retry" state that clears when delivery is restored — NOT a permanent
  20s-timeout "not delivered" bubble. The current `console.warn`-and-return
  is insufficient.
- This pairs with option 2 (tolerate gracefully): the recoverable signal
  IS the retry/clear trigger the phone needs. If option 1 (self-heal) lands,
  the dead window shrinks to near-zero and the stuck bubble becomes rare —
  but the recoverable path still must not scar permanently for the residual
  cases.

## Why this is hard to test in isolation

The bug requires a real SDK session replacement invalidating a captured ctx —
the unit-test `makePi()`/`makeSessionStartCtx()` mocks don't capture the
`runtime.assertActive()` staleness, so the prior (wrong) fix's tests passed
without proving anything. Any new fix needs an integration test that drives an
actual `ctx.newSession()`/`/reload` through the real SDK runner and asserts
delivery to the new session works, OR an honest xfail tied to this story.

## What IS fixed and deployed (not reverted)

- `resolveRemoteSessionId` stale-`sessionManager`-getter crash guard
  (`story-fix-stale-ctx-wrapactionctx-crash` covers the class; this one in
  `remote_session.ts`). Still deployed, still correct.
- `wrapActionCtx` stale-`modelRegistry`-getter crash guard
  (`story-fix-stale-ctx-wrapactionctx-crash`). Still deployed, still correct.
- Resume transcript backfill
  (`story-mobile-chat-blank-on-pair-after-pre-pair-work`). Still deployed.

These three crash/backfill fixes are sound; only the `messageApi` re-arm was
wrong and is reverted.

## References

- SDK: `core/extensions/loader.js:175-227` (`createExtensionAPI` —
  `sendUserMessage` calls `runtime.assertActive()` first).
- SDK: `core/agent-session.js:2541` (`createReplacedSessionContext` — the only
  session-bound `sendUserMessage`).
- SDK: `core/agent-session-runtime.js:117-125` (`finishSessionReplacement` /
  `withSession`).
- `pi-extension/src/session/sdk_session_projection.ts` — `wakeAgent`,
  `forget`, `bindSessionContext`, `messageApi` (reverted to pre-fix state).
- `pi-extension/src/index.ts:1859-1873` — `_wakeAgent` (error surfacing).
- `pi-extension/src/index.ts:1966-1975` — `_sendDeliveryError`.
- Reverted: the `factoryApi` field and `bindSessionContext` re-arm block.

## Design (2026-07-08) — the null-window race, confirmed by live evidence

### Root cause confirmed: hypothesis (A) — the null-window race

The feature's SDK investigation left two hypotheses; today's live evidence
settles it. After a TUI `/reload`, the operator's **first** phone message hit
`stale after session replacement`, but the **second** delivered fine. That
pattern is the signature of a transient null window, not a persistently-broken
binding.

The `/reload` ordering (SDK `agent-session.js:1966-1985` + our
`composition_root.ts:60-76`):

1. `session_shutdown` event → our `disposeRuntimePorts` → `clearStaleContexts()`
   → **`_messageApi = null; _pi = null`** (null window OPENS).
2. `await this._resourceLoader.reload()` → `loadExtensionsCached` → `factory(api)`
   → our `bindApi(freshPi)` → **`_messageApi = freshPi`** (null window CLOSES).
3. `_buildRuntime` → new `ExtensionRunner`.
4. `session_start` event → `bindSessionContext(ctx)`.

The null window is between (1) and (2). Both are `await`ed sequentially inside
the SDK's `reload()`, but the phone's relay WebSocket is a separate async
path: a `user_message` arriving on the socket between (1) and (2) is processed
with `_messageApi === null` → `wakeAgent` returns `not bound yet` (recoverable)
→ `_deliverUserMessage`'s recoverable path `console.warn`s + returns without
telling the phone → the phone's 20s `send_timeout` scars it as a permanent
"not delivered" bubble.

**The re-arm already works** (message 2 proved it: `bindApi` re-arms a fresh,
non-stale `pi` bound to the new runtime). The bug is purely the unguarded null
window + the recoverable path's failure to tell the phone to retry.

### Architectural choice: queue-and-replay on the null window (not re-arm)

The feature evaluated re-capture-via-`withSession` (option 1) and graceful
tolerance (option 2). The live evidence rules out option 1 as the fix for
*this* symptom: `bindApi` already re-arms correctly — there is no re-arm bug to
fix. The gap is the window, and the right fix is **option 2 (tolerance) done
properly**: when `wakeAgent` returns recoverable (null `messageApi` during the
null window OR a genuinely-stale ctx), the extension must not silently drop the
message — it must **queue it for replay once `bindApi` re-arms**, and tell the
phone a transient state so it doesn't scar a permanent "not delivered."

This is a queue-of-N-bounded-by-time, not unbounded queueing, and it does NOT
violate the fan-out suspend feature's drop-don't-queue design (that's for
*outbound* fan-out to offline peers; this is *inbound* delivery to the local
agent, a different surface).

### Implementation units

#### Unit 1: inbound message replay queue during the null window
**File**: `pi-extension/src/index.ts` (`_deliverUserMessage` ~L2125, `_wakeAgent` ~L1983)

When `_wakeAgent` returns `{ok:false, recoverable:true}` (null `messageApi` /
stale ctx), instead of `console.warn` + return:
- Stash the message (`{sender, msg, content, shouldSteer}`) in a bounded replay
  queue (max 1–2 messages, TTL ~5s — the null window is sub-second; 5s covers a
  slow `_resourceLoader.reload()`).
- Return a **transient recoverable signal** to the phone (not silence): a
  `delivery_pending` wire event (or reuse the existing `error` with a
  recoverable code) so the phone shows "delivering…" / clears the pending
  bubble's send-timer, rather than scarring "not delivered."
- On the next `bindApi` (null-window close), drain the queue: re-attempt
  `_wakeAgent` for each stashed message. If it succeeds, the normal echo path
  fires; if it still fails (genuinely broken, not just the window), surface a
  real `internal_error`.

**Acceptance Criteria**:
- [ ] A `user_message` arriving during the `/reload` null window
      (`_messageApi === null`) is queued, not dropped.
- [ ] The phone receives a transient `delivery_pending` (or equivalent
      recoverable) signal, NOT a 20s `send_timeout` → permanent "not
      delivered" bubble.
- [ ] On `bindApi` re-arm, the queued message is delivered to the new
      session's agent (echo fires).
- [ ] A genuinely-stale ctx that does NOT recover within the TTL surfaces a
      real `internal_error` (no infinite queue).
- [ ] Regression test: deliver a `user_message` to a projection with null
      `messageApi` → assert the message is queued + a `delivery_pending` is
      sent + `bindApi` drains the queue and delivers.

#### Unit 2: phone-side `delivery_pending` handling (clears the stuck bubble)
**File**: `app/lib/data/sync/sync_service.dart` (the `send_timeout` path ~L361)

The phone's `send_timeout` (20s no-echo) is what scars the permanent "not
delivered" bubble. On a `delivery_pending` signal from the extension:
- Disarm (or extend) the send-timer for that message — it's not lost, it's
  pending.
- Show a transient "delivering…" state (or no-op if the existing pending
  bubble already conveys this).
- When the echo finally arrives (after the queue drains), confirm the row as
  normal.

**Acceptance Criteria**:
- [ ] A `delivery_pending` signal disarms the 20s `send_timeout` for that
      message (no permanent "not delivered" scar).
- [ ] The eventual echo confirms the row (no dupe).
- [ ] If no echo arrives within an extended window (e.g. 60s — the queue TTL
      + drain), THEN surface "not delivered" (genuine failure).

### Wire shape (decide at implement time)

Prefer reusing the existing `error` ServerMessage with a new recoverable code
(e.g. `code: "delivery_pending"`) over adding a new ServerMessage variant —
minimizes protocol surface. The app's `ErrorMessage` handler already exists;
add a `delivery_pending` case that disarms the send-timer instead of scarring.
If the existing `error` shape can't carry a non-error semantics cleanly, add a
new `delivery_pending` ServerMessage and update `PROTOCOL.md`.

### Pre-mortem risks

- **Queue grows unbounded under a flap storm.** Mitigated by max-1–2 + TTL;
  if `bindApi` doesn't re-arm within 5s, surface `internal_error` and stop
  queueing. The null window is sub-second; 5s is generous.
- **Replayed message lands on the WRONG session.** The queue drains on
  `bindApi`, which fires for the NEW session. The message's `session_id` was
  stamped for the OLD session. The session-gate may reject it as
  `session_mismatch`. Mitigation: re-stamp the queued message's `session_id`
  to the new session at drain time, OR deliver via the new session's
  `sendUserMessage` directly (which doesn't carry a session_id). Verify the
  gate's behavior on a drain-time delivery.
- **Masking a genuinely-broken ctx.** The TTL + `internal_error` fallback
  ensures a real failure still surfaces. The split is: recoverable + recovers
  within TTL → queued; recoverable + TTL expires → `internal_error`.

### Implementation order
1. Unit 1 (extension replay queue + `delivery_pending` signal + regression
   test).
2. Unit 2 (phone-side `delivery_pending` → disarm send-timer).
3. Integration: `/reload` then phone-message-in-window → assert delivery to
   the new session (the feature's mandatory integration test; may be a stretch
   goal if the SDK harness is too hard — ship the unit test + honest note).
