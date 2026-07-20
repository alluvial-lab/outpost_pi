---
id: gate-patterns-cockpit-v0.2.0
kind: story
stage: done
tags: [patterns, cockpit]
parent: null
depends_on: []
release_binding: cockpit-v0.2.0
gate_origin: patterns
created: 2026-07-20
updated: 2026-07-20
---

# Patterns extracted for cockpit-v0.2.0

## New patterns codified

- `awaited-pane-teardown-contract` — Remove pane ownership before awaiting teardown, and expose a Future that completes only after its resources close.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/awaited-pane-teardown-contract.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

## Discovery note

The pattern scanner ran inline because this gate invocation prohibited nested
sub-agents. This reduced isolation was accepted for this run; discovery checked
the four-file cockpit bundle first and verified the extracted teardown contract
across the pane abstraction, agent and terminal sessions, and workspace
projection.
