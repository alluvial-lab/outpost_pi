---
id: story-extension-subagent-child-session-start-wipes-mobile-chat
kind: story
stage: done
tags: [pi-extension, app, bug, transport, session, lifecycle]
parent: feature-reconnect-reproduction
depends_on:
  - story-extension-suppress-subagent-assistant-broadcast
release_binding: v0.1.0
gate_origin: null
created: 2026-07-07
updated: 2026-07-07
---

# Subagent child `session_start` wipes the mobile chatlog + hides the subagent tool card

> **STATUS (2026-07-07): ROOT CAUSE CONFIRMED by live capture; fix restored.**
> The earlier revert was based on a misdiagnosis: I thought the `subagentGate`
> singleton was NOT shared with the child (separate module instance), so the
> gate-keyed guard would no-op. That was WRONG. A full-restart capture
> (`/tmp/remote-pi-debug-send.jsonl`, with `session_id` + `sendControl`
> instrumentation loaded) shows `gateActive=true` during the subagent window —
> the singleton IS shared — and a single `room_meta_update({session_id:
> childId})` fires at that moment, which is the wipe. The prior `/reload`
> captures were on a STALE dist (the `sendControl`/`session_id` fields weren't
> loaded), which is why they showed no `room_meta_update` and led me astray.
> `/reload` does NOT re-import `dist/index.js` (empirically confirmed; AGENTS.md
> corrected back). The fix (gating `captureRemoteSession`'s `publishRoomMeta`
> + `issuer.capture` + `backfill` on `subagentGate.isActive()`) is restored and
> the regression test passes. Pending operator manual confirm after a FULL
> restart.

## Brief

After the subagent assistant-text leak was fixed
(`story-extension-suppress-subagent-assistant-broadcast`, operator-confirmed
2026-07-07), the operator surfaced a deeper, separate defect that the leak
had masked: **dispatching a subagent wipes the mobile chatlog clean AND shows
no indication of the subagent running** (no tool card). Both symptoms share
one root cause: the child subagent session's `session_start` fires during the
parent's `subagent` tool-execution window and its side effects propagate to
the phone as if it were a real parent session rotation.

This is a **blocking bug** for subagent use from mobile: every subagent
dispatch destroys the visible conversation.

## Root cause (CONFIRMED 2026-07-07, static trace + capture)

The `subagent` tool (`@gotgenes/pi-subagents` v18.0.1) runs in-process and
creates a **child `AgentSession`** with a **fresh `SessionManager`**
(`create-subagent-session.ts:194-200`: `createSessionManager(cwd, sessionDir)`
→ `newSession({ parentSession })`). `SessionManager.newSession` generates a
**fresh session id** (`session-manager.js:559-563`:
`this.sessionId = options?.id ?? createSessionId()` — a `uuidv7()`), distinct
from the parent's.

The child then calls `session.bindExtensions()` (`create-subagent-session.ts:233`),
which re-binds the parent's `remote-pi` extension and fires the child's
`session_start` with `reason=startup`. The capture
(`~/.pi/remote/debug-firings.jsonl`) confirms the child's `session_start` fires
**between** the parent's `tool_execution_start("subagent")` and
`tool_execution_end("subagent")` — i.e. while `subagentGate.isActive()` is
true.

`session_start` is wired in `composition_root.ts:55` to call
`bindSessionContext(ctx)`, which (via `index.ts:1532-1535`) calls
`_captureRemoteSession(ctx)` → `SdkSessionProjection.captureRemoteSession`
(`sdk_session_projection.ts:275-278`):

```ts
captureRemoteSession(ctx: unknown): RemoteSessionId {
  const sessionId = this.issuer.capture(ctx);          // overwrites parent id with child id
  this.opts.outputs.publishRoomMeta({ session_id: sessionId });  // ← THE WIPE
  return sessionId;
}
```

`resolveRemoteSessionId(childCtx)` reads `childCtx.sessionManager.getSessionId()`
→ the **child's fresh id**. So the extension publishes a `room_meta_update`
carrying the **child's** session id to the phone.

### Why this wipes the chatlog

