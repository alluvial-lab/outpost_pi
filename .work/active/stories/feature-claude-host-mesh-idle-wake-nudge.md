---
id: feature-claude-host-mesh-idle-wake-nudge
kind: story
stage: implementing
tags: [pi-extension, workflow]
parent: feature-claude-host-mesh-idle-wake
depends_on: [feature-claude-host-mesh-idle-wake-qualification]
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Nudge-style wake notification

Design element: Unit 3 of `feature-claude-host-mesh-idle-wake`.
**Void condition**: if the qualification story kills the channel-notification
lane (Q2 fails, sampling fallback activates), this story voids — the content
shape is channel-lane-specific.

## Work

`pi-extension/src/mcp/mesh_server.ts`:

- Extract `wakeNudgeContent(from: string): string` — nudge text naming the
  sender and directing `get_messages` + `re` reply; deliberately NO message
  body (single authoritative drain surface — a body would let the model
  reply without draining, leaving a stale inbox duplicate).
- `onMessage` handler uses it for the `notifications/claude/channel` params;
  no-op catch comment updated to name the nudge contract.
- `pi-extension/skills/agent-network/SKILL.md` (repo source): document wake
  mode — a nudge may arrive before/without a drain; turn-start
  `get_messages` drain stays mandatory (fallback + authoritative surface).

## Acceptance evidence

- New focused unit test for `wakeNudgeContent`: contains sender address,
  names `get_messages`, contains no body payload
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
- Skill source updated
