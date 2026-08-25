---
id: idea-mobile-conflates-transport-and-agent-state
kind: story
stage: done
tags: [app, pi-extension, ux, design, architecture]
parent: feature-mobile-tui-parity-chat-resilience
depends_on: [feature-mobile-tui-parity-chat-resilience-status-projection]
release_binding: v0.2.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-20
---

# Mobile status pill conflates transport/connection state with agent/turn state

## Root insight (operator 2026-07-02)

The mobile chat status indicator mixes two orthogonal state machines into one
flattened, priority-ordered enum, losing granularity and producing misleading
labels. This is the structural root cause behind both:

- `idea-mobile-no-stop-button-while-awaiting-tool` (no "waiting" status, no
  Stop during tool execution)
- `idea-mobile-no-steering-indicator-when-queued` (no queued/steering
  indicator)

## The conflation (grounded)

`lib/ui/chat/chat_page.dart:172` renders the status as a single priority chain:

```
working > reconnecting > online > offline
```

These flags come from **two different axes**:

| Axis | States | Source |
|---|---|---|
| **Agent / turn** | working (thinking) · awaitingTool · streaming · idle | `_turnProjection.working` (`vm.isWorking`) |
| **Transport / connection** | connected (online) · reconnecting · offline | `vm.isRoomLive` (relay room live), `isReconnecting`, `peerPresence` |

The pill picks the highest-priority flag that's true. "online" is the fallback
for "connected AND not working" — which collapses two genuinely different
agent states:

- **idle but connected** → "online" (correct)
- **awaiting tool result but connected** → "online" (WRONG — looks idle)

So `awaitingTool` falls through to "online" and becomes indistinguishable from
idle. Same structural flattening is why the Stop button (gated on the narrow
`streaming` flag, not broad `working`) disappears during tool waits, and why
there's no room for a "queued/steering" indicator — the enum has no slot for
"working on prompt A, prompt B queued."

## Why the data model already supports the fix

`AppTurnStatus` (`app/lib/domain/session_state.dart`) is already a proper
turn-state enum with `idle · working · awaitingTool · streaming · done ·
error · stale` — agent state is modeled correctly in the domain. The
conflation happens at the **projection/UI layer** where the two axes get
flattened into one ordered label, and where the relay's `room_meta` only
carries a single `working` bit (`RoomTurnProjection` has only idle/working/
stale — no `awaitingTool`).

So the fix has two parts:

1. **Keep the two axes separate in the UI projection** — don't collapse
   transport state and agent state into one priority enum. The pill (or its
   replacement) should compose: a transport indicator (connected/reconnecting/
   offline) × an agent indicator (idle/working/waiting/streaming/queued).
2. **Extend the wire/room_meta signal** so `awaitingTool` reaches the app as
   distinct from `working`/`idle`, not collapsed into the single `working`
   bit. Either publish turn-phase in `room_meta` or rely on the existing
   `tool_request`/`tool_result` transcript events to derive `awaitingTool`
   app-side (the domain model already has it; it's the room_meta shortcut
   that loses it).

## Candidate decomposition (for design time — not decisions)

Treat them as orthogonal:

- **Transport dot** (connection health): green=reconnect-live, amber=
  reconnecting, gray=offline. Answers "is the pipe up?"
- **Agent status label** (turn state): "working…" (thinking) · "waiting…"
  (awaiting tool) · "queued" (steering pending) · (nothing when idle).
  Answers "what is the agent doing?"
- **Stop button**: gated on broad `working` (the whole active turn, including
  `awaitingTool`), not narrow `streaming`. `cancelTargetId` is already
  populated whenever `working` is true.

This resolves all three symptom findings with one structural correction
instead of three independent UI patches.

## Followup at design time

- Decide the final visual: two indicators (dot + label) vs one composed pill
  with more states. The pi TUI's separation (gray steering indicator distinct
  from the working/turn indicator) is the reference.
- Decide whether `awaitingTool` is derived app-side from `tool_request`/
  `tool_result` events (no wire change) or pushed explicitly via `room_meta`
  (wire change). The former keeps the relay `working` bit as-is; the latter
  enriches room_meta. Single-source-of-truth: prefer deriving from existing
  transcript events over adding a parallel `room_meta.working_phase` unless
  there's a reason the transcript events don't reach in time.
- Confirm the `scan-protocol-contract` single-source-of-truth rule: turn
  phase should be defined once (the `AppTurnStatus` enum) and derived
  everywhere, not re-enumerated in the pill, the Stop gate, and the dot.

## References

- `app/lib/ui/chat/chat_page.dart:170-182` — the flattened priority pill.
- `app/lib/ui/chat/chat_page.dart:99-106` — `isOnline`/`isReconnecting`/
  `isWorking` sourced from two different axes.
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:90-101` — `isRoomLive`
  (transport) vs `isWorking` (agent).
- `app/lib/domain/session_state.dart` — `AppTurnStatus` (correct agent enum),
  `RoomTurnProjection` (transport-flavored, only idle/working/stale).
- `pi-extension/src/index.ts:476` — `_publishWorking` publishes the single
  `working` bit via room_meta.

## Relationship to symptom items

This is the **parent structural finding**. The two symptom items are
projections of it:
- `idea-mobile-no-stop-button-while-awaiting-tool`
- `idea-mobile-no-steering-indicator-when-queued`

Fixing this properly subsumes both; fixing them piecemeal without this
correction would leave the conflation in place.

## Design

**Disposition: structurally subsumed / provenance.** The implementation
checkpoint is
`feature-mobile-tui-parity-chat-resilience-status-projection`. It replaces the
flattened booleans and priority label with a composed transport + existing
`AppTurnProjection` + steering model. This finding closes when that unit's
independent-axis, awaiting-tool Stop, and steering-indicator evidence is green;
it does not receive a second implementation patch.

## Implementation

Closed as structurally subsumed by
`feature-mobile-tui-parity-chat-resilience-status-projection`. Commit
`71a3937` replaced the flattened priority status with independent typed
transport, existing turn, and steering projections; the transport × turn table
and awaiting-tool cancellation regression are green.
