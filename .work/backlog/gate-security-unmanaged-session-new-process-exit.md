---
id: gate-security-unmanaged-session-new-process-exit
kind: story
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-29
updated: 2026-08-29
---

# Authenticated session replacement can terminate an unmanaged Pi process

## Severity
Medium

## Domain
API Security

## Location
`pi-extension/src/index.ts:3297`

## Evidence
```ts
if (!_isFreshSessionRestartManaged()) {
  process.exit(EXIT_FRESH_SESSION);
  break;
}
```

A `session_new` frame reaches this branch only after owner-channel authentication, typed decoding, replay protection, and current-session validation, so this is not an unauthenticated kill primitive. It nevertheless maps a remotely supplied session-level action directly to host-process termination when the command capability is temporarily unavailable and neither managed-restart environment flag is set. In that bare-launch case exit code 42 has no local consumer: `scripts/pi-restart-loop.sh` treats 42 specially only after setting `OUTPOST_PI_UNDER_RESTART_WRAPPER=1`, while an unmanaged shell simply loses the Pi process. This also contradicts the wrapper's safety invariant that only the wrapper and daemon supervisor may convert mobile `/new` into process exit. A compromised paired client or another authorized Owner can therefore turn a transient missing-context state into persistent room unavailability for every attached Owner.

## Remediation direction
Preserve the managed-only process-exit boundary. In unmanaged mode, complete replacement through a fresh in-process command capability or reject before any destructive teardown while keeping the owner runtime available. If a terminal fallback remains necessary, require an explicit locally established restart owner/opt-in and route it through the existing fence, accepted-delivery drain, acknowledgement/reset, and teardown coordinator instead of calling `process.exit` directly from the message router.
