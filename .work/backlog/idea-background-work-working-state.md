---
id: idea-background-work-working-state
created: 2026-08-27
updated: 2026-08-27
tags: [app, pi-extension, ux]
---

# Background work should hold the working state — not a bare "online" bubble

Field report (operator, 2026-08-27): while the agent waits on background
tools/subagents (e.g. an e2e battery worker), the app shows only the
single "online" bubble. The sole cue that we're waiting is the agent's own
prose ("I'll report when it lands") — fragile, purely conventional, and
invisible if the narration is missed.

## Root shape

The `working` projection derives from the SDK turn lifecycle: turn ends →
agent_settled → working=false. Background agents (pi-subagents tasks) run
harness-side beyond any turn — the room/app has no signal that orchestrator
work continues.

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

Related: idea-offline-state-liveness-ux (same surface, opposite failure —
dead-looking when alive vs alive-looking when idle).
