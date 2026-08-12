---
id: gate-security-broker-audit-log-oversized-predecessor-regression
kind: story
stage: implementing
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
