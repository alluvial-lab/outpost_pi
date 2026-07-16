---
id: feature-piext-lifecycle-delivery-promise-policy
kind: feature
stage: drafting
tags: [pi-extension, refactor, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
---

# Pi-extension: failure policy for lifecycle and delivery promises

## Brief

Four gate findings in `pi-extension/src/session/` describe the same defect:
async work tied to session lifecycle and message delivery is launched with bare
`void`, so a rejected promise becomes an unobserved failure — the extension
keeps running as if the work succeeded, which breaks turn-state convergence and
can strand an inbound phone message (the symptom class the
`epic-remote-session-resilience-refactor` targets). This feature defines the
intended failure policy — observe, propagate to an owned boundary, or
deliberately tolerate with a logged reason — for each site:

- `gate-refactor-lifecycle-control-frame-fire-and-forget` — control-frame dispatch drops async command failures
- `gate-refactor-lifecycle-queued-delivery-promise` — observe rejected queued-message delivery promises (absorbed `gate-refactor-lifecycle-queued-delivery-fire-and-forget`)
- `gate-refactor-lifecycle-session-start-fire-and-forget` — session-start auto-start future discarded without error handling

## Simplification opportunity

Close the unobserved-promise class on the extension side so the
session-stable-delivery guarantee (shipped v0.1.0) isn't undermined by a
silently-rejected delivery or auto-start. Preserve turn-state convergence on
every exit path.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor` — extension session lifecycle is in
the epic's scope. 3 `gate-refactor-lifecycle-*` findings (the fourth was folded
into `gate-refactor-lifecycle-queued-delivery-promise` during the groom dup
pass) from the v0.6.0 release `gate-refactor` (lifecycle library).
