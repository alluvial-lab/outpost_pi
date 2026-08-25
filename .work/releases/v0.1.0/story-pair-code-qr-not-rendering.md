---
id: story-pair-code-qr-not-rendering
kind: story
stage: done
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-10
---

# /remote-pi pair shows "QR ready" but no QR code / pairing code printed

## Brief

After the relay-auth-signing fix (extension now signs
`remote-pi-relay-auth-v1\n` ++ nonce), `/remote-pi pair` reaches the
pair-code send and the "QR ready" notify fires, but **no QR ASCII or pairing
code text appears in the pi TUI.** The relay is connected (authenticated) and
`showPairQr` reaches the `sendPiMessage({customType:"remote-pi:pair-code",
display:true})` call — the message just doesn't render.

## Reproduction

1. relay-0.2.0 deployed + extension dist rebuilt with the auth-prefix fix.
2. Fresh pi start; `/remote-pi` connects relay (footer shows 🟢 connected).
3. `/remote-pi pair` → "QR ready — valid until …" notify appears, but the
   expected `📱 Scan to pair:\n\n<ascii QR>\n📋 Or copy…` block is absent.

## Root cause (verified)

`SdkSessionProjection.bindSessionContext(ctx)` called
`replaceSessionCapabilities(ctx)`, which **unconditionally** sets
`messageApi = isAgentMessageApi(ctx) ? ctx : null`. The `ExtensionContext`
that Pi emits with `session_start` (built by
`ExtensionRunner.createContext()` in the SDK — verified in
`node_modules/.../core/extensions/runner.js`, `emit()` → `createContext()`)
carries `ui`/`cwd`/`abort`/`compact`/`sessionManager`/`model` but **NOT**
`sendMessage`/`sendUserMessage`. Only `ExtensionAPI` (the factory `pi`) and
`ReplacedSessionContext` (the `withSession` ctx after `newSession`/`fork`/
`switchSession`) carry the message methods (verified in
`core/extensions/types.d.ts` + `loader.js` `createExtensionAPI`).

So on every `session_start` — **including startup** — the valid `messageApi`
armed at factory init by `bindApi(pi)` was nulled. `sendPiMessage()` then
returned `false`, and `_sendPiMessage` logged
`[remote-pi] pair-code: Pi rejected message: agent session not bound yet`
while silently dropping the QR render. This matches the symptom and the
predicted error message in the brief's "most likely cause."

### Why the existing suite didn't catch it

The `session_start replacement contexts …` test (`extension.test.ts:1957`)
mocked the `session_start` ctx **with** `sendMessage`/`sendUserMessage`
attached — which does not match the real SDK behavior. That false-green hid
the regression. The pre-split `bindSessionContext` used the additive
`bindCapabilities` (only rebinds when the value actually carries the message
API), so a realistic ctx was a no-op and the `pi`-armed binding survived.
Commit `e057ab2` ("…sdk-session-projection-module-step-3") introduced
`replaceSessionCapabilities` for `bindSessionContext`, regressing it.

### Lifecycle grounding (why additive is correct across all paths)

- `staleMessage` is a one-way latch (never cleared) in the SDK runtime — once
  a `pi`/runner is invalidated it stays dead.
- On `/new`/`/resume`/`/fork`/`/reload`, Pi builds a fresh `ExtensionRunner`
  + fresh `runtime` + re-runs the extension factory → a fresh `pi` re-arms
  `bindApi(pi)`. `session_shutdown`→`clearStaleContexts` (which nulls) runs
  *before* the factory re-arms, so there is no stale-`pi` leak.
- `session_start` always emits with `createContext()` (no `sendMessage`),
  never a `ReplacedSessionContext`. So additive rebind is safe.
- `bindReplacementContext` (the `withSession` path driven by the app
  `session_new` action) still calls `replaceSessionCapabilities` to drop the
  stale `pi` and bind the fresh `ReplacedSessionContext`. Unchanged.

## Fix

`pi-extension/src/session/sdk_session_projection.ts` — `bindSessionContext`
now uses the additive `bindCapabilities(ctx)` (the pre-split behavior) instead
of `replaceSessionCapabilities(ctx)`. It only rebinds `messageApi` when the ctx
actually carries the message API (a `ReplacedSessionContext`), otherwise
preserves the `pi`-armed binding. `bindReplacementContext` is unchanged.

```diff
  bindSessionContext(ctx: ExtensionContext): void {
    this.eventCtx = ctx;
-   this.replaceSessionCapabilities(ctx);
+   this.bindCapabilities(ctx);
  }
```

A 7-line inline comment explains the load-bearing reason (which ctx shapes
carry `sendMessage`, and why replacing would null the factory-armed binding).

## Test

New regression test `pi-extension/src/session/sdk_session_projection.test.ts`
pins the contract against a **realistic** `session_start` ctx (no
`sendMessage`/`sendUserMessage`):

- `bindApi(pi)` arms `messageApi`; a realistic `session_start` must NOT null
  it; `sendPiMessage` returns true and `pi.sendMessage` is called.
- `isAgentMessageApi` is false for a realistic session_start ctx.
- `bindSessionContext` with an `AgentMessageApi`-shaped ctx (a
  `ReplacedSessionContext`) still rebinds to it.

## Verification

- `corepack pnpm exec vitest run src/session/sdk_session_projection.test.ts`
  → 3 passed (was 1 failed before the fix).
- `corepack pnpm exec vitest run src/extension.test.ts` → 167 passed; the
  same 2 pre-existing `listenerCount("message")` failures occur with and
  without this change (unrelated env/timing drift; confirmed by stashing).
  The `session_start replacement contexts …` test still passes.
- `corepack pnpm typecheck` → clean.
- `corepack pnpm build` → `dist/session/sdk_session_projection.js` rebuilt
  with the additive fix (verified in compiled output).

## Operator verification (live)

The fix is in `dist/`. Per AGENTS.md, `/reload` does NOT re-`require`
`dist/index.js` — a source edit only takes effect after a **full pi process
restart**. After restart, re-run `/remote-pi pair`; the
`📱 Scan to pair: …` QR block + pairing code should now render in the TUI,
and the `[remote-pi] pair-code: Pi rejected message: agent session not bound
yet` error should no longer fire.

## Files

- `pi-extension/src/session/sdk_session_projection.ts` — `bindSessionContext`
  fix + explanatory comment.
- `pi-extension/src/session/sdk_session_projection.test.ts` — new regression
  test (realistic session_start ctx).

## Context

Full debugging arc in `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`.
This was the last open issue blocking phone pairing (app APK is built and ready
to sideload once the QR renders).
