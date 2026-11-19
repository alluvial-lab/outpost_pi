---
id: story-mcp-endpoint-lock-ownership
kind: story
completed: 2026-10-06
tags: [pi-extension]
created: 2026-10-05
updated: 2026-10-06
---

# MCP endpoint lock ownership — name-scoped, coexisting, bounded, visible

Completed (`3be9f1836`, reviewed `808b7b79d`). Moved the Claude-host MCP mesh endpoint onto the shared `(cwd, name)`-scoped lock acquisition walk (`acquireUniqueNamedCwdLock` in `pi-extension/src/session/cwd_lock.ts`) with restart-race grace before suffixing (`<name>#2`), in-channel MCP warning notifications and actionable `degradedReason`, bounded shutdown exit timer, and SIGKILL re-acquisition tests; retired the `OUTPOST_PI_MCP_CWD` single-endpoint-per-folder workaround. Verified green across `pi-extension` (1206 tests + build) and `site` (lint + build). Full pre-migration story record preserved in Git history at `fa32d6abb`.
