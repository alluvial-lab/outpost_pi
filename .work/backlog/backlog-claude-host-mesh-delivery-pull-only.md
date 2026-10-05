---
id: backlog-claude-host-mesh-delivery-pull-only
created: 2026-10-04
updated: 2026-10-04
tags: [pi-extension, workflow]
---

# Claude-host mesh message delivery is pull-only — idle Claude sessions never see inbound mesh messages

Operator finding (2026-10-04, piloting the Claude session in claude-nextup;
relayed via the projects-root fleet session):

The agent-network skill surfaces inbound mesh messages on Claude hosts via
the `get_messages` MCP tool — pull-only. An IDLE Claude session therefore
never sees inbound mesh messages until the operator starts a turn to jostle
it. On Pi, the harness delivers messages into the turn; Claude Code has no
equivalent wake.

Operator impact: cross-app coordination stalls whenever the Claude side is
idle (the Pi side sends, nothing on the Claude host consumes until a human
touches it).

Candidate directions recorded by the operator (unscoped, unranked):

- (a) MCP server→client sampling request from `mesh_server` when an inbound
  message lands — if Claude Code honors sampling requests, that starts a
  turn.
- (b) Push a nudge through the remote-control HTTP channel the claude-rc
  session already exposes.
- (c) A Claude Code hook (e.g. PreCompact / UserPromptSubmit) that
  force-checks `get_messages`, at minimum bounding the delivery latency.

Context pointers: fleet CHANGELOG 2026-10-04 (projects root); tmux session
`claude-nextup`.
