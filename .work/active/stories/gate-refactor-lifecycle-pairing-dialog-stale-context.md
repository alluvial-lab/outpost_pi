---
id: gate-refactor-lifecycle-pairing-dialog-stale-context
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-24
---

# Reacquire the Pi UI before opening the pairing dialog

## Library
lifecycle

## Rule
stale-session-context

## Confidence
High

## Location
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:272`

## Issue
`showPairQr` invokes `ctx.ui.custom` after relay/mesh and optional filesystem awaits without proving the captured Pi context is still current; `_safeCommandContext` only redirects `notify`, so `/new`, `/resume`, `/fork`, or `/reload` during setup can make the final dialog call touch a stale session UI.

## Fix
Reacquire the current session UI at the post-await dialog boundary, or carry a runtime epoch/current-context guard that suppresses the dialog when the initiating session has been replaced.
