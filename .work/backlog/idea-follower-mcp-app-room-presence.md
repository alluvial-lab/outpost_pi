---
id: idea-follower-mcp-app-room-presence
created: 2026-10-07
updated: 2026-10-07
tags: [pi-extension, mcp, relay, claude-lane, design]
---

# Follower MCP gets no App↔Pi room presence (leader-gated bridge)

Found while fixing the stale-Claude-session-online incident (2026-10-07):
the Claude lane's mesh MCP holds its (cwd,name)-scoped lock and joins the
local broker correctly, but its App↔Pi relay room WS is opened only by
`MeshNode._maybeBridge` when the node **leads** the broker
(`session/mesh_node.ts` ~line 200: `if (!broker) return;` — broker remote
exists only on the leader). The header comment says "as a follower it rides
the existing leader's bridge" — but that transit covers cross-PC (room
`main`) only: relay logs show a leader pi holds exactly its OWN room WS plus
the mesh plane, never sibling agents' rooms.

Consequence: with a pi leading the local broker, a follower MCP's room
(e.g. the Claude lane's `roomIdFor(worktree, name)`) has NO member at the
relay — the mobile app's tile stays offline and phone→Claude delivery has no
path, even though the lane itself is healthy. Tonight the room came online
only when the MCP incidentally became leader mid-fleet-churn (relay log
03:46:50Z, broker re-created under it during the herdr sweep), and went
member-less again when the lane respawn made it the youngest agent.

Scope when promoted (design question first):

1. Decide the intended contract: does the leader bridge sibling agents'
   App↔Pi rooms (per plan/41 sibling publication), or should every MeshNode
   open its own room WS regardless of leadership (leader-gating only the
   cross-PC `main` bridge)?
2. Whatever the answer, add a regression test pinning follower-room
   presence behavior; tonight's incident is the repro narrative.
3. Fleet-runbook note until resolved: after a Claude-lane respawn, the
   lane's app presence returns on the next broker re-election it survives
   (fleet fresh-bounce with the lane up) — not at lane boot.
