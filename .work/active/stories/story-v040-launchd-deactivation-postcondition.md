---
id: story-v040-launchd-deactivation-postcondition
kind: story
stage: implementing
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
