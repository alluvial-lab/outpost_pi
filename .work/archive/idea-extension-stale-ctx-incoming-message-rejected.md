---
id: idea-extension-stale-ctx-incoming-message-rejected
status: superseded
superseded_by: feature-session-stable-message-delivery
created: 2026-07-03
updated: 2026-07-24
stage: done
release_binding: v0.3.0
tags: [pi-extension, app, bug, lifecycle]
---

# Phone receives `internal_error: Agent rejected incoming message: …ctx is stale…`

> **REOPENED 2026-07-03.** A first fix (`story-fix-stale-ctx-messageapi-rearm-on-reload`,
> re-arm `messageApi` from a retained factory `pi`) shipped but did NOT fix the
> symptom and was reverted — its premise (that the factory `pi` is
> session-stable) was false. `pi.sendUserMessage` calls `runtime.assertActive()`
> first, which throws stale after a replacement. See that story for the
> corrected root cause and the open design options. The crash-class siblings
> (`resolveRemoteSessionId`, `wrapActionCtx`) ARE fixed and deployed; this
> graceful `internal_error` surface is the one still open.

## Observed

Operator saw, in a live phone session, an error surfaced to the app:

> internal_error: Agent rejected incoming message: This extension ctx is
> stale after session replacement or reload. Do not use a captured pi or
> command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or
> ctx.reload(). For newSession, fork, and switchSession, move post-
> replacement work into withSession and use the ctx passed to withSession.
> For reload, do not use the old ctx after await ctx.reload().

i.e. an inbound user message from the phone was handed to a **stale** Pi
message API and the SDK rejected it; the rejection was relayed back to the
phone as an `internal_error` instead of the message being delivered.

## Grounded path

- `_deliverUserMessage` → `_wakeAgent`
  (`pi-extension/src/index.ts:1859-1873`) calls
  `_sdkSessionProjection.wakeAgent(content)`.
- `wakeAgent` (`src/session/sdk_session_projection.ts:426-440`) calls
  `api.sendUserMessage(...)` on the bound `messageApi`. If it throws a
  stale-context error, `isStaleContextError` catches it, `forget(api)` clears
  the binding, and it returns `{ ok: false, detail: <stale message> }`.
- `_wakeAgent` returns that to `_deliverUserMessage`, which calls
  `_sendDeliveryError` (`src/index.ts:1962-1971`) → emits
  `error { code: "internal_error", message: "Agent rejected incoming
  message: <detail>" }` back to the phone.

So the symptom = a stale `messageApi` binding was still in place when an
incoming user message arrived, and the rebind to a fresh API didn't happen
before the next inbound message.

## Why it's still happening (hypothesis; confirm at design time)

The 0.5.4 stale-context work fixed `session_new`-triggered and
`session_start` recapture paths; the active `story-stale-command-ui-notify-guard`
covers post-await `ctx.ui.notify` (a different surface). Neither covers the
incoming-message delivery path after a TUI-driven `/reload` or `/resume`:

- `bindSessionContext` is **additive** and only rebinds `messageApi` when the
  ctx actually carries `sendMessage`/`sendUserMessage` — i.e. a
  `withSession` `ReplacedSessionContext`, NOT a plain `session_start` ctx
  (`sdk_session_projection.ts:142-160`).
- `clearStaleContexts` (on `session_shutdown`) nulls `_pi` and `_messageApi`
  (`index.ts:1466-1470`), but `bindApi(pi)` is only called at **factory init**,
  not re-called on `session_start`.
- So after a `/reload` (re-fires `session_start` on the same module) or a
  `/resume` not driven through the app's `session_new` action, the
  `messageApi` may remain stale/null until something rebinds it — and an
  inbound phone message that lands in that window is rejected.

Distinct from the 0.5.4 fixes (which targeted `session_new` via `withSession`)
because this is the **TUI-side `/reload`/`/resume`/`/fork`** rebind gap on the
incoming-delivery surface, not the action or notify surfaces.

## Followup at design time

- Reproduce: pair, then in the pi TUI run `/reload` (or `/resume`), then send
  a message from the phone immediately. Confirm the `internal_error` fires
  and whether a *second* phone message succeeds (rebind happened) or also
  fails (rebind never happens).
- Trace which `messageApi` binding threw: the factory `pi` (should be
  process-stable) vs a captured `withSession` ctx. The error text says "captured
  pi or command ctx" — confirm which.
- Decide the rebind fix: re-arm `messageApi` from the factory `pi` on every
  `session_start` (the additive-bind comment explicitly warns this would null
  a valid `withSession` binding on startup — so the fix must distinguish
  startup/reload from a `withSession` rebind), or have `wakeAgent`'s
  stale-recovery trigger an explicit rebind attempt before returning failure.
- Consider whether the phone should get a recoverable "session replacing,
  retry" signal instead of `internal_error` for the narrow rebind window.
- Cross-check `.agents/skills/pi-extension-typescript/SKILL.md` stale-context
  rules and the active `story-stale-action-boundary-regression-tests`.

## References

- `pi-extension/src/index.ts:1859-1873` — `_wakeAgent`.
- `pi-extension/src/index.ts:1962-1971` — `_sendDeliveryError` (error surfacing).
- `pi-extension/src/session/sdk_session_projection.ts:142-160` — additive
  `bindSessionContext` (the rebind gap).
- `pi-extension/src/session/sdk_session_projection.ts:426-440` — `wakeAgent`
  stale catch.
- `pi-extension/src/index.ts:1466-1470` — `clearStaleContexts` nulls `_pi`/`_messageApi`.
- Shipped related: `.work/releases/extension-0.5.4/{story-remote-pi-stale-context-source-fix,story-fix-stale-pi-api-after-app-session-new,story-fix-session-start-message-api-recapture}.md`.
- Active related: `.work/active/stories/story-stale-command-ui-notify-guard.md` (different surface: `ctx.ui.notify`).
- `.agents/skills/pi-extension-typescript/SKILL.md` — stale-context lifecycle rules.
