---
id: gate-patterns-v0.8.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: patterns
created: 2026-08-25
updated: 2026-08-25
---

# Patterns extracted for v0.8.0

## New patterns codified

- `durable-first-visibility-gating` — Append canonical transcript facts before publishing replayable live visibility, and gate on recorded or duplicate authority.
- `session-scoped-derived-identity` — Include canonical session identity in transcript reads, writes, dedupe indexes, and derived reply links.
- `era-aware-authority-fallback-binding` — Prefer durable facts, then bind only unmatched legacy facts by stable collision keys for mixed-era compatibility.
- `canonical-projection-equivalence-oracle` — Compare optimized or migrated projections with an independent canonical oracle over prefixes, duplicates, and reopen cases.

## Candidates evaluated but already catalogued

- Fails-before evidence across campaign fixes is covered by `failure-first-regression-tests.md`; no duplicate pattern was written.
- Upload owner/channel matching is covered by `owner-channel-scoped-resource-ownership.md`; the new session pattern documents data identity, not channel teardown.
- Edge-triggered snapshot convergence is covered by `edge-triggered-convergence.md`.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/durable-first-visibility-gating.md`
- `.agents/skills/patterns/session-scoped-derived-identity.md`
- `.agents/skills/patterns/era-aware-authority-fallback-binding.md`
- `.agents/skills/patterns/canonical-projection-equivalence-oracle.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

## Discovery summary

- Bundle delta: `git v0.7.0..HEAD` (116 files, 11,228 additions, 1,392 deletions).
- Pattern candidates evaluated: 7.
- Genuine new patterns: 4, each verified with at least 3 real occurrences and file:line examples.
- Inconsistencies with existing patterns: 0.
- Scanner isolation: inline source-read-only audit because the scanner subagent tool was unavailable.

## Closure
All 4 patterns landed with the gate commit (43368fdd); index + digest regenerated. No further work.
