---
id: gate-security-launchd-plist-not-unlinked-regression
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

# Legacy launchd plist survives cleanup and can resurrect the old daemon

## Severity
High — REGRESSION of gate-security-orphaned-pre-rebrand-launchd-daemon (security regression sweep, v0.4.0).

## Location
pi-extension/src/daemon/install.ts:115-121, 255-256.

## Evidence
The prior fix was supposed to stop the legacy label and remove dev.remotepi.supervisord.plist. Current cleanup only invokes launchctl bootout/unload; it never unlinks the plist. It also suppresses every cleanup failure and unconditionally logs that the legacy service was removed. The stale LaunchAgent remains discoverable for a later login/load and can run alongside the new supervisor.

## Remediation direction
After unloading, unlink the known legacy plist path; validate cleanup success when the plist exists; emit a blocking warning or failure if it cannot be removed. Test both service deactivation and on-disk plist deletion.
