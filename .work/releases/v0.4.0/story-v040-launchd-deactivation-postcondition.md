---
id: story-v040-launchd-deactivation-postcondition
kind: story
stage: done
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-11
updated: 2026-08-11
---

# Legacy launchd deactivation is unverified and can silently fail

## Origin
Phase 8 completion review (v0.4.0) — material blocker in gate-security-launchd-plist-not-unlinked-regression. Deleting the plist prevents resurrection, but all launchctl failures are suppressed and an unconditional "deactivated" log follows. An already-loaded legacy supervisor that won't unload keeps running, so old and new supervisors coexist. The test proves only that commands were requested.

## Location
pi-extension/src/daemon/install.ts:142-145, 421-424; pi-extension/src/daemon/install.test.ts:243-256.

## Work
Validate the deactivation postcondition: after bootout/unload, verify the label is actually gone (or distinguish "not loaded" from operational failure), and FAIL installation if a loaded legacy supervisor could not be unloaded. Test that a failed deactivation blocks install / surfaces the error, not just that commands were requested.

## Implementation notes

- Execution capability: direct inline repair; the platform boundary and its existing injected test seams made this a cohesive two-file correction.
- `pi-extension/src/daemon/install.ts` now probes `launchctl print gui/<uid>/<legacy-label>` after all deactivation attempts and plist removal. A missing service is idempotent success; a still-loaded label or an unverifiable probe throws before replacement activation. The success log is emitted only after the postcondition passes.
- `pi-extension/src/daemon/install.test.ts` proves the installation boundary fails before replacement bootstrap when a fake `launchctl print` reports the legacy label loaded. Injected cleanup tests also prove success logs deactivation, while a surviving loaded supervisor removes the resurrection plist but never logs deactivation.
- Regression evidence: the loaded-supervisor test failed before the fix because cleanup returned normally. After the fix, `./node_modules/.bin/vitest run src/daemon/install.test.ts` passes (32 passed, 3 skipped) and `./node_modules/.bin/tsc --noEmit` passes.
- Bounded inline review: unknown launchctl probe failures fail closed rather than being mistaken for "not loaded"; installation calls cleanup synchronously before current-label bootout/bootstrap, so the thrown postcondition error blocks coexistence.
