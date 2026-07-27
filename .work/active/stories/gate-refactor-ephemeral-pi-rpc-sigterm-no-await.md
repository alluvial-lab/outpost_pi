---
id: gate-refactor-ephemeral-pi-rpc-sigterm-no-await
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

# Ephemeral pi RPC dispose sends SIGTERM without awaiting or escalating

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`cockpit/lib/app/core/data/relay/ephemeral_pi_rpc.dart:108-127`

## Issue
After the graceful two-second wait times out, `dispose()` sends SIGTERM but
does not await exit, escalate to SIGKILL, or confirm termination before
deleting the working directory. The owned `pi --mode rpc` child can survive
disposal.

## Fix
Await termination after SIGTERM, escalate to SIGKILL on a second timeout,
await the final exit, then cancel streams and remove the temporary
directory.
