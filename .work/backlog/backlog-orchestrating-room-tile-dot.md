---
id: backlog-orchestrating-room-tile-dot
created: 2026-08-29
updated: 2026-08-29
tags: [app, ux]
---

# Room-list dot should reflect the orchestrating state (not plain green)

**ABSORBED 2026-08-29** → `story-orchestrating-room-tile-dot` (active;
design decided with operator: pulsing blue, no new token). Details below
are the original UAT feedback record.

Operator UAT feedback on v0.11.0-rc.1 (2026-08-29, live-verified chip):
while a room's agent is orchestrating (background work active — chat chip
shows `orchestrating…`), the HOME-SCREEN / room-list tile still renders
the plain green dot, reading as idle/ready-for-input. From the room list
an operator cannot distinguish "agent is working in the background" from
"waiting for you" without opening the chat.

## Direction

The room snapshot already carries `RoomInfo.background` (same source the
chat chip projects). Consume it in the room-list tile: when
`background` is true (and `working` false), render the dot in the same
family as the chat's orchestrating treatment (not `colors.success`).
Match the chat chip's precedence: `working` > `background` > idle-green.
Widget test mirroring the chat chip's three-state cases at the tile
level.

Small app-only change. Natural companion for the next patch lane
(candidate pairing: `backlog-new-wedge-bare-pi-room-teardown-without-exit`).
