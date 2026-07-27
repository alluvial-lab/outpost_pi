---
id: release-cockpit-v0.3.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: null
created: 2026-07-27
updated: 2026-07-27
---

# Release cockpit-v0.3.0

Component release for the Flutter desktop cockpit (tag prefix `cockpit-v`).
Companion to repo v0.3.0 (paired arc shipped there). Binds the
cockpit-attributed items from that arc plus the pairing-surface repair that
followed the TUI-only pair-code security change.

## Bound items

Active done items (5), bound 2026-07-27:

- gate-cruft-cockpit-pair-code-consumer-dead (bound during the v0.3.0 drain;
  cockpit pairing moved to the OUTPOST_PI_PAIR_CODE_FILE seam)
- gate-security-cockpit-temp-workspace-trace
- gate-security-formatter-reload-diagnostics-path-disclosure
- gate-security-lsp-stderr-logged
- gate-security-rpcunknown-retains-wire-discriminator

Archived stub (1), late-bound 2026-07-27 per operator decision:

- gate-security-pair-code-file-preexisting-perms-window (seam hardened:
  exclusive-create 0600 temp, fsync, symlink/pre-existing rejection, atomic
  rename; closed during the cockpit pair-code fix)

## Gate runs

Pending.
