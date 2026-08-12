---
id: gate-security-broker-audit-log-oversized-predecessor-regression
kind: story
stage: done
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: security
created: 2026-08-11
updated: 2026-08-11
---

# Broker audit log: oversized predecessor bypasses the 256 KiB ceiling

## Severity
High — REGRESSION of gate-security-broker-audit-log-unbounded (security regression sweep, v0.4.0).

## Location
pi-extension/src/session/broker.ts:592-598.

## Evidence
The fix promises both active and predecessor logs stay at or below 256 KiB. Rotation checks (active + next record > limit) then renames active to .1 — but never checks whether the active file is ALREADY oversized. An unbounded log inherited from the prior implementation is therefore retained as an arbitrarily large predecessor after the first write post-hardening.

## Remediation direction
If the active file already exceeds 256 KiB at rotation, delete or safely truncate it instead of retaining it as .1. Add an upgrade regression seeded with an oversized pre-hardening log and assert both segments end at or below the ceiling.

## Implementation notes
- Execution capability: inline host execution; this was a bounded security regression in one writer and its existing integration suite.
- Review weight: standard (project default), using the required bounded inline standalone-story review with no independent reviewer.
- Files changed: `pi-extension/src/session/broker.ts` now removes an already-oversized active log instead of rotating it to `.1`; `pi-extension/src/session/e2e.test.ts` seeds an oversized legacy active log and predecessor, then verifies the new active segment is bounded and no oversized predecessor survives.
- Tests added/removed: added the broker upgrade regression `audit rotation drops an oversized pre-hardening active log`; removed none.
- Verification: `./node_modules/.bin/vitest run src/session/e2e.test.ts` passed (34 tests); `./node_modules/.bin/tsc --noEmit` passed.
- Simplification: reused the existing bounded-rotation shape already present in the owner-channel audit writer; no new abstraction was needed.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Bounded inline review
Approved. Rotation remains serialized by `auditWrite`, ordinary bounded logs still rotate normally, and an inherited oversized active segment plus any predecessor cannot survive the first post-upgrade append.
