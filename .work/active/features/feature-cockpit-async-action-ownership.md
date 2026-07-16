---
id: feature-cockpit-async-action-ownership
kind: feature
stage: drafting
tags: [cockpit, refactor, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
---

# Cockpit: shared async UI-action and teardown ownership

## Brief

Eight gate findings across `cockpit/` describe Cockpit UI actions and lifecycle
hooks that invoke `Future`-returning work from sync button callbacks or
`initState` without `await`/`unawaited(...)`/error handling. The shared defect
is the same as the app-side lifecycle ownership gap, but in the desktop UI: a
discarded async future silently swallows failures, and one of them
(`gate-refactor-lifecycle-unguarded-async-workspace-projection`) calls
`PaneItem.dispose()` synchronously while `AgentSession.dispose()` is async —
teardown races that can leak process/subscription resources. This feature
defines the shared ownership pattern for Cockpit async UI actions and applies it
to:

- `gate-cruft-empty-catch-formatter-reload` — empty catch-swallow in formatter reload path
- `gate-refactor-lifecycle-unguarded-async-agent-composer` — agent composer drops session operation futures
- `gate-refactor-lifecycle-unguarded-async-connectivity-save` — relay save action discards its async save future
- `gate-refactor-lifecycle-unguarded-async-cron-log` — cron log initial load future discarded
- `gate-refactor-lifecycle-unguarded-async-daemon-actions` — daemon action buttons discard `Future`-returning callbacks
- `gate-refactor-lifecycle-unguarded-async-language-settings` — LSP probe future fired without explicit handling
- `gate-refactor-lifecycle-unguarded-async-schedule-actions` — schedule action buttons discard `Future`-returning callbacks
- `gate-refactor-lifecycle-unguarded-async-workspace-projection` — async tab disposal discarded by workspace teardown

## Simplification opportunity

Establish one owned-async pattern for the Cockpit UI layer (mirror the
`.catchError` / `unawaited` discipline the app feature defines) and ensure
async `dispose()` chains await before the owning widget tears down. No
public-surface behavior change.

## Source

Promoted from backlog by `scope` (2026-07-15). 8 `gate-refactor-lifecycle-*` /
`gate-cruft-*` findings from the v0.6.0 release gate passes.
