---
id: gate-docs-pattern-line-refresh
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

# Pattern skills carry stale file:line references

## Drift category
pattern-skill-staleness (High ×7, release-relevant; consolidated — one
mechanical class)

## Location
`.agents/skills/patterns/`: reachability-contract-projection.md:5,45;
asymmetric-threshold-stabilization.md:44; frame-byte-bounded-admission.md:12;
edge-triggered-convergence.md:39; presence-aware-patch-merging.md:65,79;
lifecycle-boundary-state-convergence.md:54;
owner-channel-scoped-resource-ownership.md:71.

## Required edit
Refresh each reference to the current implementation lines (verified against
the tree); qualify reachability-contract-projection for bounded stack-local
exceptions.
