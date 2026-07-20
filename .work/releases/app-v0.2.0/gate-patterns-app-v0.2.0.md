---
id: gate-patterns-app-v0.2.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: app-v0.2.0
gate_origin: patterns
created: 2026-07-20
updated: 2026-07-20
---

# Patterns extracted for app-v0.2.0

## New patterns codified

- `generation-fenced-async-ownership` — Capture a lifecycle revision before async work and suppress side effects when the owner has been replaced or disposed.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/generation-fenced-async-ownership.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

## Discovery note

The pattern scanner ran inline because this gate invocation prohibited nested
sub-agents. This reduced isolation was accepted for this run; discovery checked
the 32-file app bundle first and verified the extracted structure across router,
chat, sync, and mesh ownership code.
