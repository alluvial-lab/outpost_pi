---
id: gate-docs-reachability-stall-docs
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: docs
created: 2026-10-04
updated: 2026-10-04
---

# Reachability docs omit the handshake-stall fast-cycle exception

## Drift category
foundation-doc-assertion (High ×2 + Medium, release-relevant)

## Location
Docs: `docs/DECISIONS.md:83`, `docs/ARCHITECTURE.md:257-261`,
`protocol/schema/reachability.md:5`.
Contradicting: app-local `handshakeStall` failures retry at fixed 1s with
the ladder rung frozen (`reachability_adapter.dart`), a deliberate bounded
exception to the shared `[1,2,5,10,30]` ladder.

## Required edit
Qualify the shared ladder as the NORMAL retry policy in all three docs; note
the app-local zero-inbound handshake-stall fast cycle as a bounded
stack-local exception that does not change the canonical schema.
