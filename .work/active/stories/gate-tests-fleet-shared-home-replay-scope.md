---
id: gate-tests-fleet-shared-home-replay-scope
kind: story
stage: implementing
tags: [testing, pi-extension, bug]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: tests
created: 2026-09-08
updated: 2026-09-08
---

# Protect per-target fleet consumption in a shared home, including restart replay

## Priority
High — release-relevant; useful coverage gap with a source-confirmed production defect.

## Value evidence
Item: `feature-fleet-update-from-mobile-extension-coordinator`.

The feature promises a rolling restart of local siblings, each staging its OWN nonce-bound arm, while a replay after process restart must be declined. The parent feature's review fixes 3–4 explicitly claim durable replay fencing and phase-aware consumption.

Existing `pi-extension/src/extension/fleet_update.test.ts:296-325` tests one handler with an injected boolean `consumed`. That usefully checks that the handler calls its consumption port, but cannot test the production persistence key or independence between targets. The coordinator tests similarly replace every sibling with canned acknowledgements. There is no shared-home, multiple-target consumption test.

The omitted seam currently fails:

- `pi-extension/src/index.ts:3015-3016` resolves the machine-shared `OUTPOST_PI_HOME` / `~/.pi/remote` directory.
- `index.ts:3185-3205` hashes only `updateId` into `.fleet-update-consumed-<digest>` and claims it using `wx`.
- Every sibling receives the same update id; `index.ts:3242-3247` wires that store into the sibling handler, and `index.ts:3226-3229` consumes the same id again for the coordinator.
- Consequently the first sibling consumes the run for the entire machine; remaining siblings and the coordinator decline. A PID-only key would avoid the collision but would lose the promised replay fence across restart; scope the durable identity to the stable target.

## Gap type
Important multi-target persistence seam / bug regression. Repair the underlying production defect, not just the test.

## Suggested test
```typescript
// Exercise the production consumption adapter with one isolated shared store.
// Instantiate two distinct stable target identities plus their coordinator.
// All three must accept their FIRST commitment for the SAME update id.
// Re-create each target's adapter with a new process incarnation against the
// same store: each must reject that id, but accept a new update id.
// Drive the real phase-aware handler so prepare never consumes or arms.
// Assert own-target nonce-bound arms, not mocked per-target success responses.
```

Use a narrow persistence seam or isolated temporary state, and stub restart side effects before any lifecycle hook runs. Never involve the live fleet. Keep same-target duplicate rejection and owner-only/exclusive file admission intact.

## Test location (suggested)
`pi-extension/src/extension/fleet_update.test.ts` plus production persistence-adapter or composition coverage in `pi-extension/src/extension.test.ts`.

## Scanner verification
Source-read-only executable witness: extracted the unchanged `_fleetUpdateConsumedPath` and `_consumeFleetUpdateIntent` function bodies from `index.ts`, stripped TypeScript types with Node, and evaluated three distinct virtual process contexts sharing one in-memory filesystem. First consumption of one run yielded `[true, false, false]`, rather than three successes. This is a focused source-level witness, not a production integration-suite run. No real marker files, processes, signals, or live services were touched. The permanent regression should exercise the production adapter and fail on the pre-fix implementation.