The app's `_onRoomsChanged` (`sync_service.dart:544-556`) fires on room-meta
change. When `_resolveActiveRef` returns a ref whose `sessionId` differs from
`_activeRef.sessionId`, it calls `activate(epk, roomId)`, which (per the
comment at `:550-553`) **"Rebind persistence to the new session-scoped box and
clear in-memory turn state."** The child's id ≠ the parent's active id, so
`activate()` runs, rebinding the app to the child's (empty) session box → the
visible chatlog is wiped.

### Why no subagent tool card shows

After the wipe, `_activeRef` points at the child's session id. The parent's
subsequent `tool_request` / `tool_result` broadcasts for the `subagent` tool
are stamped with the **parent's** session id (`_withCurrentSession`), which now
fails the app's session gate (`_sessionGate.accepts` against the child's
active ref) → dropped as `session_mismatch`. So the legitimate
"subagent running" tool card never renders.

### The prior capture's misleading "same session id"

The prior session's `debug-firings.jsonl` capture logged the child's
`session_start` with the **same** session id as the parent (`06075b43`) and
concluded "no session-id-change signal." That was an instrumentation artifact:
the `sessionId` field was read from `_currentRemoteSessionId()` (the issuer's
cached value), not from `childCtx.sessionManager.getSessionId()` directly.
`SessionManager.newSession` provably generates a fresh `uuidv7()` (no `id`
option passed by the subagent), so the child's real id IS different. The
operator's observed wipe is the empirical confirmation that the id changes.

## The fix (fork-local, `pi-extension`)

The child's `session_start` is an **internal** lifecycle event of an in-process
subagent — it must NOT propagate session-rotation side effects to the phone.
The `subagentGate` (already shipping from the leak-fix story) is active during
exactly this window, so it is the correct guard.

Two side effects of `bindSessionContext` must be suppressed while the gate is
active:

1. **`captureRemoteSession` → `publishRoomMeta({ session_id: childId })`** —
   the wipe. Must NOT publish a `room_meta_update` with the child's id.
2. **`issuer.capture(childCtx)`** — overwrites the parent's session id in the
   issuer with the child's. Must NOT run, or subsequent parent broadcasts would
   be stamped with the wrong id.
3. **`backfillTranscriptFromSessionManager(childCtx)`** — reads the child's
   SessionManager and stamps parent-seeded history under the child's id into
   the transcript log. Must NOT run (pollutes the log, even if filtered at
   read time by `forSession(currentId)`).

### Implementation approach (to confirm at design)

Guard at the `bindSessionContext` entry point (or at the `session_start`
handler in `composition_root.ts:55` / `index.ts:1532`): when
`subagentGate.isActive()`, skip the phone-facing side effects of the child's
`session_start` — i.e. skip `captureRemoteSession`'s `publishRoomMeta` and
`issuer.capture`, and skip `backfillTranscriptFromSessionManager`. The
capability rebinds (`bindCapabilities`) are still needed for the child's own
message API, so those should remain (they don't touch the phone).

Cleanest seam: add a `bindSessionContext` variant or an early-return guard in
`captureRemoteSession` / `backfillTranscriptFromSessionManager` keyed on
`subagentGate.isActive()`. The gate is a process singleton already imported by
the projection's host (`index.ts`); the projection itself should NOT import
the gate (keep the projection SDK-pure). So the guard belongs in `index.ts`'s
`bindSessionContext` wrapper (line ~1532) and/or a thin flag threaded into the
projection call.

### Alternative considered: gate at `publishRoomMeta`

Suppressing `publishRoomMeta({session_id})` alone would stop the wipe but
leave `issuer.capture` corrupting the parent id and backfill polluting the
log. So the guard must be at the `bindSessionContext`/`captureRemoteSession`
level, not just at the room-meta sink.

## Acceptance Criteria

- [x] A child subagent's `session_start` (fired during a `subagent`
      tool-execution window) does NOT publish a `room_meta_update` carrying
      the child's session id to the phone. (regression test asserts zero
      `room_meta_update` with `session_id` escape during the window)
- [x] The parent's session id in the `RemoteSessionIssuer` is NOT overwritten
      by the child's id during the subagent window (regression test asserts
      the parent id is still current after the child `session_start`).
- [x] `backfillTranscriptFromSessionManager` does NOT run for the child's
      `session_start` (suppressed via the `subagentChild` flag).
