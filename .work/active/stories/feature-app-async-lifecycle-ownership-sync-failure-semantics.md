---
id: feature-app-async-lifecycle-ownership-sync-failure-semantics
kind: story
stage: done
tags: [app, lifecycle]
parent: feature-app-async-lifecycle-ownership
depends_on: [feature-app-async-lifecycle-ownership-connection-persistence]
release_binding: null
gate_origin: null
created: 2026-07-17
updated: 2026-07-17
---

# Define SyncService write, rebind, and convergence failure semantics

## Checkpoint

Implement Unit 5 from the parent feature: distinguish awaited commands from
owned detached writes, serialize activation before resend/replay, reject stale
session completions, and surface transcript persistence degradation without
inventing a second transcript truth.

## Finding coverage

- `gate-cruft-enqueue-drops-write-errors`
- `gate-refactor-lifecycle-sync-service-floating-rebinds`
- `gate-refactor-lifecycle-transcript-write-futures-discarded`

## Required behavior

- `_enqueue` returns real failures to awaited callers while its predecessor
  chain remains usable after failure.
- Stream/timer work uses a private named detached boundary with typed
  diagnostics and replay recovery.
- Terminal outcomes settle idle even when event persistence fails; non-terminal
  failures do not falsely idle a live turn.
- Transcript degradation is visible in Chat and clears only after a successful
  transcript write; no synthetic transcript row is created.
- Room change ordering is activation, stale check, held-message resend, then
  sync/replay. Runtime Hive `put` is awaited in the queue.
- Every async gap validates disposal, generation, and captured session before
  mutation/send/emit.

## Acceptance evidence

- [x] A fail-once `TranscriptEventStore` proves queue continuation,
      degraded/recovered signaling, replay request, and terminal idle
      convergence.
- [x] Controlled stale-session tests prove no old-session write, send, or emit
      lands after replacement/disposal.
- [x] Runtime Hive failure proves `put` is awaited and diagnosed.
- [x] Existing convergence tests at `sync_service_test.dart:1988-2070` remain
      green with added failure injection.
- [x] Targeted sync/chat tests and `flutter analyze` pass.

## Implementation

- Execution capability: inline, highest-rigor lifecycle implementation; the
  ordering and convergence model stayed in one context.
- Review weight: standard (caller workflow default; feature-level review only).
- Files changed: Sync service/events, Chat state/ViewModel/page, and focused
  Sync/Chat tests.
- Tests added: fail-once append/read recovery, one-shot degraded/recovered
  signaling, replay request, terminal vs non-terminal convergence, stale
  append/send suppression, awaited runtime writer, and Chat warning projection.
- Simplification: all cited discarded transcript/rebind futures now terminate
  in named Sync-owned boundaries; terminal event pairs are batched; the obsolete
  active-key helper and lint suppressions were removed.
- Discrepancies from design: runtime `put` is tested through an injected
  writer seam around the real awaited queue boundary rather than corrupting a
  process-global Hive box; production still calls and awaits Hive directly.
- Adjacent issues parked: none.

Verification: 101 focused Sync/replay/Chat tests and
`flutter analyze lib test` passed. Existing convergence coverage remains green.
