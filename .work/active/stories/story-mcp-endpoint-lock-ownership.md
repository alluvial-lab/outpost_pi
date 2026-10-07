---
id: story-mcp-endpoint-lock-ownership
kind: story
stage: implementing
tags: [pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-05
updated: 2026-10-06
---

# MCP endpoint lock ownership — name-scoped, coexisting, bounded, visible

## Brief

The Claude-host mesh MCP endpoint (`pi-extension/src/mcp/mesh_server.ts`)
still acquires the LEGACY cwd-only lock (`acquireCwdLock(_cwd)` in
`tryJoinMesh`) even though every other participant moved to the
(cwd, name)-scoped lock (`plan/41`: `roomIdFor(cwd, name)` keys both the
App↔Pi room and the cwd lock, and the broker registers by (cwd, name)).
Field consequences:

- A Claude session in a folder with a resident Pi agent can never take the
  lock — both derive the default name → same legacy lock id. Fleet
  workaround in effect today: `OUTPOST_PI_MCP_CWD` pointing the Claude
  identity at a sibling dir (fleet-verified still open at the call site,
  2026-10-07 relay).
- Lock-contention failure exits via `_failLoud` → stderr only; Claude Code
  does not record MCP stderr, so the client sees a healthy handshake
  followed by "not connected" with no diagnostic.
- `shutdown()` runs `mesh.close()` best-effort with no bound — a wedged
  close hangs the process forever, pinning the UDS lock (orphaned lock).

Consolidated 2026-10-05 (operator-confirmed groom) from
`idea-mesh-lock-contention-mcp-visibility`,
`idea-mesh-server-orphan-lock-shutdown`,
`idea-multi-endpoint-per-folder-mesh`.

## Design

**Name-scoped acquisition with a coexistence suffix walk (single source).**
Extract the Pi side's suffix walk (`local_mesh_commands.ts`: try
`requestedName`, then `#2`, `#3`, … — the same scheme the broker's
`_uniqueIdentity` uses) into a shared helper beside the lock primitive in
`src/session/cwd_lock.ts`, and use it from BOTH the Pi command surface and
the MCP server. The MCP registers with the LOCKED name so lock identity and
broker identity agree (mirroring `lockedName` on the Pi side). MeshNode
construction moves after the lock walk (it is currently built at module
load under the pre-lock requested name).

**Grace before suffixing.** Keep the existing restart-race grace
(`MAX_JOIN_ATTEMPTS` × `JOIN_RETRY_MS`) on the REQUESTED name only: the
common single-endpoint folder keeps name stability across respawns, while
genuine same-name coexistence (Pi resident + Claude MCP in one folder)
suffixes after the grace. Full-walk exhaustion fails loud (pathological).

**In-channel contention visibility.** Contention surfaces through the MCP
surface itself, not only stderr: `degradedReason` (tool results) names the
lock path and state; add `logging/message` notifications (warning level) on
contention/timeout/suffix adoption so clients that surface log notifications
see an actionable reason without a tool call. The server instructions
reword to "requested name … verify your exact address via list_peers" so a
suffixed endpoint is not misnamed in-session.

**Bounded shutdown.** `shutdown()` arms a hard-exit timer (~3 s) around the
graceful `mesh.close()` sequence; the timer fires `process.exit(0)` if
teardown wedges, so the process — and its lock — can never linger. Lock
release under abrupt death stays OS-guaranteed (UDS); add an explicit
kill -9 subprocess test proving re-acquisition after SIGKILL (the gap the
existing cwd_lock tests punt on).

**Docs.** Durable docs implying one-MCP-endpoint-per-folder update to the
(cwd, name) coexistence semantics: multiple same-folder endpoints coexist
under suffixed names; folder broadcast reaches all of them; addresses
disambiguate.

## Simplification opportunity

The suffix walk currently lives inline in `local_mesh_commands.ts`; the
shared helper deletes that duplication. `_failLoud`'s stale "one agent per
folder" narrative simplifies into the name-scoped coexistence story.

## Acceptance criteria

- [ ] MCP acquires the (cwd, name)-scoped lock; a Claude MCP in a folder
      with a resident default-named Pi agent comes up as `<name>#2` after
      grace — retiring the `OUTPOST_PI_MCP_CWD` workaround
- [ ] Lock suffix walk lives in ONE place shared by the Pi command surface
      and the MCP server
- [ ] Contention produces in-channel logging notifications + an actionable
      degraded tool reason naming the lock path
- [ ] Shutdown is bounded: a wedged `mesh.close()` cannot pin the lock
- [ ] kill -9 re-acquisition test green; typecheck + full vitest suite +
      build green
