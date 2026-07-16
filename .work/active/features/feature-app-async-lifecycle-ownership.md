---
id: feature-app-async-lifecycle-ownership
kind: feature
stage: drafting
tags: [app, refactor, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
---

# App: explicit ownership and observability for discarded async work

## Brief

Eleven gate findings across `app/` describe the same defect class: the mobile
app launches, retries, and persists through async futures that are never
awaited, returned, or given error handling. Failures vanish silently, which
breaks lifecycle convergence (the `working` state does not reliably settle
false on error) and masks the exact reconnect/persistence bugs the
`epic-remote-session-resilience-refactor` exists to fix. This feature
establishes explicit ownership — `unawaited(...).catchError(...)` or an owned
async boundary — for every discarded app-side future:

- `gate-cruft-dynamic-setactiveroom-fallback` — silent dynamic transport fallback for `setActiveRoom`
- `gate-cruft-empty-catch-old-channel-close` — empty catch around old channel close during adopt
- `gate-cruft-enqueue-drops-write-errors` — `_enqueue` drops write-chain exceptions
- `gate-cruft-room-adoption-persist-dropped` — legacy room-adoption persistence failures dropped
- `gate-refactor-lifecycle-app-router-floating-boot` — router starts `ConnectionManager.boot` as an unguarded future
- `gate-refactor-lifecycle-chat-bootstrap-floating` — `ChatViewModel` constructor discards bootstrap failures
- `gate-refactor-lifecycle-connection-retry-floating` — connection retry timer discards the reconnect future
- `gate-refactor-lifecycle-peer-mesh-publish-dropped` — peer mutation hook drops async mesh publish failures
- `gate-refactor-lifecycle-room-persist-fire-and-forget` — room persistence writes are fire-and-forget
- `gate-refactor-lifecycle-sync-service-floating-rebinds` — `SyncService` drops lifecycle-sensitive async rebind futures
- `gate-refactor-lifecycle-transcript-write-futures-discarded` — transcript write futures discarded from server-message handlers

## Simplification opportunity

Converge `working`/connection state to false on every error exit path (the
lifecycle-ownership rule in `.agents/rules/code-design.md`); the discarded
futures are the structural reason the state machine doesn't converge on
failure. No public-surface behavior change.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor` — mobile UI state robustness is the
epic's stated scope. 11 `gate-refactor-lifecycle-*` / `gate-cruft-*` findings
from the v0.6.0 release `gate-refactor` (lifecycle library) and `gate-cruft` passes.
