---
id: story-fix-stale-ctx-messageapi-rearm-on-reload
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-03
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
