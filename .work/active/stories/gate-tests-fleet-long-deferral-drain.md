---
id: gate-tests-fleet-long-deferral-drain
kind: story
stage: done
tags: [testing, pi-extension, bug, lifecycle]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: tests
created: 2026-09-08
updated: 2026-09-08
---

# Protect fleet restart convergence after a quiet, long background deferral

## Priority
High — release-relevant; useful coverage gap with a source-confirmed production defect.

## Value evidence
Item: `feature-fleet-update-from-mobile-extension-coordinator`.

The feature promises self-quiescing restarts after turns and background work drain. Its review fix 2 specifically says deferred fleet arms no longer expire. This matters to real long-lived coding sessions; the post-v0.11.1 background-work incident also establishes that restart tooling must respect in-process background work.

Existing `pi-extension/src/extension.test.ts:7298-7321` covers an ordinary interactive arm and an immediate background completion. The separate expiry test at `extension.test.ts:7207-7268` intentionally protects the five-minute expiry of ordinary arms. Neither combines a consumed fleet arm with a background task longer than that window. `fleet_update.test.ts:328-332` only asserts that the injected arm function is called and reports `deferred`.

The omitted timeline currently fails:

1. A valid fleet arm is staged while background work is active.
2. `agent_settled` refreshes its timestamp once (`pi-extension/src/index.ts:3398-3400`).
3. Background work continues quietly for more than five minutes; no additional settle event occurs.
4. The final background completion calls the restart gate with `activeCount == 0` (`index.ts:1402-1407`).
5. The timestamp check deletes the arm (`index.ts:3425-3427`) before the non-idle refresh path (`index.ts:3430-3433`), so the process never restarts after draining.

## Gap type
Interrupted/deferred state transition / bug regression. Repair the underlying production defect without weakening ordinary-arm expiry.

## Suggested test
```typescript
// Fake clock, isolated state, and intercepted process signaling.
// Stage a consumed fleet arm with an active background task.
// Emit agent_settled, then advance six minutes WITHOUT extra lifecycle events.
// Assert no restart while busy; complete the final background task.
// Assert exactly one normal restart claim after drain, with the correct nonce.
// Repeated completion/settle notifications must not claim twice.
// Contrast an ordinary interactive arm: it must still expire after five minutes.
```

Do not make the test pass by injecting periodic settle events or refreshing the timestamp in the harness; that would assume away the real quiet-background timeline. Cover a long foreground-turn deferral through the same contract if the repaired policy shares that path. No live restarts or live marker files are required.

## Test location (suggested)
`pi-extension/src/extension.test.ts`, alongside the existing hot-reload expiry and background-drain tests.

## Scanner verification
Source-read-only executable witness: extracted unchanged `_maybeRestartForExtensionReload`, `_refreshDeferredFleetArm`, and consumption helpers from `index.ts`, and evaluated them with virtual filesystem, clock, lifecycle state, and process signaling. After a consumed arm, one busy settle, a six-minute advance, and final drain, observed `{armed: false, claimed: false, mockSignalCount: 0}`. This is a focused source-level witness, not a production integration-suite run. No real filesystem marker or process signal was emitted. The permanent regression should fail on the pre-fix implementation.

## Resolution (2026-09-08)

- Root cause confirmed: after a quiet background deferral exceeded five
  minutes, the final drain edge checked the armed file timestamp and deleted
  the still-valid fleet intent before claiming it.
- Fix: fleet arms (identified by a validated, target-scoped `update_id`) are
  exempt from the five-minute stale sweep. Their durable single-use marker and
  stable per-Pi target fence provide the replay boundary; ordinary interactive
  arms still use the unchanged five-minute expiry. This avoids requiring
  periodic lifecycle events during quiet background work.
- Regression: `pi-extension/src/extension.test.ts` uses a virtual clock and
  temporary state, stages a production fleet arm while background work is
  active, emits one settle, advances six minutes without lifecycle events,
  then completes the background work. The arm survives and signals exactly
  once at drain; repeated completion/settle events cannot re-claim it.
- Verification: `cd pi-extension && corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  passed (65 files, 1,156 tests passed, 3 skipped). Existing ordinary-arm
  expiry coverage remains green and unchanged.
- Safety: only temporary state, a virtual clock, and an intercepted `process.kill`
  were used; no live process was restarted or signaled.
