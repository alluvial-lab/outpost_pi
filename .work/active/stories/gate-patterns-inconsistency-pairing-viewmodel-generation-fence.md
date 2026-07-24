---
id: gate-patterns-inconsistency-pairing-viewmodel-generation-fence
kind: story
stage: drafting
tags: [refactor]
parent: null
depends_on: []
release_binding: null
gate_origin: patterns
created: 2026-07-24
updated: 2026-07-24
---

# pairing_viewmodel crosses async gaps then installs channel without a generation fence

## Existing pattern
`generation-fenced-async-ownership`

## Divergent code
`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart:81-122`

## Nature of divergence
A pairing attempt crosses several async gaps and then installs a channel, adopts it, and emits UI state without a lifecycle generation or disposed/current-operation check.

## Reconciliation direction
Bring the code into conformance with the documented pattern (or, if the
divergence is deliberate, amend the pattern's "When NOT to Use"). Routed to a
subsequent release — parked unbound by gate-patterns for v0.3.0.
