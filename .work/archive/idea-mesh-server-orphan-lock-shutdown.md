---
id: idea-mesh-server-orphan-lock-shutdown
created: 2026-10-04
updated: 2026-10-05
tags: []

status: folded
folded_into: backlog-mcp-endpoint-ownership
---

Orphaned mesh_server processes must not hold a per-folder cwd lock
indefinitely.

Operator-relayed from the 2026-10-04 Claude-in-nextup bring-up: a host
Claude Code session died and its mesh server went with it (no orphan that
time), but the general hazard stands. Nuance from source: `mesh_server.ts`
already registers `process.stdin.on("end"|"close", shutdown)` and
`transport.onclose = shutdown`, and the UDS lock has dead-socket detection —
so the residual gap is a shutdown path that can hang (e.g. `mesh.close()`
wedged on a broker socket) leaving the lock file held, and/or detection
latency before the next contender treats the holder as dead. Candidate:
bound the shutdown sequence (timer → hard exit) and verify lock release
under abrupt host death (kill -9 patterns) in a test.
