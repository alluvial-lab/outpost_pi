---
id: gate-tests-concurrent-first-run-pairing-race
kind: story
stage: done
tags: [pi-extension, testing]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-15
updated: 2026-08-16
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

## Upstream reference
Upstream independently hit and solved the adjacent class (`fc2339bd` —
coalesce concurrent startup, root-level single-flight at their
`index.ts:494,1777-1788`). Our lineage deliberately removed root single-flight
after it wedged Pi; our coalescing lives at `index.ts:1877-1892` + exclusive
identity creation. Use their shape as a verification reference for what the
tests must pin — not as a port.

## Implementation

- Added a deterministic first-run fallback race test in
  `pi-extension/src/pairing/storage.test.ts`. The filesystem harness blocks the
  exclusive winner after `open(..., "wx")`, starts the competing caller, and
  waits until that caller observes `EEXIST` and enters its recovery read. It
  then releases the winner's write, waits for the complete write, and releases
  the recovery read. The assertions pin that neither caller settles early,
  both return identical public/private key material, and the sole persisted
  `identity.json` is complete with private file and directory permissions.
- Added a deterministic relay single-flight test beside the room/start tests in
  `pi-extension/src/extension.test.ts`. The fake relay exposes a connect-started
  barrier and a separate release barrier; the second relay start is invoked
  while the first is parked in `connect()`. Before release the test pins one
  relay instance, one connect call, idle state, and two pending awaiters; after
  release both awaiters settle from that shared start and the runtime reaches
  `started` without another connection.
- Verification passed from `pi-extension/`:
  `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  (56 files, 996 passed, 3 skipped). Both focused race tests also passed five
  consecutive runs with one worker.

### Bounded inline review (2026-08-16)
PASS — tests-only diff, genuine park/release barriers (no wall-clock), 996 tests green, race tests stable across 5 focused runs.
