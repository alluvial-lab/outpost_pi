---
id: feature-claude-host-mesh-idle-wake-qualification
kind: story
stage: implementing
tags: [pi-extension, workflow]
parent: feature-claude-host-mesh-idle-wake
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Live qualification: does the channel-notification wake start an idle Claude turn?

Design element: Unit 1 of `feature-claude-host-mesh-idle-wake` (the trickiest
unit — everything downstream gates on this evidence).

## Protocol

Run from this repo's session (this agent is a mesh peer and can drive sends);
record command + observation + timestamp into the feature body under
`## Qualification evidence`:

1. **Q1 enablement paths** — Claude Code build on this box: flag inventory
   (`claude --help`), settings/env equivalents for development channels,
   version string.
2. **Q2 wake semantics** — scratch folder, `outpost-pi claude <dir>
   --dangerously-load-development-channels server:outpost-pi-mesh` in a tmux
   pane; idle; Pi peer sends a message; observe whether a turn starts, what
   the channel input does, and busy-wake behavior (message during an active
   turn).
3. **Q3 spawn timing** — fresh session, same launch: is the MCP server
   process alive before any tool call? If not, record sender-side ACK status
   pre-first-spawn and post-spawn drain — pins the from-launch gap.
4. **Q4 conditional** — only if Q2 fails: sampling-request probe in a scratch
   copy (not the product tree).

Operator authorization: standing (2026-10-04, "I'd at least want it on
here"). Idle panes cost nothing; woken turns cost one roundtrip.

## Acceptance evidence

- Q1–Q3 observations + Claude Code version recorded in the feature body
- Lane decision recorded (channel-notification lands / sampling fallback
  activates) with rationale
- Lazy-spawn verdict + docs stance chosen

## Ordering

No dependencies. Units 2 (`-toggle`) and 3 (`-nudge`) depend on this story's
lane decision.
