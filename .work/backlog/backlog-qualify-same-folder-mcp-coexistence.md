---
id: backlog-qualify-same-folder-mcp-coexistence
created: 2026-10-06
updated: 2026-10-06
tags: [pi-extension, workflow]
---

# Qualify Claude+Pi same-folder MCP coexistence live; retire OUTPOST_PI_MCP_CWD

Name-scoped lock acquisition for the mesh MCP landed on trunk
(story-mcp-endpoint-lock-ownership: grace-then-`#N`-suffix coexistence walk,
in-channel contention visibility, bounded shutdown). It is a local trunk
capability until a release installs it — the fleet's Claude sessions still
run the deployed v0.13.0-era MCP, and the fleet runbook's
`OUTPOST_PI_MCP_CWD` sibling-dir workaround stays in effect until this
qualification passes.

Qualification lane (run on the deployed build, live):

- Deploy/refresh the extension build containing the name-scoped lock.
- A Claude MCP in a folder with a resident default-named Pi agent comes up
  as `<name>#2` within ~8s (grace) — visible via `list_peers`; wake nudge
  and folder broadcast reach both endpoints; contention produces the
  in-channel logging notification.
- Pi-side `/outpost-pi` behavior unchanged (Backoffice#2 semantics).
- Kill -9 an MCP holder; the next spawn re-acquires cleanly.

Retirement condition: on pass, drop `OUTPOST_PI_MCP_CWD` from the fleet
Claude launch surfaces and update the fleet runbook. Preferred stable
address instead of a suffix: set `OUTPOST_PI_MCP_NAME` (or `--name`) on
the Claude session.

This is also the natural slot for the live e2e wake/coexistence lane the
v0.13.0 review noted as the residual coverage gap.
