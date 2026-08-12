---
id: gate-security-launchd-plist-not-unlinked-regression
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

# Legacy launchd plist survives cleanup and can resurrect the old daemon

## Severity
High — REGRESSION of gate-security-orphaned-pre-rebrand-launchd-daemon (security regression sweep, v0.4.0).

## Location
pi-extension/src/daemon/install.ts:115-121, 255-256.

## Evidence
The prior fix was supposed to stop the legacy label and remove dev.remotepi.supervisord.plist. Current cleanup only invokes launchctl bootout/unload; it never unlinks the plist. It also suppresses every cleanup failure and unconditionally logs that the legacy service was removed. The stale LaunchAgent remains discoverable for a later login/load and can run alongside the new supervisor.

## Remediation direction
After unloading, unlink the known legacy plist path; validate cleanup success when the plist exists; emit a blocking warning or failure if it cannot be removed. Test both service deactivation and on-disk plist deletion.

## Implementation notes
- Execution capability: inline host execution; this was a bounded security cleanup fix in the launchd installer and its focused unit suite.
- Review weight: standard (project default), using the required bounded inline standalone-story review with no independent reviewer.
- Files changed: `pi-extension/src/daemon/install.ts` now centralizes the legacy plist path, attempts all idempotent launchctl deactivation forms, unlinks the persisted plist, validates absence with `lstat`, and throws on inspection/removal failure; `pi-extension/src/daemon/install.test.ts` covers command deactivation, on-disk deletion, and an unremovable path.
- Tests added/removed: added successful legacy launchd cleanup and blocking unlink-failure cases; removed none.
- Verification: `./node_modules/.bin/vitest run src/daemon/install.test.ts` passed (30 passed, 3 skipped); `./node_modules/.bin/tsc --noEmit` passed.
- Simplification: replaced the install path's unconditional success log with one cleanup operation that owns both deactivation and durable-file removal.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Bounded inline review
Approved. Missing registrations/plists remain idempotent, launchctl alternatives stay best-effort, but any discoverable legacy plist must now be verifiably removed before the new launchd service is activated.
