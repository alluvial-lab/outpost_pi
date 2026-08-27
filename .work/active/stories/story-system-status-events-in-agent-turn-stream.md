---
id: story-system-status-events-in-agent-turn-stream
kind: story
stage: implementing
tags: [pi-extension, bug, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# System status events must never become agent turn input

REOPENED 2026-08-27 (operator): this class was discarded in the 2026-08-26
groom as "unrecallable premise" (backlog-mesh-message-wake-interrupts-agent,
idea-same-pc-peer-presence-ux — both archived). The operator's correction:
it is NOT settled. Field evidence: after the 2026-08-27 extension restart,
the startup status ("Mesh name: outpost_pi / Relay connected") appeared in
the resumed session's agent-visible context (prefixed to the next user
message), and — per the operator — OTHER pi sessions in the fleet have
historically taken such banners as turn input and responded to them as if
user input.

## Reported behavior

- Startup/system status (mesh name assignment, relay connection state)
  reaches the AGENT-visible stream.
- In sessions without a following operator message, this can wake the agent
  into a turn that "responds" to a status line.

## Known anchors (incomplete — diagnosis must complete them)

- `outpost-pi:name-assigned` event: pi-extension/src/extension/command_surface/local_mesh_commands.ts:382 — sendPiMessage with `display: false`, no explicit triggerTurn — YET "Mesh name: ..." reached agent context.
- No single "Relay connected" emitter found in current extension source — the composite banner's second half must come from another path (relay transport status event? app-side? daemon RPC?).
- Open questions: does sendPiMessage(custom, display:false) land in the transcript regardless? Is there a relay-status event with turn semantics? Where exactly does the observed composite line originate?

## Fix direction (post-diagnosis)

System/status events belong on the notification/UI surfaces (ctx.ui.notify /
app system channel / footer), NEVER on any path that creates agent turn
input or transcript entries the agent treats as user speech. Startup banner
specifically: informational only.

## Acceptance

- Exact delivery path identified + documented with anchors.
- After fix: extension restart produces NO agent-visible status text (verified by resuming a session post-restart and inspecting context), and no fleet agent wakes to respond to startup status.
- Regression test: status-event emission does not enqueue any turn-triggering message (unit-level at the emission boundary).
