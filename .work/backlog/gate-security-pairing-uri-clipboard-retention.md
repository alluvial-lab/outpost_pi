---
id: gate-security-pairing-uri-clipboard-retention
kind: story
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-28
updated: 2026-08-28
---

# Pairing clipboard action leaves a live enrollment capability in ambient clipboard state

## Severity
Low

## Domain
Data Protection

## Location
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:113`

## Evidence
```ts
await this.clipboard.copy(this.qrUri);
this.copyState = "copied";
```

`qrUri` includes the active one-time pairing token (`pi-extension/src/pairing/qr.ts:111-114`). Copying is explicit and the token expires quickly, but OSC 52 places the complete enrollment capability in system clipboard state, where clipboard managers, synchronization services, or other local applications may retain or read it during the validity window. A token holder can authenticate with its own Owner key and enroll while the token remains usable.

## Remediation direction
Warn that the copied value is a short-lived enrollment secret and keep its validity visibly bounded. Where a trustworthy native clipboard adapter can verify that the clipboard still contains the same value, clear it after expiry without overwriting newer user content; otherwise document the clipboard-history/sync exposure and consider issuing a shorter-lived token specifically for copy.
