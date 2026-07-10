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
updated: 2026-07-10
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

## Implementation notes
- Files changed: `protocol/schema/defs/app-pi-common.schema.json`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/protocol/generated/protocol.generated.ts`, `app/lib/data/sync/sync_service.dart`, `app/test/data/sync/sync_service_test.dart`, `app/lib/protocol/generated/protocol.g.dart`, `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, `PROTOCOL.md`.
- Tests added: pi-extension regression coverage for stale/null `messageApi` queuing, TTL expiry to `internal_error`, and bindApi replay delivery; app regression coverage for `delivery_pending` extending the no-echo window and later failing if no replay echo arrives.
- Discrepancies from design: Dart protocol generation used the existing committed Dart IR fixture, so the generator/fixture were extended to emit a typed `KnownErrorCode.deliveryPending` enum while keeping `ErrorMessage.code` as an open string.
- Edge cases handled: queue is bounded to 2 entries with oldest-drop failure, queued entries fail on TTL or second session replacement, recoverable wake failures send `delivery_pending` instead of silence, app does not discard streaming/turn state for `delivery_pending`, and eventual echo still uses the existing dedupe path.
- Verification: `cd pi-extension && corepack pnpm generate:protocol && corepack pnpm typecheck && corepack pnpm test`; `cd app && flutter analyze && flutter test test/data/sync/sync_service_test.dart`; `node --check tools/protocol-codegen/bin/protocol-codegen.mjs`.

## Review outcome (2026-07-08)

Two cross-model review passes (`openai-codex/gpt-5.5`, deep lane):

1. **Deep review** returned `Request changes` (2 important, no blockers):
   - `withSession` re-arm path (`_bindReplacementSessionContext`, the mobile `session_new` recovery) re-armed `_messageApi` but did NOT drain the pending queue → a queued message would sit until TTL → `internal_error` despite a valid API. **Fixed:** added `_drainPendingDeliveryQueue()` to `_bindReplacementSessionContext`. Test added.
   - Bounded-queue overflow (max-2 drop) was untested. **Fixed:** test added (3 messages → oldest dropped as `internal_error`, 2 remain queued).
2. **Re-review** returned `Approve` (findings resolved, no blockers/important/nits). Confirmed the drain is safe on empty/double-drain and the test helper faithfully arms both module-level + projection `messageApi`.

Final verification: pi-extension 769/769 pass (was 767; +2 review tests); app analyze clean + sync_service tests pass. Committed as `eab7315` (impl) + `1c96a37` (review fixes).

## CORRECTED root cause (2026-07-08, live ring-log evidence) — the prior "null-window" analysis was wrong

**Reverted `done → drafting`.** The "null-window race" framing above was incorrect.
Live ring logs (`debug/ae8-*.bin`, `debug/aef-*.bin`, 2026-07-08) plus a fresh TUI
error ("agent session not bound yet") show the actual failure is a **stuck-null
`messageApi` after `/new`/`/resume`/`/fork`**, not a transient mid-`/reload` window.

### What the SDK actually does (traced against `@earendil-works/pi-coding-agent`)

The extension factory (`factory(api)` → our `bindApi` port) is invoked by
`resourceLoader.reload()` → `loadExtensionsCached` → `loadExtension` →
`factory(api)` (`loader.js:350`). This is the **only** path that re-arms
`messageApi` with a fresh, non-stale `pi`.

- **`/reload`** (`agent-session.js:1966`) calls `this._resourceLoader.reload()`
  (line 1972) → re-invokes factories → `bindApi(freshPi)` re-arms `messageApi`.
  ✅ This is why a workstation `/reload` recovers the stuck-null state.
- **`/new` / `/resume` / `/fork`** (`agent-session-runtime.js`) call
  `createRuntime` → `resourceLoader.getExtensions()` (`sdk.js:260`), which
  returns the **cached** `extensionsResult` — NO `reload()`, NO factory
  re-invoke. A new `ExtensionRunner` is created with a fresh runtime, but
  **`bindApi` is never called**, so `messageApi` keeps pointing at the old
  `pi` bound to the now-stale runtime.

