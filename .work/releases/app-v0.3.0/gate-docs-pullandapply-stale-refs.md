---
id: gate-docs-pullandapply-stale-refs
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: app-v0.3.0
gate_origin: docs
created: 2026-07-25
updated: 2026-07-25
---

# Comments and a test name reference the nonexistent pullAndApply

## Location
`app/lib/data/mesh/mesh_sync_service.dart:19-21,397-399`;
`app/test/data/mesh/mesh_sync_service_test.dart:759`

## Contradiction
`[pullAndApply]` does not exist; the current public reconciliation API is
`pullOnDemand()`.

## Implementation notes
Renamed both dartdoc references and the test name to `pullOnDemand`.
Verification: flutter analyze clean; mesh tests green.

## Review
Bounded inline review (orchestrator, 2026-07-25): refs now resolve to the
real API. Approved -> done.
