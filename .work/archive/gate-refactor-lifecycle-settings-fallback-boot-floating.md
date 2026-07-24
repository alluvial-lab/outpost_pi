---
id: gate-refactor-lifecycle-settings-fallback-boot-floating
status: superseded
superseded_by: backlog-app-lifecycle-owned-operations (groom merge bd3b3a7, 2026-07-22)
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-24
---

# Own fallback connection boot after peer revocation

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/ui/settings/viewmodels/settings_viewmodel.dart:126`

## Issue
After revoking the active peer, `revoke` discards the fallback peer's `ConnectionManager.boot()` future behind a lint suppression, so boot failures are unobserved and `revoke` can finish and reload settings before fallback cache restore/connect setup settles.

## Fix
Needs analysis: await fallback boot when revocation completion should include fallback setup, or delegate it to an explicit connection-owned detached operation that catches and projects failure before `revoke` reloads user-visible state.
