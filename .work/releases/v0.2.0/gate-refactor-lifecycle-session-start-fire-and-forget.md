---
kind: story
release_binding: v0.2.0
parent: feature-piext-lifecycle-delivery-promise-policy
stage: done
id: gate-refactor-lifecycle-session-start-fire-and-forget
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Session start auto-start future is discarded without error handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/extension/composition_root.ts:58`

## Issue
The `session_start` hook calls `void ports.commands.ensureStarted?.(ctx)`; if the async auto-start path rejects, the failure is not awaited or caught by the lifecycle hook.

## Fix
needs analysis

## Implementation

Narrowed `CommandSurfacePort.ensureStarted` to a synchronous trigger and
removed the discarded promise from lifecycle composition. Centralized the
three background `_cmdRoot` launches behind `_startRootInBackground`, which
logs and consumes startup rejection with an origin label; the slash-command
path remains awaited. Added coverage that the registered `session_start`
handler returns synchronously.

Verification: `./node_modules/.bin/tsc --noEmit` and
`./node_modules/.bin/vitest run src/extension/composition_root.test.ts`.
