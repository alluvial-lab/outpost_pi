---
id: story-mobile-chat-blank-on-pair-after-pre-pair-work
kind: story
stage: review
tags: [pi-extension, app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-03
implemented: 2026-07-03
review_addressed: 2026-07-03
confirmed_root_cause: 2026-07-03
---

# Mobile chat renders blank after pairing into a session that did pre-pair work

## Observed

Operator scenario (phone, live relay): do real coding work in a Pi session
*first*, then initiate Remote Pi (relay up), then pair/connect from the phone.
The phone's chat window comes up **blank** — none of the turns that ran before
the phone attached are visible. The user cannot read back through history.

This is a **hydration gap on first attach**, not a re-render glitch: the
history is either never sent on the wire or is rejected on arrival.

## Distinct from

- `idea-mobile-chat-blank-on-tab-return` — that's a Flutter view rehydrate
  bug where the data *is* present and back-out/re-enter fixes it. This is
  the *first* attach after pre-pair work, data absent on the wire.
- `epic-bold-transcript-event-log-hydration-replay` (v0.6.0, done) — made
  hydration replay-idempotent and fail-closed on foreign `session_id`, but
  did not address pre-pair work never entering the replay source.

## Architecture grounding (read before diagnosing)

The replay source is the in-memory `TranscriptEventLog`
(`pi-extension/src/session/transcript_event_log.ts`), owned by
`SdkSessionProjection`. It is **append-only, process-local, and fed only by
live SDK hooks** — `message_end`, `tool_execution_start/end`, `message_update`
(`src/index.ts:1200-1370`). There is **no backfill** from the SDK's durable
`sessionManager` persisted messages on `session_start`/`/resume`; the log only
accumulates events seen while the extension is loaded and listening.

`session_sync` answers from `transcriptLog.forSession(currentRemoteSessionId())`
(`sdk_session_projection.ts:361-374`). Events are filtered by the `sessionId`
stamped on them at hook-fire time via `currentRemoteSessionId()` →
`RemoteSessionIssuer.currentOrCapture(ctx)`. The issuer captures the id in
`bindSessionContext` on **every** `session_start` (startup/new/fork/reload/resume)
via `_captureRemoteSession(ctx)` (`src/index.ts:1451-1454`,
`composition_root.ts:55-60`). `pair_ok.session_id` uses the same
`currentRemoteSessionId` (`_currentPairingSessionSnapshot`, `index.ts:1077`),
so in a stable same-process session the ids should match.

On the app side, `_replayHistory` (`sync_service.dart:1003-1047`) gates replay
on:
- `history.sessionId == key.sessionId` (else silently drop), and
- `_isStaleHistory(history.sessionStartedAt)` — rejects when
  `sessionStartedAt < _acceptedSessionStartedAtHighWater`.

The high-water is reset to `null` in `activate()` but **re-populated from the
persisted `SessionIndexRecord` in `_loadIndex`** (`sync_service.dart:1094-1120`).

`session_started_at` on the extension side is set **lazily at relay start** by
`ensureSessionStarted()` (`_cmdStart`, `index.ts:1743`), i.e. "time `/remote-pi
start` ran", **not** the actual Pi session start time. Pre-pair transcript
events carry their own earlier `ts`.

## Root cause (CONFIRMED 2026-07-03 via SDK source + failing spike test)

The operator's clean single-process repro (Run A) returned **full history** —
so the no-boundary case works. The blank case requires a session boundary,
and the boundary that strands history is **`/resume`** (and `/fork`, `/new`,
reload, daemon respawn — any `session_start` for a session whose persisted
history the SDK loads from disk rather than replays through the agent).

The SDK's `/resume` path loads persisted entries into a fresh
`SessionManager` and renders them **directly to the TUI** via
`renderInitialMessages()` → `sessionManager.buildSessionContext()` — it does
**not** route them through the agent's message pipeline, so **`message_end`
never fires for resumed history**. The extension's `TranscriptEventLog` is
fed only by live SDK hooks (`message_end`, `tool_execution_start/end`,
`message_update`), so on `/resume` the log stays empty and `session_sync`
returns a blank `session_history` even though the TUI shows full history.

The gap is reachable, not architectural: `ctx.sessionManager` is exposed on
the `session_start` ctx (`ExtensionRunner.createContext`, runner.js:431-433),
`getEntries()` is public on `SessionManager` (session-manager.js:889), and
`mapLegacyAgentMessagesToTranscriptEvents` already converts those entries to
transcript events (used today by `setLegacyMessageBufferForTest`).

**Spike test (run then reverted):** added a failing test to
`src/session/sdk_session_projection.test.ts` — a resume-style `session_start`
with persisted entries on `ctx.sessionManager.getEntries()`, then
`buildSessionHistoryMessage` returned `[]` instead of the persisted
events. Confirms the gap at the unit level.

```text
/resume (agent-session-runtime.js switchSession)
  → SessionManager.open(path) loads persisted entries   [history is in memory]
  → session_start {reason:"resume"} fires                 [ctx.sessionManager has it]
  → renderInitialMessages() renders to TUI directly       [message_end does NOT fire]
  → TranscriptEventLog stays empty                        [extension's replay source]
  → session_sync → buildSessionHistoryMessage → []       [phone sees blank]
```

### Rejected/deferred candidates (from the original ranked list)

- **Session-id mismatch after `/reload`** (was #1): `/reload` re-fires
  `session_start` but `clearStaleContexts` does not clear the log — still a
  latent issue, but the *blank* symptom is explained by resume, not reload.
  Reload would strand events under the old id (a different bug: stale-bleed,
  not blank). Keep as a related concern when designing the backfill: the
  backfill must not double-append when events already exist for the id.
- **App-side stale `session_started_at` high-water** (was #2): not the primary
  cause; a wire-empty history can't be rejected as stale. Still worth
  reconciling `session_started_at` semantics (extension reports relay-start
  time via `ensureSessionStarted`, not real session start) as a secondary fix.
- **Transient UUID7 stranding** (was #3): subsumed — on `/resume` the real
  SDK id IS available, yet the log is empty regardless of id. The backfill
  fixes this implicitly.
- **Separate-process daemon** (was #4): a special case of the same root cause
  (fresh process, empty log); the backfill fixes it too.

## Fix shape (confirmed)

Backfill the `TranscriptEventLog` from `ctx.sessionManager.getEntries()` on
`session_start`. Concretely, in `SdkSessionProjection.bindSessionContext`
(`sdk_session_projection.ts:142-160`) — or a dedicated `backfillFromSessionManager`
called right after it from `composition_root.ts:55-56`:

1. Detect when `ctx.sessionManager.getEntries` is present and the transcript
   log is empty (or the session id just changed).
2. Map entries via the existing `mapLegacyAgentMessagesToTranscriptEvents`.
3. `transcriptLog.replace(...)` (dedupe is already handled by `append`/`seen`).

Because the log is the only replay source and is already keyed/deduped by
`eventId`, this also handles `/new` (fresh empty log), `/fork`, daemon respawn,
and `/reload` (existing events survive; the backfill must not duplicate —
`append`'s `seen` set guards this, but `replace` would clobber, so prefer
`appendAll` or gate on emptiness/id-change rather than unconditional replace).

Design decisions to pin at implement time:
- **Replace vs append:** `replace` is wrong if the log already has live
  post-start events (race where a hook fired between `session_start` and the
  backfill). Prefer `appendAll` (dedupe by `eventId`) and only `replace` when
  the log is empty for the new session id.
- **`session_started_at`:** capture the real session start from the
  `sessionManager` header (session-manager.js `getHeader()`) instead of the
  lazy `ensureSessionStarted()` relay-start time, so the app-side stale
  high-water check also becomes correct (fixes the deferred secondary concern).
- **Backfill trigger scope:** only on `session_start` with a fresh session id,
  not on every `bindSessionContext` (which also fires for `withSession`
  replacements that already have live state).

## Verification

- Re-add the spike test (now expected to pass) as a regression:
  resume-style `session_start` with persisted entries → `session_sync`
  returns those entries.
- `/new` after backfill → empty history (no bleed from the prior session).
- `/resume` a session that already has live events in the log → no duplicates.
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`.

## Verification matrix (after fix)

- Fresh pair after 2-3 pre-pair turns → history visible immediately.
- Pre-pair turn including a tool call → tool request + result render.
- `/remote-pi start` then `/new` then pair → only post-new history (no bleed).
- `/reload` then pair → history intact (no blank) or correctly reset per the
  chosen semantics, with a test pinning the chosen behavior.
- Re-pair to a known peer with a prior persisted index → no stale-reject.
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` on
  `pi-extension/`; `flutter analyze && flutter test` on `app/`.

## References

- `pi-extension/src/session/transcript_event_log.ts` — in-memory replay source.
- `pi-extension/src/session/sdk_session_projection.ts:361-389` —
  `buildSessionHistoryMessage` / `forSession` filter / `session_started_at`.
- `pi-extension/src/session/sdk_session_projection.ts:142-160` —
  `bindSessionContext` (additive, no clear).
- `pi-extension/src/index.ts:1262-1320` — `message_end`/tool hooks feed the log.
- `pi-extension/src/index.ts:1743` — `ensureSessionStarted()` at relay start.
- `pi-extension/src/index.ts:2231-2251` — `_handleSessionSync`.
- `pi-extension/src/session/remote_session.ts:45-54` — UUID7 fallback.
- `app/lib/data/sync/sync_service.dart:1003-1062` — `_replayHistory` + stale gate.
- `app/lib/data/sync/sync_service.dart:1094-1120` — `_loadIndex` high-water.
- `.agents/skills/mobile-remote-coding/SKILL.md` — snapshot+replay checklist.
- `.agents/skills/pi-extension-typescript/SKILL.md` — session lifecycle /
  stale-context rules.