So after `/new`/`/resume`/`/fork`:
1. The new `ExtensionRunner` invalidates the old runtime (stale).
2. `messageApi` (still the old `pi`) throws stale on the next `sendUserMessage`.
3. `wakeAgent`'s catch calls `forget(api)` → `messageApi = null`.
4. **Nothing re-arms it** — `bindApi` only fires on `/reload`. `messageApi`
   stays null → every subsequent inbound message gets "agent session not
   bound yet" (recoverable wake failure) until a `/reload` (the only factory
   re-invoke) happens.

### Why the shipped queue-and-replay code is NOT this fix (but is kept as companion)

The queue-and-replay tolerance layer (commits `eab7315` + `1c96a37`, split into
`story-stale-ctx-recoverable-delivery-tolerance`, `stage: done`) does NOT heal
the stuck-null: it queues the message + sends `delivery_pending` + drains on the
next `bindApi` — but `bindApi` is the `/reload` the operator must do anyway. So
even deployed, it would replace the silent 20s timeout with a `delivery_pending`
bubble (a real UX win — no permanent scar) but the message still wouldn't
deliver without a workstation `/reload`. It is the **tolerance/mitigation**,
not the **self-heal**.

### Why a fork-local transparent self-heal is blocked

The only SDK surface carrying a working `sendUserMessage` bound to the live
session is `AgentSession.createReplacedSessionContext()` (`agent-session.js:2541`),
handed out **only** inside a `withSession` callback during an SDK-driven
replacement. The plain `session_start` ctx (`ExtensionRunner.createContext`,
`runner.js`) exposes `sessionManager`/`modelRegistry`/`ui`/`cwd` but **NOT** the
`AgentSession` itself — so `createReplacedSessionContext` is unreachable from a
plain `session_start`. `pi-coding-agent` is the upstream runtime (consumed as
a dependency, not forked), so this is not editable in-fork.

### Feasible paths (none are a transparent no-loss heal)

1. **Phone-driven `session_new` (`withSession`) — re-arms, but discards the
   conversation.** `handleSessionNew` → `ctx.newSession({withSession})` → SDK
   hands a `ReplacedSessionContext` carrying `sendUserMessage` →
   `_bindReplacementSessionContext` re-arms. Works when the *extension* drives
   the replacement. This is the mobile-quick-action recovery, not transparent.
2. **Upstream ask:** expose `sendUserMessage` (or the live `AgentSession` /
   a `createReplacedSessionContext`-equivalent) on the plain `session_start`
   ctx, OR make `/new`/`/resume`/`/fork` re-invoke the extension factory (so
   `bindApi` fires). Either unblocks a fork-local transparent heal.
3. **Mitigation (shipped):** `delivery_pending` stops the permanent scar; a
   `/reload` button (parked, `idea-mobile-session-control`) is the
   context-preserving recovery the operator needs on mobile-only.

### Re-scoped acceptance criteria (the self-heal — OPEN, SDK-blocked)

- [ ] A `/new`/`/resume`/`/fork` on the pi re-arms `messageApi` so the next
      inbound `user_message` delivers without a workstation `/reload`.
      Blocked on path (1) verifying the phone `session_new` clears the
      stuck-null live, OR path (2) an upstream change.
- [ ] Confirm live: after a `/new`, a mobile message delivers (not
      "agent session not bound yet").
- [ ] Regression test against a real SDK `/new`/`/resume` (mocks can't model
      the runtime-staleness — the lesson from the reverted first fix).

### What's NOT in this story anymore

- The `delivery_pending` tolerance + bounded replay queue + app-side timer
  disarm — split to `story-stale-ctx-recoverable-delivery-tolerance` (done).
  Kept in the codebase; correct and reviewed on its own merits.

## SDK deep-dive (2026-07-10) — the structural-stale root cause, verified

