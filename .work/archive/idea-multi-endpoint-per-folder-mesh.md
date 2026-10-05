---
id: idea-multi-endpoint-per-folder-mesh
created: 2026-10-04
updated: 2026-10-05
tags: []

status: folded
folded_into: backlog-mcp-endpoint-ownership
---

Documented support for two agents sharing one folder's mesh via the broker.

Operator-raised third candidate from the same bring-up. Today the Claude
mesh adapter calls `acquireCwdLock(_cwd)` with no name — one mesh endpoint
per folder — so a Claude session in a folder with a resident Pi agent can
never take the lock (workaround in the field: `OUTPOST_PI_MCP_CWD` pointing
the Claude identity at a sibling/worktree dir). Substrate partially exists:
`cwd_lock.ts` already keys locks by (cwd, name) ("several agents can run in
the same cwd"), and broker registration is (cwd, name)-addressed. Candidate:
name-scoped lock acquisition for the MCP adapter (e.g. derived from
agent_name or an explicit flag) plus documented semantics/UX for
folder-scoped broadcast with multiple same-folder endpoints.
