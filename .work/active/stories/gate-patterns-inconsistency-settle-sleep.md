---
id: gate-patterns-inconsistency-settle-sleep
kind: story
stage: drafting
tags: [refactor, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: patterns
created: 2026-10-04
updated: 2026-10-04
---

# New manager join tests infer progress from a fixed sleep

## Existing pattern
`deterministic-completion-barriers` (also `explicit-async-interleaving-tests`)

## Divergence
The same-peer/different-peer connect-join tests added in
`story-fix-post-strike-recovery-ladder`
(`app/test/data/transport/connection_manager_test.dart`, join group) call
`_settle()` — an arbitrary `Future.delayed(5ms)`
(`connection_manager_test.dart:248`) — to infer that `_performConnect` has
started and set `_activePeer`. The pending-factory completer correctly holds
work open; only the start-barrier is time-based.

## Reconciliation direction
Replace the `_settle()` calls in the join group with a deterministic
factory-start barrier (e.g. a completer completed inside the factory before
returning the pending channel future, awaited before the second
`connectTo`), or an explicit event-loop drain appropriate for a
synchronously-started async prefix. Test-only change; behavior-preserving.
