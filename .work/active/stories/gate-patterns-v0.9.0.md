---
id: gate-patterns-v0.9.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: patterns
created: 2026-08-26
updated: 2026-08-26
---

# Patterns extracted for v0.9.0

## New patterns codified

- `deterministic-completion-barriers` — Drain event-loop work or await a named bounded state predicate instead of using arbitrary sleeps for async test completion.
- `break-it-proof-regression-discipline` — Reintroduce one old failure, require the guard to fail with bounded evidence, then restore and rerun the clean path.
- `reachable-blob-history-content-scanning` — Enumerate unique blobs reachable from public revisions and scan their bytes directly, including merge and binary history.
- `atomic-snapshot-store-marker-last-migration` — Flush complete snapshots through temp-and-rename, and write a migration completion marker only after all destinations finish.
- `dual-execution-path-contract-documentation` — Document capability-dependent operations as both in-process and managed-restart paths, including ownership, acknowledgement, teardown, and convergence.

## Existing patterns extended

- `generation-fenced-async-ownership` — Extended from mobile generation checks to the app's outbox/channel revalidation and relay binding `AbortSignal` plus current-generation fencing.

## Inconsistencies flagged

None. The outbox and relay abort-controller shapes extend
`generation-fenced-async-ownership`; they do not contradict it. Existing
`explicit-async-interleaving-tests` and `failure-first-regression-tests` remain
separate: the new completion-barrier pattern drains scheduled work, while the
new break-it-proof pattern validates guard strength by deliberate failure.

## Pattern files written

- `.agents/skills/patterns/deterministic-completion-barriers.md`
- `.agents/skills/patterns/break-it-proof-regression-discipline.md`
- `.agents/skills/patterns/reachable-blob-history-content-scanning.md`
- `.agents/skills/patterns/atomic-snapshot-store-marker-last-migration.md`
- `.agents/skills/patterns/dual-execution-path-contract-documentation.md`
- `.agents/skills/patterns/generation-fenced-async-ownership.md` (extended)
- `.agents/skills/patterns/SKILL.md` (updated index; 36 entries)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

## Discovery summary

- Bundle: `.work/bin/work-view --release v0.9.0 --paths`, 41 non-release items.
- Code delta: `bc49564e..HEAD`.
- Pattern candidates evaluated: 6.
- New patterns codified: 5.
- Existing patterns extended: 1.
- Inconsistencies with existing patterns: 0.
- Scanner isolation: inline source-read-only discovery because the caller
  prohibited the subagent tool; reduced isolation was recorded here rather than
  editing the release orchestration file.
