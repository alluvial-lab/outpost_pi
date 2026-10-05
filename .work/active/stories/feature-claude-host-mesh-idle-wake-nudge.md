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

# Edge-triggered coalesced wake notification

Design element: Unit 3 of `feature-claude-host-mesh-idle-wake`. Reshaped by
the Opus review: coalescing + rate cap designed in (not deferred to
qualification observation), untrusted-input handling, honest catch comment.
**Void condition**: if the qualification story kills the channel lane, this
story voids.

## Work

`pi-extension/src/mcp/mesh_server.ts`:

- Extract testable pure helpers:
  - `wakeNudgeContent(from: string): string` — nudge text naming the
    sender (escaped — untrusted input) and directing `get_messages` + `re`
    reply; NO message body (single authoritative drain surface).
  - `shouldWake(inboxLengthBefore: number): boolean` — edge trigger: true
    only on empty→non-empty transition.
- `onMessage` handler: push to inbox, notify only on the edge, re-arm when
  `get_messages` drains to empty. Burst/broadcast → one wake.
- Global wake rate cap (floor on notification frequency, e.g. min interval
  between notifies) as the two-peer ping-pong backstop; the inbox never
  drops messages — only additional wakes are suppressed.
- Replace the misleading `.catch` comment: no wake-state detection exists
  (un-opted clients silently ignore custom notifications; the catch covers
  transport errors only).
- `pi-extension/skills/agent-network/SKILL.md` (repo source): wake-mode
  note (nudge may arrive before/without a drain; turn-start drain stays
  mandatory) + delivered-semantics precision (received = buffered by the
  peer's MCP process, not handled; inbox is in-memory, dies with the
  process).

## Acceptance evidence

- Unit tests: nudge content (sender escaped, names get_messages, no body);
  edge-trigger (burst → one wake, drain re-arms); rate-cap suppression
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
- Skill source updated
