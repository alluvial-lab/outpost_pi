---
id: story-fix-stale-ctx-wrapactionctx-crash
kind: story
stage: done
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-03
updated: 2026-07-10
implemented: 2026-07-03
---

# Fix: stale-ctx crash in `wrapActionCtx` (unguarded `modelRegistry` getter) on inbound app action

## Observed

Pi exited with an uncaught exception while the operator tested the
resume-backfill fix from the phone:

```
pi exiting due to uncaughtException:
Error: This extension ctx is stale after session replacement or reload…
    at ExtensionRunner.assertActive (runner.js:331)
    at get modelRegistry (runner.js:436)
    at SdkSessionProjection.wrapActionCtx (sdk_session_projection.js:552)
    at SdkSessionProjection.freshActionCtx (sdk_session_projection.js:438)
    at _routeClientMessageFrom (index.js:1892)
    at onMessage (index.js:215)
    at OwnerMultiplexer.routeFrom (owner_multiplexer.js:302)
    at PlainPeerChannel._onLine (peer_channel.js:102)
```

A phone-origin action routed through `_routeClientMessageFrom` →
`freshActionCtx()` → `wrapActionCtx(ctx)`, which accessed `ctx.modelRegistry`
(a guarded SDK getter that calls `assertActive()`). The captured
`eventCtx`/`commandCtx` was stale after a session replacement, so the getter
threw the stale-context error **synchronously and uncaught** — propagating
through the relay message router and crashing the whole pi process.

## Root cause (confirmed)

`wrapActionCtx` wrapped the *invocation* of `compact`/`newSession`/`getModel`
in try/catch (calling `forgetStaleBinding` on a stale error), but the
**property accesses themselves** — `typeof ctx.compact === "function"`,
`ctx.modelRegistry`, etc. — happen OUTSIDE any try/catch. The SDK marks every
guarded getter on a replaced ctx to throw via `assertActive()`
(`runner.js:330-333`, `429-441`), so reading any of them on a stale ctx throws
synchronously. Since `wrapActionCtx` is called synchronously from the message
router (`onMessage` → `routeFrom`), the throw was uncaught and took pi down.

Distinct from `idea-extension-stale-ctx-incoming-message-rejected` — that's
the `wakeAgent`/`sendUserMessage` path, which is caught and surfaces a
graceful `internal_error` to the phone. This is a **different surface**
(`wrapActionCtx` → `modelRegistry`) that was **uncaught and crashed pi**.
Higher severity (process loss vs. dropped message).

## Fix

`wrapActionCtx` now wraps the whole property-access sequence in a try/catch.
On a stale-context error it calls `forgetStaleBinding(ctx)` and returns
`null` (callers `freshActionCtx`/`freshCommandActionCtx` already return
`ActionCtx | null`, and the action handlers turn null into a graceful
`action_error` like "compact unavailable (no active session ctx)" via
`runAsync`/`runSync`). Non-stale errors still propagate. So a stale ctx now
degrades a single app action to an `action_error` instead of crashing pi.

`pi-extension/src/session/sdk_session_projection.ts` — `wrapActionCtx`
signature changed to `ActionCtx | null`; all callers already handled null.

## Regression tests

3 new tests in `SdkSessionProjection stale-ctx crash guard on freshActionCtx`:
1. `freshActionCtx` on a stale event ctx returns null instead of throwing.
2. `freshCommandActionCtx` on a stale command ctx returns null instead of throwing.
3. A non-stale error from the getters still propagates (guard is stale-specific).

## Verification

- `corepack pnpm typecheck` — clean.
- `corepack pnpm test` — 732 pass, 3 pre-existing skips, 0 regressions.
- `corepack pnpm build` — clean, `dist/index.js` rebuilt.

## Not deployed

Needs a full pi process restart to pick up the rebuilt `dist/` (the parked
`idea-mobile-restart-pi-session-affordance` is the mobile-path blocker).

## Relationship to the resume-backfill work

The crash is a **pre-existing latent bug** (the unguarded `modelRegistry`
access predates the backfill change), but the resumed-session scenario made
it triggerable: with history now backfilled, the phone interacts with a
resumed session, and if a `/new`/`/reload`/replacement left a stale
`eventCtx`/`commandCtx`, the next inbound action crashed pi through this
surface. Surfaced during operator testing of
`story-mobile-chat-blank-on-pair-after-pre-pair-work`.

## References

- `pi-extension/src/session/sdk_session_projection.ts` — `wrapActionCtx`,
  `freshActionCtx`, `freshCommandActionCtx`, `forgetStaleBinding`.
- `pi-extension/src/index.ts:2137,2140,2184,2202` — `freshActionCtx`/
  `freshCommandActionCtx` call sites on inbound actions.
- SDK: `runner.js:330-333` (`assertActive`), `:429-441` (guarded getters).
- Related: `.work/backlog/idea-extension-stale-ctx-incoming-message-rejected.md`
  (graceful sibling on the `sendUserMessage` path — still open).
- Surfaced by: `.work/active/stories/story-mobile-chat-blank-on-pair-after-pre-pair-work.md`.
