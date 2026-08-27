---
id: story-system-status-events-in-agent-turn-stream
kind: story
stage: review
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

## Diagnosis

The reported banner was two adjacent Pi custom messages, not one composite
aggregator:

1. `session_start` activates the runtime and calls `ensureStarted` at
   `pi-extension/src/extension/composition_root.ts:84-122`.
2. Returning-user startup runs local mesh join and then relay start at
   `pi-extension/src/extension/command_surface/local_mesh_commands.ts:100-174`.
3. Before this fix, join called `sendPiMessage` from
   `local_mesh_commands.ts:379-386`, with content `Mesh name: <assigned>`.
4. Successful relay startup calls the relay adapter's deduplicated state emitter
   at `pi-extension/src/extension/relay_transport.ts:609`; reconnect, close, and
   stop emit at lines 480, 544, and 630. Before this fix, index projected that
   snapshot through `sendPiMessage` at `pi-extension/src/index.ts:1148-1158`,
   with content `Relay ${snapshot.status}` — the precise source of
   `Relay connected`.
5. Pi SDK docs state that all `pi.sendMessage` custom messages participate in
   LLM context (`docs/extensions.md:1398-1419`). Installed SDK code confirms the
   no-trigger idle path pushes the message into `agent.state.messages` and
   appends a durable `custom_message` entry
   (`dist/core/agent-session.js:1071-1099`). `display:false` controls rendering
   only. With no `triggerTurn`, an idle status waits in context for the next
   prompt; while streaming, the default delivery path can steer the active run.

`_notify`/`ctx.ui.notify` was not the leak: interactive mode renders a UI notice,
and RPC mode emits `extension_ui_request` without adding a session message. The
daemon RPC child consumes stdout and does not synthesize the composite; the same
mode-independent `sendMessage` calls above were the only startup path into model
context. Other system-only custom-message emitters (`paired` and
`mesh-revoked`) had the same latent defect and were moved with the two reported
emitters. Intentional agent inputs remain unchanged: admitted mesh messages and
capture-delivery prompts still use explicit turn-triggering message delivery.

## Implementation notes

- Execution capability: direct inline implementation; one cross-component RPC
  status boundary with a small, cohesive write set.
- Review weight: standard (project default); standalone-story bounded inline
  review follows this implementation commit.
- Files changed: `pi-extension/src/extension/system_status_event.ts`, status
  emitters and tests under `pi-extension/src/`; Cockpit RPC mappers, pairing
  gateway, tests, and `cockpit/docs/rpc-protocol.md`; durable Pi extension skill
  guidance.
- Tests added: SDK-context reproduction and RPC UI non-enqueue regression;
  startup/relay emission assertions that `sendMessage` is never called; Cockpit
  typed status and ephemeral pairing-consumer coverage.
- Simplification: removed `sendPiMessage` from mesh/control/pairing status ports;
  all four schema-owned system status types now share one UI-only emitter.
- Discrepancies from design: the legitimate structured consumer is dormant
  Cockpit (not the mobile app); mobile owner status continues through room/app
  protocol metadata and was not changed.
- Adjacent issues parked: none.

## Verification evidence

- Failure reproduction: an in-memory SDK session with the two `display:false`
  custom messages rebuilt both in `buildSessionContext()`.
- Break-it proof: temporarily restored `_sendPiMessage` in the status boundary;
  the startup regression failed with two calls (`name-assigned`, `relay-state`),
  then passed after restoration.
- `pi-extension`: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  passed — 61 files, 1106 passed, 3 skipped.
- `cockpit`: `flutter analyze && flutter test` passed — 319 tests.
- Restart/resume smoke: launched a persisted isolated Pi RPC session with the
  built extension, restarted it with `--continue`, observed the structured
  startup status both times, and `get_messages` returned zero messages before
  and after resume (`statusContextLeaks: 0`).
- Shared mobile protocol was not changed; the mobile app suite was not required.
