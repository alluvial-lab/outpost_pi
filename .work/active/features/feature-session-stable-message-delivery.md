---
id: feature-session-stable-message-delivery
kind: feature
stage: implementing
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on:
  - story-fix-stale-ctx-messageapi-rearm-on-reload
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-03
designed: 2026-07-03
---

# Session-stable message delivery (the stale-`internal_error` architectural gap)

## Brief

Inbound phone messages are delivered to the Pi agent via `messageApi`
(`wakeAgent` → `sendUserMessage`). Today `messageApi` is captured from either
the factory `pi` or a `withSession` `ReplacedSessionContext`, and **every
capturable binding goes stale on the next session replacement** — a TUI
`/reload`, an app-driven `/new`, a `/resume`, a daemon respawn, or a peer
session replacing this one in the same CWD. When that happens the phone gets
`internal_error: Agent rejected incoming message: …ctx is stale…`, and once
`wakeAgent`'s catch `forget()`s the binding, subsequent messages return
`agent session not bound yet`. The phone is then broken until a full pi
restart — which a phone-only operator cannot trigger (see parked
`idea-mobile-restart-pi-session-affordance`).

This feature closes the architectural gap: **there must be a reliable way to
deliver a user message to the current live session from outside any captured
ctx, surviving session replacement.**

## Why this is a feature, not a story

A prior attempt (`story-fix-stale-ctx-messageapi-rearm-on-reload`) shipped a
one-line "re-arm from the factory `pi`" fix that **passed its mock-based unit
tests but did not fix the symptom** — because the mocks don't model
`runtime.assertActive()`, the SDK guard that actually throws stale. The fix
premise (that the factory `pi` is session-stable) was false; `pi.sendUserMessage`
calls `runtime.assertActive()` first (`loader.js:224`), which throws stale
after a replacement. That story is reverted and reopened under this feature.

The lesson: this bug class **cannot be validated with mock-based unit tests**.
It requires an integration test that drives a real SDK session replacement
through the actual `ExtensionRunner` and asserts delivery to the new session
works. Building that harness is design-bearing work, so this is a feature at
`drafting`, not a story.

## The architectural constraint (confirmed against SDK source)

The only SDK surface carrying a working `sendUserMessage` bound to the
*current* live session is a `ReplacedSessionContext` from
`AgentSession.createReplacedSessionContext()` (`agent-session.js:2541`), which
binds `sendUserMessage` to the AgentSession's own method. That ctx is handed
out **only** inside the `withSession` callback during an SDK-driven
replacement (`agent-session-runtime.js:117-125`). The plain `session_start`
ctx (`ExtensionRunner.createContext`, `runner.js:411`) carries
ui/cwd/abort/compact/sessionManager/modelRegistry but **NO `sendUserMessage`**.
And the factory `pi` (`createExtensionAPI`, `loader.js:175`) routes through
`runtime`, which `assertActive()`-guards — so it goes stale too.

So: **no session-stable "deliver a message to the current session" entry point
exists on any plain ctx.** This is the core gap.

## Design options to evaluate (do NOT pick before investigation)

1. **Re-capture a `ReplacedSessionContext` on every `session_start`.** The SDK
   only hands one out during a `withSession` callback. Investigate whether the
   extension can obtain one outside that callback — e.g. reach the live
   `AgentSession` via `ctx.sessionManager` (does the SDK expose a
   session/runner → `createReplacedSessionContext` path from the plain ctx?),
   or whether the SDK needs a new hook. **Open question requiring SDK
   investigation.**
2. **Bridge via `ctx.sessionManager` + a fresh `AgentSession` reference.** If
   the plain ctx's `sessionManager` can reach the current session, build a
   thin adapter that calls `session.sendUserMessage` directly. Requires
   confirming the SDK exposes the live `AgentSession` from the ctx.