Re-traced the SDK source (`@earendil-works/pi-coding-agent@0.79.10`, under
`dist/`) to verify the "SDK-blocked" conclusion and found the deeper reason
the factory-`pi` re-arm can NEVER work after a non-`reload` replacement —
even if the upstream "re-invoke factory on `/new`" ask landed.

### The shared-runtime stale flag is never cleared

The extension `runtime` is created **once** by `createExtensionRuntime()`
(`loader.js:115`) and **cached** in `extensionsResult` (`resource-loader.js:166`,
`getExtensions()` returns `this.extensionsResult` — the same object every call).
`/new`/`/resume`/`/fork` call `getExtensions()` (cached), NOT `reload()` (which
re-runs `loadExtensions` → fresh runtime). So all non-`reload` replacements
**reuse the same `runtime` object** with the same closure-captured `state`.

`runtime` has (`loader.js:119-145`):
```js
const state = {};
const assertActive = () => { if (state.staleMessage) throw new Error(state.staleMessage); };
const runtime = {
  ...
  assertActive,
  invalidate: (message) => { state.staleMessage ??= message ?? "...stale..."; },
};
```

`state.staleMessage` is set by `invalidate()` (with `??=` — only-if-not-already-
set) and **NEVER CLEARED**. There is no `clearStale()` / `state.staleMessage =
null` anywhere in the SDK (`rg 'staleMessage'` across `loader.js` + `runner.js`
shows only reads + the `??=` set).

When `/new` runs (`agent-session-runtime.js:117-134`):
1. The old `ExtensionRunner` is invalidated → `runner.invalidate()` → sets
   `runner.staleMessage` AND calls `runtime.invalidate()` → sets
   `state.staleMessage`.
