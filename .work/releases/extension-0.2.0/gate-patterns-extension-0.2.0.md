---
id: gate-patterns-extension-0.2.0
kind: story
stage: done
tags: [patterns, pi-extension]
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: patterns
created: 2026-07-20
updated: 2026-07-20
---

# Patterns extracted for extension-0.2.0

## New patterns codified

- `stale-capability-eviction` — On a Pi stale-context error, evict only the matching captured capability before degrading or propagating the failure.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/stale-capability-eviction.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

## Discovery note

The pattern scanner ran inline because this gate invocation prohibited nested
sub-agents. This reduced isolation was accepted for this run; discovery checked
the 9-file pi-extension bundle first and verified the stale-capability shape in
message rendering, agent wake, action wrappers, and guarded context access.
