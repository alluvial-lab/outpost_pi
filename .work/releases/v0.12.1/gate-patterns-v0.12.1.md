---
id: gate-patterns-v0.12.1
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: patterns
created: 2026-10-04
updated: 2026-10-04
---

# Patterns extracted for v0.12.1

## New patterns codified
- `evidence-local-failure-classification` — assign recovery categories at the
  evidence-owning boundary; consumers upstream never reclassify from
  exception shapes.
- `join-in-flight-operations` — share one completion future for equivalent
  concurrent work; release only the matching operation on settlement.

## Inconsistencies flagged
- New connection-manager join tests rely on the existing 5ms `_settle()`
  sleep helper, diverging from `deterministic-completion-barriers` /
  `explicit-async-interleaving-tests` — tracked as
  `gate-patterns-inconsistency-settle-sleep` (unbound, drafting).

## Pattern files written
- `.agents/skills/patterns/evidence-local-failure-classification.md`
- `.agents/skills/patterns/join-in-flight-operations.md`
- `.agents/skills/patterns/SKILL.md` (updated index, 44 entries)
- `.agents/rules/patterns.md` (regenerated digest, src-sha256
  `7544c3a395f6567a…`)

Not promoted (scanner triage): probe-pinned runtime semantics (single
fixture boundary, no independent recurrence); fail-fast non-interactive
wizards (single qualifying guard).