2. A **new** `ExtensionRunner` is created with the **same cached `runtime`**
   (`agent-session.js:1931`). The new runner's own `staleMessage` is `undefined`
   (so the new runner's ctx works), but `runtime.state.staleMessage` is **still
   set** from step 1.
3. The new runner's `bindCore` mutates `runtime.sendUserMessage =
   newActions.sendUserMessage` (the new session's) — but `assertActive()` still
   throws because `state.staleMessage` is set.

### Consequence: the factory `pi` is structurally permanently stale

The factory `pi` (`createExtensionAPI`, `loader.js:212-219`) routes
`sendUserMessage` through `runtime.assertActive()` **then**
`runtime.sendUserMessage()`:
```js
sendUserMessage(content, options) {
    runtime.assertActive();          // ← throws: state.staleMessage is set
    runtime.sendUserMessage(content, options);
}
```

So after the FIRST `/new`/`/resume`/`/fork`, the factory `pi` throws stale on
**every** `sendUserMessage` — forever, until a `/reload` creates a fresh
runtime (the only path that clears `state.staleMessage`). Re-arming
`messageApi` from the factory `pi` (the reverted fix's approach, or the
upstream "re-invoke factory" ask) **cannot work** — the `pi` is stale at the
runtime level, not the binding level.

### The only working surface: `ReplacedSessionContext`

`AgentSession.createReplacedSessionContext()` (`agent-session.js:2529-2534`)
bypasses `runtime.assertActive()` entirely — it binds `sendUserMessage`
directly to `this.sendUserMessage` (the `AgentSession`'s own method,
`agent-session.js:1020`, which goes straight to `this.prompt()` with NO
`assertActive` guard):
```js
createReplacedSessionContext() {
    const context = Object.defineProperties({}, ...createCommandContext());
    context.sendUserMessage = (content, options) => this.sendUserMessage(content, options);
    return context;
}
```

This ctx is handed out **only** inside the `withSession` callback during an
SDK-driven replacement (`agent-session-runtime.js:117-122`). The plain
`session_start` ctx (`ExtensionRunner.createContext()`, `runner.js:411-475`)
exposes `ui`/`cwd`/`sessionManager`/`modelRegistry`/`abort`/`compact` but
**NOT** `sendUserMessage` and **NOT** the `AgentSession` — so
`createReplacedSessionContext` is unreachable from a plain `session_start`.
`ctx.sessionManager` is the history manager (`SessionManager`), not a handle
to the live `AgentSession`.

### Why this confirms the story's "SDK-blocked" conclusion (and sharpens it)

The story's two feasible paths stand, with the structural-stale finding
sharpening path (2):

1. **Phone-driven `session_new` (`withSession`)** — re-arms from a
   `ReplacedSessionContext`, but discards the conversation. Mobile quick-action
   recovery, not transparent.
2. **Upstream ask** — but it's now TWO asks, not one:
   - (a) make `/new`/`/resume`/`/fork` re-invoke the extension factory (so
     `bindApi` fires), AND
   - (b) **clear `runtime.state.staleMessage` on the new runner** (without
     this, the re-invoked factory hands back a `pi` that still throws stale —
     the `??=` set from the old runner's invalidation persists).
   - OR: expose `sendUserMessage` (or the live `AgentSession` / a
     `createReplacedSessionContext`-equivalent) on the plain `session_start`
     ctx. This is the cleaner ask — it sidesteps the stale-flag entirely by
     giving the extension a non-`assertActive`-guarded surface.

### What this means for the fork

The self-heal is genuinely SDK-blocked — there is no fork-local code change
that can obtain a working `sendUserMessage` after an uncommanded
`/new`/`/resume`/`/fork`. The shipped `delivery_pending` tolerance (done,
`story-stale-ctx-recoverable-delivery-tolerance`) remains the correct
fork-local mitigation: it stops the permanent scar and queues for replay on
the next `/reload` (the only factory re-invoke). A mobile `/reload` button
(parked `idea-mobile-session-control`) is the context-preserving recovery.

The upstream ask (path 2) is the real fix. File it as an upstream issue
against `@earendil-works/pi-coding-agent` with the structural-stale evidence
above — the `state.staleMessage` never-cleared + the plain-ctx-missing-
`sendUserMessage` are the two concrete SDK gaps.

## Fork-local redesign (2026-07-10) — the cancel-and-re-drive pattern

Re-investigated whether the extension can fit the SDK's `withSession` model
for **uncommanded** replacements (operator `/new`/`/resume`/`/fork` in the
TUI), without an upstream change. There IS a fork-local path.

### The SDK surface that makes it possible

`ExtensionRunner.emit()` (`runner.js:522`) fires `session_before_switch`
**before** `/new`/`/resume`/`/fork` (`agent-session-runtime.js:145,126`),
passing `(event, ctx)` to registered handlers. The handler can return
`{cancel: true}` to **abort** the replacement (`emitBeforeSwitch` →
`beforeResult.cancelled` → early return, no replacement runs).

Critically, the `ctx` handed to the `session_before_switch` handler is built
by `createCommandContext()` (`runner.js:485`) — it carries `ctx.newSession({
withSession})` (line 496), and `ctx.newSession` calls `this.assertActive()`
on the **current** (pre-replacement) runner, which is **still valid** at
`session_before_switch` time. So the handler can drive its own replacement.

### The pattern: cancel the uncommanded replacement, re-drive with `withSession`

```
pi.on("session_before_switch", (event, ctx) => {
  if (event.reason === "new" || event.reason === "resume" /* || fork */) {
    if (_reDrivingReplacement) return;   // our own re-drive — let it through
    _reDrivingReplacement = true;
    // Cancel the uncommanded replacement (no withSession → no working ctx).
    // Re-issue it WITH a withSession that captures a ReplacedSessionContext.
    void ctx.newSession({
      withSession: (replacedCtx) => {
        _sdkSessionProjection.bindReplacementContext(replacedCtx);  // re-arms messageApi
        _reDrivingReplacement = false;
      },
    });
    return { cancel: true };
  }
});
```

The re-driven `ctx.newSession({withSession})` runs the FULL replacement
(`createRuntime` → new runner → `finishSessionReplacement(withSession)` →
`withSession(replacedCtx)`), and `replacedCtx.sendUserMessage` bypasses
`runtime.assertActive()` (binds directly to `AgentSession.sendUserMessage`).
So `messageApi` is re-armed with a working, non-stale surface — without a
`/reload`.

### Re-entrancy guard (the one real risk)

The re-driven `ctx.newSession` fires `session_before_switch` **again**. The
handler MUST let it through (return undefined / `{cancel:false}`) or it
infinite-loops. A module-level `_reDrivingReplacement` flag, set before
`ctx.newSession` and cleared in the `withSession` callback, gates it. The
flag is synchronous-set / async-cleared, but `session_before_switch` for
the re-drive fires synchronously inside `ctx.newSession` (before the
`await createRuntime`), so the flag is still set when it's checked — correct
ordering.

### What this does NOT preserve (open questions for design)

- **`/resume` semantics.** `/resume` switches to an *existing* session
  (different `sessionManager`/`sessionFile`), not a fresh one. The
  cancel-and-re-drive must pass the **same target** the operator chose, or
  it resumes the wrong session. `session_before_switch` carries
  `targetSessionFile` — the re-drive must forward it. `ctx.newSession` may
  not be the right re-drive for `/resume` (it's `ctx.navigateTree` /
  `switchSession`); verify the per-reason re-drive call.
- **`/fork` semantics.** `/fork` takes an `entryId`. The re-drive must
  forward it via `ctx.fork(entryId, {withSession})`.
- **The `setup` option.** `newSession` supports `options.setup` (line 161);
  an uncommanded `/new` may carry it. The re-drive must forward any options
  the original carried — but `session_before_switch`'s `event` may not
  expose them. Verify what's on the event.
- **TUI state.** Cancelling + re-driving may disrupt the TUI's own
  `/new`-flow state (loading animation, status container — see
  `interactive-mode.js:1153-1164`). The re-drive happens inside the
  handler, before the TUI's `newSession` action returns — verify the TUI
  doesn't double-render or lose state.

### Why this is a redesign, not a patch

This changes the extension from a **passive** `session_start` listener (which
the prior reverted fix assumed) to an **active** `session_before_switch`
interceptor that owns the replacement flow. It's a real architectural shift:
the extension becomes responsible for re-driving replacements so it can
inject a `withSession` and capture a working `messageApi`. The
`bindSessionContext` / `bindApi` / `clearStaleContexts` ports stay, but the
**re-arm trigger** moves from `bindApi` (factory, `/reload`-only) to
`bindReplacementContext` (withSession, every replacement).

### Acceptance criteria (re-scoped to the redesign)

- [ ] A `session_before_switch` handler intercepts uncommanded
      `/new`/`/resume`/`/fork`, cancels, and re-drives with a `withSession`
      that re-arms `messageApi` from a `ReplacedSessionContext`.
- [ ] Re-entrancy guard prevents the infinite loop.
- [ ] `/resume` and `/fork` forward their target/entryId (not just `/new`).
- [ ] After the re-drive, an inbound `user_message` delivers to the new
      session WITHOUT a workstation `/reload`.
- [ ] Regression test against a real SDK `/new`/`/resume` (mocks can't model
      the runtime-staleness — the lesson from the reverted first fix). If
      the harness is infeasible, an honest xfail + the `delivery_pending`
      tolerance as the shipped mitigation.
- [ ] No regression to the mobile `session_new` quick-action (which already
      drives `withSession` — the interceptor must not double-cancel it).

### Implementation order

1. Spike: register a `session_before_switch` handler, log the events +
   payload for `/new`/`/resume`/`/fork` to confirm what's on the event and
   whether the cancel-and-re-drive is clean (no TUI disruption, no loop).
2. If the spike confirms, implement the re-drive + re-entrancy guard +
   `bindReplacementContext` re-arm.
3. Integration test (the mandatory non-mock test).
