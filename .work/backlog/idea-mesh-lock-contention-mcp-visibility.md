---
id: idea-mesh-lock-contention-mcp-visibility
created: 2026-10-04
updated: 2026-10-04
tags: []
---

Surface "folder busy" lock-contention failures through the MCP channel, not
only stderr.

Operator-relayed from the 2026-10-04 Claude-in-nextup bring-up: when
`_failLoud` exits after the 4 lock-acquire attempts, it writes the reason to
stderr — which Claude Code does not record — so the client sees a successful
handshake followed by "not connected" with no diagnostic. Candidate: report
the contention through the MCP protocol surface itself (e.g. an initialize
warning/capability note, or a degraded tool result naming the lock path and
holding pid) so clients log an actionable reason. Related context: resident
per-folder agents legitimately hold the lock (one mesh endpoint per folder);
the `OUTPOST_PI_MCP_CWD` override is the current workaround for a second
agent in the same folder.
