---
kind: story
release_binding: null
parent: feature-piext-lifecycle-delivery-promise-policy
stage: drafting
id: gate-refactor-lifecycle-control-frame-fire-and-forget
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
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
