---
id: feature-claude-host-mesh-idle-wake
kind: feature
stage: drafting
tags: [pi-extension, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Claude-host mesh idle wake — reliable inbound-message delivery to idle Claude sessions

## Brief

On Pi hosts, inbound mesh peer→agent messages are delivered into the agent's
turn (with busy-batching, flush at `agent_settled`). On Claude hosts the
agent-network skill surfaces messages via the `get_messages` MCP tool —
pull-only — so an idle Claude session never sees inbound mesh messages until
the operator starts a turn to jostle it. Cross-app coordination stalls
whenever the Claude side is idle (observed 2026-10-04, claude-nextup session).

This feature closes that gap: qualify a wake mechanism that makes inbound
mesh messages reach an idle Claude Code session without human jostling, and
land the chosen mechanism as a first-class (toggleable) launcher capability
of `outpost-pi claude`.

Origin: operator finding via the projects-root fleet session (2026-10-04,
fleet CHANGELOG); parked as `backlog-claude-host-mesh-delivery-pull-only`,
promoted same day.

## Strategic decisions (scoped 2026-10-04)

- **Mechanism: qualification-first, not pre-committed.** Empirically qualify
  the existing `notifications/claude/channel` wake end-to-end before building
  anything new; fall back to the MCP server→client sampling-request lane only
  if the dev channel proves unreliable. — The wake already exists server-side;
  the unknowns are qualification facts.
- **Default posture: wake ON for this fleet's Claude sessions** (operator:
  "I'd at least want it on here"), exposed as a wrapper toggle rather than a
  silent hard-wired default. — Pi hosts already wake by default; the box's
  operator-piloted sessions want parity. Public/default posture for other
  consumers is a design-time call informed by qualification (dev-channel
  stability risk).
- **rc-HTTP-nudge lane: out of scope here — handed to NextUp.** The
  remote-control HTTP channel is a NextUp-side surface; the candidate nudge
  lane was handed to the NextUp resident agent (mesh handoff 2026-10-04) and
  is parked there as `mesh-idle-wake-rc-nudge` (nextup commit 93f4ae2), with
  pickup conditions (this feature qualifies+lands; rc channel verified able
  to inject a turn noninteractively) and a void-if-covered condition (voids
  if the channel-notification path here fully covers idle wake). Their side
  will coordinate on-mesh before implementing — double-wake race (rc
  injection + channel notification) is the noted interaction to avoid.
  This feature stays single-repo (mesh-server + wrapper + skill + docs).

## Grounding (scoping evidence)

- The server side already fires the wake: `mesh_server.ts` pushes
  `notifications/claude/channel` on every inbound peer message (broker/system
  presence envelopes filtered out), with a no-op catch when channels aren't
  enabled. It works only when Claude Code is launched with
  `--dangerously-load-development-channels server:outpost-pi-mesh` — per
  current docs the ONLY known enablement path; the wrapper forwards such
  flags verbatim but never passes this one itself.
- The 2026-10-04 claude-nextup session ran the mesh MCP staged on **lazy
  spawn** — while idle the server process may not exist: nothing subscribes
  to the broker, nothing buffers, nothing can notify. At least two candidate
  causes for the observed pull-only behavior: flag absent, and/or server not
  alive while idle.
- Candidate directions from the operator finding: (a) MCP sampling request
  when a message lands (if Claude Code honors sampling, that starts a turn);
  (b) rc-HTTP nudge — deferred to NextUp per strategic decisions; (c) Claude
  Code hooks that force-check `get_messages`. Hooks cannot wake a truly idle
  session (no hook events fire while idle — they only cover turn boundaries,
  which the skill's turn-start discipline already covers): expect
  evaluate-and-drop unless qualification proves otherwise.
- Pi-side contrast: `_deliverMeshMessageToAgent` injects and triggers the
  turn, batching while busy (landed after the characterized interruption
  complaint, archived `backlog-mesh-message-wake-interrupts-agent`). Claude
  hosts have no equivalent.
- Code surfaces (all this repo): `pi-extension/src/mcp/mesh_server.ts`,
  `pi-extension/src/extension/command_surface/standalone_cli.ts`
  (`outpost-pi claude` launcher + flag passthrough),
  `pi-extension/skills/agent-network/SKILL.md` (source; `~/.pi/remote` is the
  deployed copy), `site/src/app/tutorials/claude-mesh/page.tsx`,
  `pi-extension/README.md`.

## Qualification ladder (design inputs, not a plan)

1. Enumerate Claude Code enablement paths for the channel notification
   (flag is documented; settings.json/env equivalent — unknown, verify
   against current Claude Code).
2. Qualify the existing wake live: relaunch a Claude mesh session with the
   flag, send it a mesh message while idle, observe whether a turn starts;
   repeat with the MCP lazily-spawned vs already-running to pin the lazy-spawn
   interaction (does a down server mean dropped messages, or does the broker
   queue for absent peers?).
3. If the dev channel is unreliable: qualify the sampling-request lane
   (does Claude Code honor server-initiated sampling on this build? approval
   UX for operator-piloted sessions?).
4. Hooks lane: confirm the idle-no-events premise; expected evaluate-and-drop.

## Simplification opportunity

If a wake lands as the primary delivery path, the agent-network skill's
every-turn `get_messages` discipline demotes from primary mechanism to
fallback (skill-doc simplification; the tool itself stays — it remains the
drain/replay surface and the no-wake default for consumers who don't opt in).
The `mesh_server.ts` no-op catch comment ("channels not enabled — get_messages
polling covers it") would then describe the fallback, not the norm. Nothing
identified for outright deletion.