3. **Tolerate the gap gracefully** (fallback, not a fix): when `messageApi`
   is stale/null, return a recoverable "session replacing, retry" signal
   instead of `internal_error`, so the phone retries after the next
   `session_start`. Does not fix delivery but removes the broken-permanent UX.
   May ship as a stopgap while (1)/(2) are investigated.
4. **Process model:** confirm whether a "peer session in the same CWD" is a
   separate process (then this extension instance is the wrong one entirely —
   a relay routing problem, not a message-delivery problem) or the same
   process with a replaced session. The `RoomAlreadyOpenError` guard
   (`relay_client.ts:65`) suggests the relay rejects a second claim, but the
   operator's symptom implies a same-process replacement. Needs live-process
   inspection to confirm.

## What must ship with any fix

- **An integration test** that drives a real `ctx.newSession()` (and/or
  `/reload`) through the actual SDK `ExtensionRunner` and asserts an inbound
  `user_message` is delivered to the **new** session, not rejected as stale.
  This is the non-negotiable gate — mock-based tests already proved they
  can't catch this class. If the harness is too hard to build against the
  installed SDK, document exactly why and ship option (3) as a stopgap with an
  honest xfail tied to this feature.
- **A clear semantics for the gap window:** between a replacement and the
  rebind, an inbound message either (a) is delivered to the new session, or
  (b) returns a recoverable retry signal — never a permanent `internal_error`
  that strands the phone.
- **No regression** to the pair-code QR / `sendPiMessage` path (which relies on
  the factory `pi` armed at `bindApi`; the additive-bind contract documented
  in `sdk_session_projection.ts:148-167` must hold).

## Out of scope (tracked separately)

