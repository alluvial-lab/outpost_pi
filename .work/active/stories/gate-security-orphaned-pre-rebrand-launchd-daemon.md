---
id: gate-security-orphaned-pre-rebrand-launchd-daemon
kind: story
stage: done
tags: [security, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-12
updated: 2026-07-28
---

# Launchd identifier cutover leaves the pre-rebrand daemon running

## Severity
Medium

## Domain
Infrastructure & Deployment

## Location
`pi-extension/src/daemon/install.ts:241`

## Evidence
```ts
const uid = userInfo().uid;
_tryExec("launchctl", ["bootout", `gui/${uid}`, unitPath], log);
_tryExec("launchctl", ["unload", unitPath], log);
_exec("launchctl", ["bootstrap", `gui/${uid}`, unitPath], log);
```

## Remediation direction
During the 0.1.0 install/upgrade path, detect the known pre-rebrand `dev.remotepi.supervisord` plist/label and explicitly stop and remove it before activating `dev.outpostpi.supervisord`, with idempotent tests and a clear log entry. If automatic removal remains intentionally out of scope, add an install-time blocking warning/check rather than relying only on a manual documentation step, so stale supervisor code cannot continue spawning agents alongside the new service.

## Implementation notes

- macOS install now runs idempotent cleanup for the legacy
  `dev.remotepi.supervisord` label and plist before activating Outpost-Pi, and
  reports that cleanup in the installer log.
- Added a pure command-plan regression for the legacy label and path.
- Changed `pi-extension/src/daemon/install.ts` and `src/daemon/install.test.ts`.
- Verified with `vitest run src/daemon/install.test.ts` (28 passed, 3 skipped)
  and `tsc --noEmit`.
