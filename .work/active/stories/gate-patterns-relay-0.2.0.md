---
id: gate-patterns-relay-0.2.0
kind: story
stage: done
tags: [patterns, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: patterns
created: 2026-07-19
updated: 2026-07-19
---

# Patterns extracted for relay-0.2.0

Discovery ran inline with reduced isolation at the operator's direction; no nested scanner agent was dispatched.

## New patterns codified

- `centralized-resource-policy` — Define relay resource ceilings and budget semantics once, then import them at each owning boundary.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/centralized-resource-policy.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)
