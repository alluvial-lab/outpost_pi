---
id: gate-patterns-v0.11.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: patterns
created: 2026-08-28
updated: 2026-08-28
---

# Patterns extracted for v0.11.0

## New patterns codified
- `event-bus-unknown-payload-narrowing` — Narrow unknown event-bus payloads to validated fields before mutating lifecycle state.
- `presence-aware-patch-merging` — Distinguish omitted patch fields from explicit values so partial updates preserve cached state.
- `lifecycle-boundary-state-convergence` — Reset active lifecycle projections before transport teardown so replacement and shutdown cannot strand stale state.

The `lifecycle-boundary-state-convergence` pattern realizes the fourth candidate from `backlog-pattern-candidates-v040`; the bundle's background/working lifecycle work provides the additional cross-surface occurrences needed for codification.

## Inconsistencies flagged
None.

The existing `durable-first-visibility-gating` and `edge-triggered-convergence` patterns already cover the bundle's durable-before-visible ordering and transition-edge-only broadcasting. The bounded watchdog/retry candidate did not reach three recurring occurrences with the same structure, and canonical timestamp capture remained covered by existing durable identity/timestamp patterns; neither was added.

## Pattern files written
- `.agents/skills/patterns/event-bus-unknown-payload-narrowing.md`
- `.agents/skills/patterns/presence-aware-patch-merging.md`
- `.agents/skills/patterns/lifecycle-boundary-state-convergence.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)
