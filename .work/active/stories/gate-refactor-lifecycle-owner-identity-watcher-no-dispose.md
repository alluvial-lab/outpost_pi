---
id: gate-refactor-lifecycle-owner-identity-watcher-no-dispose
kind: story
stage: drafting
tags: [app, refactor]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Owner identity watcher is registered without lifecycle disposal

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `resource-no-dispose`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`app/lib/config/dependencies.dart:96`

## Issue
OwnerIdentityBridge owns a platform stream subscription and implements dispose(), but addInstance provides no disposal hook, so disposeDependencies() does not cancel its watcher.

## Fix
Register the bridge through an injector binding with an onDispose callback, or explicitly call OwnerIdentityBridge.dispose() from disposeDependencies().
