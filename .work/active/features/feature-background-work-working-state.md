---
id: feature-background-work-working-state
kind: feature
stage: drafting
tags: [pi-extension, app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Background work should hold the working state — not a bare "online" bubble

## Brief

While the agent waits on background tools/subagents (e.g. an e2e battery
worker), the app shows only the single "online" bubble. The sole cue that
we're waiting is the agent's own prose ("I'll report when it lands") —
fragile, purely conventional, and invisible if the narration is missed.
The working projection must reflect harness-side background work, so the
operator can trust the status surface instead of agent narration.

Field report (operator, 2026-08-27, during the v0.10.1 release e2e
battery): the orchestrator agent waited on a long-running background
worker; the app showed a bare online bubble throughout.

## Root shape

The `working` projection derives from the SDK turn lifecycle: turn ends →
agent_settled → working=false. Background agents (pi-subagents tasks) run
harness-side beyond any turn — the room/app has no signal that
orchestrator work continues.

## Candidate directions (design time)

1. **Extension-side bridge**: the pi-subagents package owns live agent
   state (it queues/schedules them) — if outpost-pi can observe sibling
   extension state or pi exposes a task/agent lifecycle event, map
   "background agents active" onto the working marker (or a new distinct
   "orchestrating" state so idle-vs-working-vs-backgrounding are visually
   three states, not two).
2. **Interim convention (now)**: agents narrate wait-state in the closing
   message — already practiced, confirmed insufficient alone.
3. Consider a distinct iconography: online (idle) / working (turn) /
   orchestrating (background) — the operator explicitly reads these as
   different situations.

## Code seams (grounded at scope time)

- `pi-extension/src/extension/relay_transport.ts` — where `agent_settled`
  drives the working projection onto room metadata; the bridge from
  background-agent liveness lands here (or feeds it).
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart` (`statusProjection`) +
  `_nlIndicator` in `app/lib/ui/chat/chat_page.dart` — the app-side
  status surface that would gain the third state.
- Pi-subagents package observability (what lifecycle events the extension
  can subscribe to) is the open investigation for feature-design.

Related: `story-offline-state-liveness-ux` (same surface, opposite
failure — dead-looking when alive vs alive-looking when idle). Deliberately
independent: neither assumes the other's output, but design should keep
the two status-surface changes coherent.

## Simplification opportunity

A real "orchestrating" state makes the narration convention (agents
prose-reporting wait-state) unnecessary — delete the convention from
operator expectations once the signal is trustworthy. If the three-state
model lands, check whether any ad-hoc working-state heuristics in the app
can collapse onto it. Iconography should reuse existing status-indicator
primitives (design-system tokens), not invent a parallel indicator.

## Verification

`corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
from `pi-extension/`; `flutter analyze && flutter test --exclude-tags e2e`
from `app/`. Cross-component behavior (extension → room metadata → app)
gets an e2e lane if the projection changes shape.