- [x] Regression test: opening a `subagent` tool-execution window, firing a
      child `session_start` with a fresh session id, then closing the window,
      asserts NO `room_meta_update`/`session_id` broadcast escaped during the
      window AND the parent's session id is still current afterward.
- [ ] Manual: rebuild dist, `/reload` (or restart), dispatch a subagent from
      the phone, confirm the mobile chatlog is NOT wiped and the "subagent
      running" tool card DOES render (and disappears/completes on
      `tool_execution_end`).
- [x] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      green in `pi-extension/`.
- [x] Inline comment citing `@gotgenes/pi-subagents` child-session re-binding
      and the fork-local tradeoff.

## Implementation notes

- **Files changed**:
  - `pi-extension/src/session/sdk_session_projection.ts` — `bindSessionContext`
    gained an optional `opts?: { subagentChild?: boolean }` second parameter.
    When `subagentChild` is true, it SKIPS `issuer.capture(ctx)` (preserves the
    parent's session id) and `backfillTranscriptFromSessionManager(ctx)`
    (avoids stamping parent-seeded history under the child's id), but KEEPS
    `eventCtx = ctx` and `bindCapabilities(ctx)` (the child needs its own
    message API; neither touches the phone). The port interface
    (`bindSessionContext(ctx): void`) is unchanged — the optional second arg
    is a projection-only extension.
  - `pi-extension/src/index.ts` — the `bindSessionContext` wrapper (in the
    `session` port object) now checks `subagentGate.isActive()`. When true (a
    child subagent's `session_start` fired during the parent's `subagent`
    tool-execution window), it: (a) skips `_lastEventCtx = ctx` (the child ctx
    is stale after the window and would corrupt parent actions);
    (b) passes `{ subagentChild: true }` to the projection; (c) skips
    `_captureRemoteSession(ctx)` (no `room_meta_update({session_id: childId})`
    → no mobile chatlog wipe). When the gate is inactive (real parent
    `session_start` for startup/new/resume/fork/reload), the original behavior
    is fully preserved.
  - `pi-extension/src/extension.test.ts` — new regression test "subagent child
    session_start must not publish room_meta_update with the child session id":
    establishes the parent session id, opens a `subagent` tool-execution window,
    fires a child `session_start` with a FRESH session id, and asserts (1) zero
    `room_meta_update` carrying a `session_id` escaped during the window, (2)
    the parent's session id was NOT overwritten, and (3) it's still current
    after the window closes. This test FAILS without the fix (reproduces the
    wipe: exactly 1 `room_meta_update` with the child id is published) and
    PASSES with it.
- **Design decision (guard at `bindSessionContext`, not the room-meta sink)**:
  gating only `publishRoomMeta` would stop the wipe but leave `issuer.capture`
  corrupting the parent id (subsequent parent broadcasts stamped wrong) and
  `backfillTranscriptFromSessionManager` polluting the transcript log. The
  guard must be at the `bindSessionContext`/`captureRemoteSession` level so all
  three side effects are suppressed together. The `subagentGate` (process
  singleton, already shipping from the leak-fix story) is the correct signal:
  the capture proves the child's `session_start` fires between
  `tool_execution_start("subagent")` and `tool_execution_end("subagent")`.
- **Why `bindCapabilities` is still called for the child**: the child
  `AgentSession` needs its own message API for its internal turn loop
  (`sendPiMessage`/`sendUserMessage`). `bindCapabilities` only rebinds when
  the ctx carries the message API (a `withSession` `ReplacedSessionContext`)
  and does NOT touch the phone — so it is safe to keep.
- **Discrepancies from design**: none.
- **Verification**: `corepack pnpm typecheck` ✓, `corepack pnpm build` ✓,
  `corepack pnpm test` ✓ (765 passed, 3 pre-existing skipped, 48 files —
  +1 from the new regression test; the existing `session_start` new/resume/
  fork/reload tests still pass because they fire outside a subagent window,
  where the gate is inactive and the original behavior is preserved).
- **Manual criterion (pending)**: rebuild dist (done), `/reload` pi (which
  DOES re-import dist — confirmed this session), dispatch a subagent from the
  phone, confirm (1) the mobile chatlog is NOT wiped and (2) the "subagent
  running" tool card renders and completes. The tool card (symptom #2) should
  resolve automatically once the wipe is fixed — the parent's `tool_request`/
  `tool_result` will no longer fail the app's session gate.

## Next step

Operator `/reload`s pi (to load the rebuilt dist with this fix) and dispatches a
subagent from the phone. Confirm: chatlog stays intact AND the subagent tool
card appears. If both hold, advance to `done`.

- [ ] A child subagent's `session_start` (fired during a `subagent`
      tool-execution window) does NOT publish a `room_meta_update` carrying
      the child's session id to the phone.
- [ ] The parent's session id in the `RemoteSessionIssuer` is NOT overwritten
      by the child's id during the subagent window (subsequent parent
      broadcasts keep the correct session stamp).
