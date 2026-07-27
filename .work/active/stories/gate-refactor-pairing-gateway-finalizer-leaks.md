---
id: gate-refactor-pairing-gateway-finalizer-leaks
kind: story
stage: implementing
tags: [refactor]
parent: null
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: refactor
created: 2026-07-27
updated: 2026-07-27
---

# Pairing gateway timeout/exit paths leak RPC process, seam dir, and timers

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`cockpit/lib/app/core/data/relay/pairing_gateway_impl.dart:72-86,173-185`

## Issue
The boot-timeout callback emits `PairFailed` but never cleans up the RPC
process, seam directory (TOKEN-BEARING), or periodic poll timer. Also, if
`onExit` invokes `_cleanup()` between `_rpc.start()` and timer installation,
`start()` installs timers after cleanup; the periodic timer then survives
indefinitely because the earlier cleanup could not cancel it.

## Fix
Funnel timeout, process exit, cancellation, and startup failure through one
serialized finalizer; check `_closed` after awaited startup/poll work before
installing timers; add an explicit interleaving test for exit-during-start
and a timeout-cleanup test.
