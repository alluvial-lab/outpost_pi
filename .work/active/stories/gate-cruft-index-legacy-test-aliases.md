---
kind: story
release_binding: null
parent: feature-retire-legacy-piext-composition-seams
stage: done
id: gate-cruft-index-legacy-test-aliases
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-17
---

# Migrate legacy index test aliases to the named harness

## Confidence
Medium

## Category
compatibility shim

## Location
`pi-extension/src/index.ts:2223`

## Evidence
```ts
// Legacy compatibility aliases. Keep these private test exports available while
// new tests migrate to the named harness above.
export const _connectForTest = remotePiTestHarness.connect;
export const _stopForTest = remotePiTestHarness.stop;
export const _getState = remotePiTestHarness.state;
export const routeClientMessage = remotePiTestHarness.routeClientMessage;
```

## Removal
Update extension tests and compatibility probes to import/use `remotePiTestHarness` directly, then remove these legacy aliases from `index.ts`. Keep only the named harness as the test seam.

## Implementation

Migrated `src/extension.test.ts` and `test/ping.test.ts` to the canonical
`outpostPiTestHarness` and removed the four redundant `src/index.ts` exports.
`./node_modules/.bin/tsc --noEmit` passed. The focused Vitest run passed 194/195
tests; only the tracked `env-ext-test-cwd-lock-ordering-flake` failed because a
stale read-only cwd-lock socket prevented the fixture's first lock acquisition.
