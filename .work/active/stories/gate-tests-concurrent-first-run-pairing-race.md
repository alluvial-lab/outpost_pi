---
id: gate-tests-concurrent-first-run-pairing-race
kind: story
stage: implementing
tags: [pi-extension, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-08-15
updated: 2026-08-15
---

# Deterministic coverage for the concurrent first-run pairing race

Post-hoc v0.5.0 tests-gate finding. Severity: **High** — coverage gap on a
production-impacting contract.

## Severity
High

## Contract at risk
Concurrent starters must share one persisted identity and one relay
connection, so the QR targets the live Pi room.

## Location
- Test gap: `pi-extension/src/pairing/storage.test.ts:211` (sequential-only)
- Production concurrency surfaces: `pi-extension/src/pairing/storage.ts:177-203`
  (exclusive creation + EEXIST recovery), `pi-extension/src/index.ts:1877-1892`
  (`_relayStartInFlight`); partial relay-side coverage at
  `pi-extension/src/extension.test.ts:4302`, `:4978`

## Evidence
Identity-creation tests run sequentially; nothing deterministically races two
fallback identity creations or two relay starts through `_relayStartInFlight`.
Currently protected only probabilistically by E2E. (Distinct from
`story-identity-boot-restore-race` — app-side late Block Store restore — and
`backlog-peers-lock-restore-collision-safety` — peers.lock restore-on-mismatch.)

## Remediation direction
Barrier-based deterministic tests: two concurrent fallback identity creations
→ assert identical keys, one complete private identity file, both callers
resolving from the shared operation; two concurrent relay starts → exactly one
connect.
