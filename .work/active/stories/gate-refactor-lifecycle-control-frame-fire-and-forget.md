---
kind: story
release_binding: null
parent: feature-piext-lifecycle-delivery-promise-policy
stage: done
id: gate-refactor-lifecycle-control-frame-fire-and-forget
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# Control-frame dispatch drops async command failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/index.ts:1016`

## Issue
`_dispatchControlFrame` fires `_handleControl(frame.command)` with bare `void`; relay toggle/rename errors from the async control-command path can reject without an explicit catch or reply path.

## Fix
needs analysis

## Implementation

Attached a final rejection observer to the synchronous control-frame
(dispatch-and-swallow) boundary. Unexpected async command failures are now
consumed with a payload-free error log, while the input handler still returns
`{ action: "handled" }` immediately and no Cockpit response or transcript turn
is created. Added focused coverage using the existing relay mock seam.

Verification: `./node_modules/.bin/tsc --noEmit` and
`./node_modules/.bin/vitest run src/extension.test.ts -t 'control dispatch observes unexpected async command rejection|input hook swallows a CTRL_PREFIX|legacy CTRL_PREFIX input dispatches relay status|structured outpost_pi_control input is swallowed'`.
