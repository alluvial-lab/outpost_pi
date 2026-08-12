---
id: backlog-cockpit-v040-hardening
created: 2026-08-11
updated: 2026-08-11
tags: [cockpit, security]
---

# Cockpit hardening gaps introduced by prior fixes

## Origin
gate-security-regression SR3 (Medium) + SR4 (Low), v0.4.0; both hardening-introduced.

## Findings
- cockpit/.../validators/file_name_validator.dart:41-63 — _normalize converts \\server\share\repo to //server/share/repo, drops empty leading components, reconstructs /server/share/repo: no longer a UNC path. A valid filename is returned beneath a different local rooted path, defeating containment for UNC-backed workspaces. Use platform-aware path parsing preserving UNC/device roots; compare canonical child parent vs canonical original parent; add UNC-parent tests.
- cockpit/.../relay/pairing_seam_cleanup.dart:14-31 — sweep deletes every owner-private outpost-pi-pair-* dir without age/token-expiry/process-ownership check; a second Cockpit starting while the first is pairing can delete the first's live token-bearing seam. Delete only provably stale seams (expiry/age beyond token lifetime + PID/liveness or exclusive-lock marker).