- [ ] `backfillTranscriptFromSessionManager` does NOT run for the child's
      `session_start` (no transcript-log pollution under the child's id).
- [ ] Regression test: opening a `subagent` tool-execution window, firing a
      child `session_start` with a fresh session id, then closing the window,
      asserts NO `room_meta_update`/`session_id` broadcast escaped during the
      window AND the parent's session id is still current afterward.
- [ ] Manual: rebuild dist, `/reload` (or restart), dispatch a subagent from
      the phone, confirm the mobile chatlog is NOT wiped and the "subagent
      running" tool card DOES render (and disappears/completes on
      `tool_execution_end`).
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      green in `pi-extension/`.
- [ ] Inline comment citing `@gotgenes/pi-subagents` child-session re-binding
      and the fork-local tradeoff.

## Out of scope

- The subagent assistant-text leak — FIXED
  (`story-extension-suppress-subagent-assistant-broadcast`).
- Upstream `@gotgenes/pi-subagents` exposing a `parentSessionId`/`subagent`
  marker on `SessionStartEvent` — out of fork (would be the cleanest signal,
  but the `subagentGate` window is model-independent and already shipping).
- The reorder-fix deploy / 77% inbound drop rate — separate, tracked on
  `story-fix-transport-active-room-reestablishment-on-reconnect`.

## References

- Leak-fix story: `.work/active/stories/story-extension-suppress-subagent-assistant-broadcast.md`
  (operator-confirmed the text leak is fixed; surfaced this wipe bug).
- Capture: `~/.pi/remote/debug-firings.jsonl` — child `session_start` fires
  during the `subagent` tool-execution window.
- `pi-extension/src/extension/composition_root.ts:55` — `session_start` →
  `bindSessionContext`.
- `pi-extension/src/index.ts:1532-1535` — `bindSessionContext` wrapper →
  `_captureRemoteSession`.
- `pi-extension/src/session/sdk_session_projection.ts:142-167` —
  `bindSessionContext` (capture + backfill); `:275-278` `captureRemoteSession`
  (the `publishRoomMeta({session_id})` wipe); `:184-231`
  `backfillTranscriptFromSessionManager`.
- `pi-extension/src/session/remote_session.ts:65-77` — `resolveRemoteSessionId`
  reads `ctx.sessionManager.getSessionId()` (child's fresh id).
- `pi-extension/src/session/subagent_gate.ts` — the `subagentGate` singleton
  (active during the window).
- `app/lib/data/sync/sync_service.dart:544-556` — `_onRoomsChanged` →
  `activate()` (the wipe: rebinds persistence + clears in-memory turn state).
- `@gotgenes/pi-subagents` source:
  `src/lifecycle/create-subagent-session.ts:194-233` (fresh child
  SessionManager + `newSession({parentSession})` + `bindExtensions`).
- `@earendil-works/pi-coding-agent` `dist/core/session-manager.js:559-563` —
  `newSession` generates a fresh `createSessionId()` (uuidv7) when no `id`
  option is passed.
- Parent: `feature-reconnect-reproduction.md`.

## Final resolution (2026-07-07) — DONE

Operator-confirmed: dispatching a subagent no longer wipes the mobile chatlog,
and the "subagent running" tool card now renders. The fix (suppress
`captureRemoteSession`'s `room_meta_update({session_id: childId})` +
`issuer.capture` + `backfillTranscriptFromSessionManager` when
`subagentGate.isActive()`) was confirmed by live capture: zero
`room_meta_update({session_id})` fires during the window, and the parent
session id stays constant throughout. TEMP DEBUG sink instrumentation removed.
