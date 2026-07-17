---
id: feature-app-async-lifecycle-ownership-sync-failure-semantics
kind: story
stage: implementing
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

- [ ] A fail-once `TranscriptEventStore` proves queue continuation,
      degraded/recovered signaling, replay request, and terminal idle
      convergence.
- [ ] Controlled stale-session tests prove no old-session write, send, or emit
      lands after replacement/disposal.
- [ ] Runtime Hive failure proves `put` is awaited and diagnosed.
- [ ] Existing convergence tests at `sync_service_test.dart:1988-2070` remain
      green with added failure injection.
- [ ] Targeted sync/chat tests and `flutter analyze` pass.
