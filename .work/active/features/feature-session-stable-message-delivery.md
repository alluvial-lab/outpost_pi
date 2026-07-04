---
id: feature-session-stable-message-delivery
kind: feature
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on:
  - story-fix-stale-ctx-messageapi-rearm-on-reload
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-03
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

## Design decisions

- **Fix direction: deferred pending (A)/(B) disambiguation.** The design
  cannot proceed until we know whether this is a null-window race (fix = guard
  + retry) or a multi-replacement/stale-runner case (fix = re-capture or
  process-model). Captured here so the next pass inherits the constraint.
- **Integration test is mandatory** regardless of direction: a real
  `ctx.newSession()` through the SDK `ExtensionRunner` asserting delivery to
  the new session. Mock-based tests cannot catch this class (the reverted fix
  proved it).
- **Stopgap is acceptable interim:** a graceful "session replacing, retry"
  signal instead of `internal_error` so the phone stops going permanently
  broken while the real fix is designed. Pairs with
  `idea-mobile-restart-pi-session-affordance`.

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
