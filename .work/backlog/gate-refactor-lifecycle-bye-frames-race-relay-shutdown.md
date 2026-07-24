---
id: gate-refactor-lifecycle-bye-frames-race-relay-shutdown
created: 2026-07-24
updated: 2026-07-24
tags: []
---

# Secure-channel bye frames race relay shutdown

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `unguarded-async-void`, confidence Medium → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/index.ts:943`

## Issue
_goIdle enqueues protected bye frames, immediately detaches all channels, and closes the relay without awaiting each secure channel's persistence/send drain.

## Fix
Make teardown awaitable, detach each owner with the bye reason, await returned whenIdle work, and only then stop the relay.
