---
id: release-v0.13.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: null
created: 2026-10-05
updated: 2026-10-05
---

# Release v0.13.0

Feature-lane minor cut. Full e2e battery + six gates + operator UAT per
policy. Cut autonomously to the UAT checkpoint; tag/publish operator-gated.

## Bound items

Active done (9):
- feature-claude-host-mesh-idle-wake (+ child stories -qualification,
  -toggle, -nudge) — Claude-host mesh idle wake (qualification, toggle,
  coalesced notification, cross-model reviewed)
- gate-security-mcp-inbox-unbounded — bounded MCP inbox (byte-accurate,
  linear drain rendering)
- gate-security-mcp-tmp-config-path — ephemeral MCP config hardening
- gate-cruft-launcher-copy-semantics-test — low-value test removed
- gate-cruft-verdict-archaeology-comments — incident narrative trimmed
- gate-patterns-inconsistency-settle-sleep — deterministic test barriers

Late-bound archived stubs (3):
- gate-cruft-misnamed-bounded-test-mailbox-shim (done atop earlier baseline)
- gate-cruft-unused-parse-hello-wrapper (done atop earlier baseline)
- gate-tests-join-adoption-room-binding (done atop v0.12.1-era baseline)

## Gate runs
(populated by gates)
