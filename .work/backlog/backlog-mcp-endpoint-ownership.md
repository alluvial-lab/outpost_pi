---
id: backlog-mcp-endpoint-ownership
created: 2026-10-05
updated: 2026-10-05
tags: [pi-extension, workflow]
---

# MCP endpoint ownership and same-folder coexistence

One lock-ownership lifecycle for the Claude-host mesh MCP endpoint: surface folder-busy contention through the MCP channel (not only stderr), bound the shutdown sequence (timer → hard exit) so the cwd lock never orphans, and name-scoped lock acquisition so multiple endpoints can coexist per folder. Folded from three ideas sharing the lock-ownership lifecycle.

Consolidated 2026-10-05 by operator-confirmed groom merge from: idea-mesh-lock-contention-mcp-visibility, idea-mesh-server-orphan-lock-shutdown, idea-multi-endpoint-per-folder-mesh.
Scope-promote via /agile-workflow:scope when wanted.