- The mobile restart affordance (`idea-mobile-restart-pi-session-affordance`)
  — adjacent (it's how a phone-only operator recovers today), but a separate
  UX concern.
- The crash-class siblings (`resolveRemoteSessionId`, `wrapActionCtx`) —
  already fixed and deployed; those are unguarded getter reads, a different
  problem.

## SDK investigation findings (2026-07-03, feature-design Phase 3)

Read the installed SDK source (`@earendil-works/pi-coding-agent@0.80.3`). The
mechanism is more subtle than any prior hypothesis (including the reverted
fix's premise):

1. **The factory `pi` is re-created and re-injected on every session
   replacement.** `loadExtension` (`loader.js:340`) builds a fresh `api` via
   `createExtensionAPI(extension, runtime, ...)` on every load — even when the
   *factory function* is cached. On `reload()` (`agent-session.js` reload),
   `newSession`/`resume`/`fork` (`agent-session-runtime.js`),
   `_buildRuntime` creates a new `ExtensionRunner` + new `runtime`, re-loads
   extensions → **`factory(api)` is re-invoked with a fresh `pi`** bound to the
   new (non-stale) `runtime`.
2. **Our `bindApi` IS called with the fresh `pi` on every replacement.** The
   factory body (`index.ts:1131-1134`) calls `legacyRuntime.ports.session.bindApi(pi)`
   on every factory invocation → `_pi = boundPi; _messageApi = boundPi;
   _sdkSessionProjection.bindApi(boundPi)` → `bindCapabilities` re-arms
   `messageApi` to the fresh `pi` (it carries `sendMessage`/`sendUserMessage`).
3. **So `messageApi` SHOULD be re-armed to a working, non-stale `pi` on every
   replacement.** The reverted fix's premise (that the factory `pi` is a single
   stale object) was wrong — a fresh `pi` is handed over each time.
4. **The replacement ordering is:** `session_shutdown` (old) →
   `clearStaleContexts` (nulls `messageApi`) → `_buildRuntime` (factory
   re-invoked, `bindApi(freshPi)` re-arms) → `session_start` (new). There is a
   **null window** between `clearStaleContexts` and `bindApi` where
   `messageApi` is null.

### The unresolved ambiguity (blocks fix direction)

Given (2)+(3), `messageApi` should be a fresh working `pi` after any
replacement. Yet the operator still hits the stale error, THEN "not bound
yet". Two surviving hypotheses, and I cannot disambiguate without live-process
inspection (the sandbox can't see the running pi):

- **(A) Race in the null window.** A phone message arrives between
  `clearStaleContexts` (null) and `bindApi` (re-arm). The first message after
  the *prior* replacement hit the old-now-stale `pi` (stale error), `wakeAgent`'s
  `forget()` nulled `messageApi`, and a second message in the null window got
  "not bound yet". The fix would be a guard + retry, not a re-arm.
- **(B) The fresh `pi` is itself going stale faster than expected** — e.g. a
  second replacement (peer `/new` in same CWD) fires before the first re-arm
  lands, or the operator's "peer session in same CWD" is a *separate process*
  whose room-claim invalidates this one's runner via the relay
  (`RoomAlreadyOpenError` path). Needs the live process state.

This is the one question that must be answered before designing the fix —
and it needs either live-process instrumentation or a repro with logging,
not more static reading.

## CORRECTED root cause (2026-07-03, after operator disambiguation)

Operator confirmed: pi was **idle**, the "peer session in the same CWD" was a
**separate pi process**, timing unsure. This is **NOT the single-process
`messageApi`-rearm problem** the reverted fix and the SDK investigation above
were chasing. It is a **multi-instance identity/room collision**:

1. **Shared identity.** The Ed25519 identity is per-MACHINE
   (`pairing/storage.ts`: keyring service `dev.remotepi.pi` / account
   `longterm-ed25519`, with file fallback `~/.pi/remote/identity.json`). Two pi
   processes on the same host share the same private key → same `owner_pk`.
2. **Shared room.** The relay room is derived from the CWD. Two pis in the same
   CWD derive the same `room_id`.
3. **Relay accepts duplicates.** The relay does NOT emit `room_already_open`
   (that error code is dead — never emitted relay-side). `PeerRegistry`
   explicitly allows multiple conns at the same `(peer, room)` to coexist
   (`registry.rs:355` test `duplicate_room_accepted_and_broadcast`), designed
   for multi-device owners sharing a key.
4. **Fanout to ALL conns.** Data-plane forwarding is keyed by `(owner_pk,
   room_id)` and **every live conn receives a copy** (`registry.rs:33`:
   "Every live conn in the corresponding Vec receives a copy"). So when the
   phone sends `user_message` to `(owner_pk, room)`, the relay delivers it to
   **both** pi processes.
5. **The idle/wrong pi errors.** The phone's message was meant for the active
   test pi, but the idle pi (e.g. the coding-agent's session, whose ctx may
   have been replaced by harness `/new`/`/resume` during work) also receives
   it, runs `wakeAgent` → `sendUserMessage` on a stale `messageApi`, throws →
   `internal_error` to the phone. The active pi may handle it fine, but the
   phone sees the stale error from the idle one.

So the symptom is real, but the cause is **cross-process message delivery to a
pi that wasn't the intended target and has a stale ctx**, not a single-process
binding that needs re-arming. The reverted fix was solving the wrong problem
for this scenario (though the single-process re-arm question it raised is
still valid for the TUI-`/reload`-then-phone case — now a secondary concern).

## Design decisions

- **Primary fix direction: the idle/wrong pi must NOT error visibly when it
  receives a `user_message` it wasn't the intended target of.** Two sub-angles:
  - **(P1) Session-gate the delivery.** `_routeClientMessageFrom` already
    validates `session_id` via `validateClientSession`. A `user_message` whose
    `session_id` doesn't match this pi's current session should be rejected
    *silently* (or with a benign no-op), not delivered via `wakeAgent` to a
    stale ctx. Confirm whether `user_message` carries a `session_id` and
    whether the gate already covers it; if the gate passes but `messageApi`
    is stale, the delivery attempt itself is the bug.
  - **(P2) Stale-ctx tolerance on the wake path.** If `wakeAgent` returns
    stale, return a *recoverable* signal (or a silent drop) instead of
    `internal_error`, so a duplicate-delivered message on the wrong pi
    doesn't surface a broken UX. This is the "stopgap" from the original
    brief, now promoted to the primary fix for this scenario.
- **Secondary: the single-process re-arm after TUI `/reload`.** Still a real
  gap (the SDK investigation confirmed `bindApi` re-arms a fresh `pi` on every
  replacement, so this may already be handled — but an idle pi whose ctx was
  replaced by the harness is the same stale-ctx surface). Lower priority now;
  fold into P2.
- **Prevention vs tolerance:** preventing two pis on the same identity+room
  (e.g. a second-pi detection that refuses to claim a room already held by
  the same pubkey on this host) is a bigger UX change and may conflict with
  the legitimate multi-device-owner design. **Tolerance (P1/P2) is the
  smaller, correct fix for the reported symptom.**
- **Integration test is still mandatory:** a two-instance simulation (or a
  unit test that delivers a foreign-`session_id` `user_message` to a pi with
  a stale ctx) asserting no visible `internal_error`.

## What the reverted fix got right/wrong

- WRONG: it assumed the factory `pi` is a single stale object (it's re-created
  per replacement) and that re-arming from it would help (it re-arms a fresh
  one already via `bindApi`). For the *operator's actual scenario* it was
  irrelevant — the problem is cross-process fanout, not single-process binding.
- The crash-class siblings (`resolveRemoteSessionId`, `wrapActionCtx`) ARE
  still correct and deployed — those are unguarded getter reads, unrelated to
  this scenario.

## Design decision (final, 2026-07-03)

**Fix = P2: stale-ctx tolerance on the wake path.** When `wakeAgent` returns
stale (or "not bound yet" in the immediate aftermath), `_deliverUserMessage`
must NOT surface `internal_error` to the phone. The message is either
re-deliverable (the phone retries after the next `session_start` rebinds) or
it was a duplicate to a pi that wasn't the target — in both cases a visible
broken UX is wrong. This single change covers:

- the operator's reported scenario (stale ctx on an idle/wrong pi, whatever
  the source of staleness), and
- the same-process TUI-`/reload`/harness-`/new` case (P2 is the union of the
  prior "stopgap" and "primary fix").

P1 (session-gate) already rejects foreign-`session_id` messages as
`session_mismatch` *before* `wakeAgent` — confirmed `user_message` is
session-scoped and gated (`session_scope.ts`, `index.ts:_routeClientMessageFrom`).
So the stale error must come from a pi whose `currentRemoteSessionId` *matched*
the phone's `session_id` (same-session, ctx replaced in-process) — which P2
covers. No P1 change needed.

**Prevention** (second-pi-on-same-identity detection) is explicitly out of
scope for this feature — it conflicts with the legitimate multi-device-owner
design and is a larger UX change. Tolerance is correct and small.

## Implementation units

### Unit 1: stale/no-op tolerance in `_deliverUserMessage`
**File**: `pi-extension/src/index.ts` (`_wakeAgent` ~L1859, `_deliverUserMessage`)
**Story**: `feature-session-stable-message-delivery-stale-wake-tolerance`

Change `_wakeAgent`'s stale-error handling: instead of returning
`{ok:false, detail}` (which `_deliverUserError` turns into `internal_error`),
distinguish a *stale* failure from a *real* delivery failure. On stale:
- Log a debug line (the operator/dev can see it).
- Return a recoverable result so `_deliverUserMessage` sends a **benign no-op**
  (or nothing) rather than `internal_error`.

Decide the wire shape at implement time: (a) send nothing (the phone's
existing send-timeout will surface "not delivered" — acceptable, but noisy),
or (b) reuse/extend the existing `error` with a recoverable code the app
treats as "retry, not broken" (cleaner; may need an app-side change — scope
that as a child if needed). Prefer (b) only if the app already has a retry
path; otherwise (a) + document.

**Acceptance Criteria**:
- [ ] A `wakeAgent` stale-ctx failure does NOT produce a visible
  `internal_error: Agent rejected incoming message` on the phone.
- [ ] A non-stale wake failure (real delivery error) still surfaces.
- [ ] Regression test: deliver a `user_message` to a projection with a stale
  `messageApi` → assert no `internal_error` is sent (silent or recoverable).

## Implementation Order
1. Unit 1 (the tolerance fix + regression test).

## Testing

### Unit test: `pi-extension/src/extension.test.ts` (or a new projection test)
- `wakeAgent` with a stale `messageApi` (throws stale) → `_deliverUserMessage`
  sends no `internal_error` (or a recoverable code), logs the stale detail.
- `wakeAgent` with a real error → `internal_error` still surfaces (unchanged).
- `wakeAgent` with null `messageApi` ("not bound yet") → same tolerance
  (the immediate-after-replacement window).

### Integration (stretch): two-instance simulation
- Two `SdkSessionProjection` instances sharing a session id; deliver a
  `user_message` to one whose ctx is stale → no visible error. If too hard to
  simulate against the installed SDK, ship the unit test + an honest note.

## Risks

- **Masking real failures.** Tolerance must distinguish stale/not-bound-yet
  (recoverable) from genuine delivery errors (e.g. malformed content, provider
  down). The SDK runtime owns post-handoff failures (no extension error event
  for them), so the extension only sees handoff-time failures — those split
  cleanly into stale (tolerate) vs not (surface). Low risk if the split is on
  `isStaleContextError` + "not bound yet" detail only.
- **Phone UX on full tolerance.** If we send nothing on stale, the app's 20s
  send-timeout surfaces "not delivered" — which is accurate (the message
  wasn't delivered to *this* pi) but noisy if the other pi handled it. The
  recoverable-code option (b) is cleaner but needs an app change. Pick at
  implement time.

## Foundation-doc impact

If option (b) adds a new recoverable error code, update `PROTOCOL.md`'s error
table. Otherwise none. No skill change needed — the stale-context section of
`pi-extension-typescript/SKILL.md` stays accurate (it already describes the
stale-after-replacement class).

## Foundation-doc impact

Likely updates `PROTOCOL.md` (if a new "session replacing, retry" wire signal
is added, option 3) and possibly the pi-extension skill
(`.agents/skills/pi-extension-typescript/SKILL.md`) stale-context section if
the binding model changes. No vision/spec/architecture change — this fixes an
existing capability, doesn't introduce a new one.

## References

- Reopened story (reverted fix + corrected root cause):
  `.work/active/stories/story-fix-stale-ctx-messageapi-rearm-on-reload.md`
- Parked backlog (symptom record):
  `.work/backlog/idea-extension-stale-ctx-incoming-message-rejected.md`
- SDK: `core/extensions/loader.js:175-227` (`createExtensionAPI`,
  `sendUserMessage` → `runtime.assertActive()` first).
- SDK: `core/agent-session.js:2541` (`createReplacedSessionContext` — the only
  session-bound `sendUserMessage`).
- SDK: `core/agent-session-runtime.js:117-125` (`finishSessionReplacement` /
  `withSession`); `:1984` (`/reload` emits `session_start` without
  `session_shutdown`).
- `pi-extension/src/session/sdk_session_projection.ts` — `wakeAgent`,
  `forget`, `bindSessionContext`, `messageApi`, `bindApi`.
- `pi-extension/src/index.ts:1859-1873` (`_wakeAgent`),
  `:1966-1975` (`_sendDeliveryError`).
- Parked mobile recovery: `.work/backlog/idea-mobile-restart-pi-session-affordance.md`.
- Skill: `.agents/skills/pi-extension-typescript/SKILL.md` (stale-context rules).
