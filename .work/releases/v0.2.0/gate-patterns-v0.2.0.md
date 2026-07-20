---
id: gate-patterns-v0.2.0
kind: story
stage: done
tags: [patterns, docs]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: patterns
created: 2026-07-20
updated: 2026-07-20
---

# Patterns extracted for v0.2.0

## New patterns codified

- `fresh-operation-gateway-factories` — Create a fresh, lifecycle-owned gateway through an injected factory for each independent process, agent, terminal, or pairing operation.

## Inconsistencies flagged

None. The candidate shapes that overlapped the existing catalog (typed wire decoding, lifecycle fencing/teardown, and command adapters) were not redocumented. No bundle divergence from the existing documented patterns was verified.

## Discovery record

- Bundle prepared from 91 non-release bound item records and 903 distinct committed files; release-bound source files were the focus and recurring candidates were followed only where needed to establish recurrence.
- Scanner ran inline because this gate invocation explicitly disallowed nested sub-agents. This reduces reviewer isolation; no release-body edit was made because the invocation prohibits editing `.work/active/release-v0.2.0.md`.
- The new pattern was verified with four concrete occurrences: pairing factory, revoke factory, per-agent RPC factory, and per-terminal PTY factory.

## Pattern files written

- `.agents/skills/patterns/fresh-operation-gateway-factories.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)
