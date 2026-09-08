---
id: gate-tests-fleet-report-commit-order-oracle
created: 2026-09-08
updated: 2026-09-08
tags: [testing, pi-extension]
gate_origin: tests
release_binding: null
---

# Assert the coordinator report precedes sibling commits, not only self-arm

## Priority
Medium — release-relevant useful gap; unbound backlog per gate routing.

## Value evidence
Item: `feature-fleet-update-from-mobile-extension-coordinator`.

The feature's review fix 4 changed one-phase arming into prepare → publish `arming` → commit, specifically to prevent a sibling restarting before the report. The production order in `pi-extension/src/extension/fleet_update.ts:226-238` currently implements that barrier.

The existing tests are valuable but do not fully assert it: `fleet_update.test.ts:72-99` checks updating-before-subprocess, status-before-SELF-arm, and self-arm-last; `fleet_update.test.ts:174-194` separately checks that the first mesh body is prepare and the last is commit. Both still pass for this incorrect ordering:

`updating → update → prepare → commit → arming → self-arm`.

The sibling-handler test at `fleet_update.test.ts:296-325` proves prepare alone does not arm, but cannot constrain the coordinator's emission order. This is a gap in the assertion oracle, not a claim that two-phase implementation or all two-phase tests are absent.

## Gap type
Bug-regression order assertion across the coordinator/sibling seam.

## Suggested test
Extend the existing success-path test (rather than adding another duplicative suite):

```typescript
// At each mesh commit callback, assert the arming event has already been emitted.
// Hold a sibling prepare acknowledgement behind an explicit promise barrier;
// before releasing it, neither arming nor commit nor self-arm may occur.
// After release: arming -> all eligible sibling commits -> coordinator self-arm.
```

Verify the test rejects an in-memory or temporary-worktree mutation that moves commitment before `emitStatus(arming)`. Do not touch live processes or marker files.

## Test location (suggested)
`pi-extension/src/extension/fleet_update.test.ts`.

## Classification
Useful gap; no test-integrity accusation and no low-value-test deletion proposed. Found by source/assertion inspection; no mutation or test suite was executed during the scan.
