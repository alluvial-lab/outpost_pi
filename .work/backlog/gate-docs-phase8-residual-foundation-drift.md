---
id: gate-docs-phase8-residual-foundation-drift
created: 2026-07-19
updated: 2026-07-19
tags: [docs]
---

# Phase-8 residual foundation-doc drift (3 stale assertions)

## Source

Parked from the Phase-8 final completion review (2026-07-19). Lower-risk —
foundation-doc drift, routes to the `gate-docs` release gate's drift detection.

## Findings

1. `.agents/skills/formal-rigor-stack/SKILL.md:60` still claims relay mailboxes
   are unbounded; `feature-relay-resource-bounds` made them 16-frame bounded
   with drop-newest + saturation metrics (commit a86378b).
2. `AGENTS.md` still describes sender-side `to_room` targeting as deferred to
   design (see `story-to-room-sender-side-room-targeting`), but current
   room-targeted behavior has advanced under the session-lifecycle work —
   reconcile the current-state description.
3. `docs/SPEC.md` + `docs/ARCHITECTURE.md` contradict themselves about NUL-prefix
   vs structured Cockpit control (already tracked in
   `gate-docs-control-transport-nul-prefix-contradiction`, the parked
   cockpit-settings review finding — deduplicate on adoption).

## Risk rationale

Foundation-doc drift misleads future agents into restoring stale behavior or
contradicting shipped work. All three are current-state corrections, not
missing coverage. Belong to the `gate-docs` release gate.

## Recommended direction

On the next `gate-docs` run or docs touch: update formal-rigor-stack to the
bounded-mailbox current state; reconcile AGENTS.md to_room targeting against
current room-targeted behavior; fold the NUL-prefix contradiction into one fix.
