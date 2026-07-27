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

2026-07-27 (consolidated scanners recorded per gate):
- **gate-security** — 2 findings (both low, parked):
  `gate-security-cockpit-agent-boot-path-debugprint`,
  `gate-security-cockpit-stale-pair-dir-orphan-sweep` (its timeout-cleanup
  half is covered by the bound finalizer item). 6 verified-clean incl. seam
  write hardening, LSP stderr, RPC discriminator, file-viewer diagnostics.
- **gate-tests** — 1 finding (medium): pairing-gateway tests lacked
  exit/timeout/orphan cleanup coverage — covered by the bound finalizer
  item's acceptance; orphan-sweep test follows the parked sweep item.
- **gate-cruft** — no findings.
- **gate-docs** — 1 finding (high): stale pair-code row + RpcNotice dartdoc
  → `gate-docs-cockpit-rpc-protocol-pair-code-row` (bound, in fix wave).
- **gate-patterns** — no new patterns.
- **gate-refactor** — 2 findings (both high, lifecycle):
  `gate-refactor-pairing-gateway-finalizer-leaks`,
  `gate-refactor-ephemeral-pi-rpc-sigterm-no-await` (bound, in fix wave).
