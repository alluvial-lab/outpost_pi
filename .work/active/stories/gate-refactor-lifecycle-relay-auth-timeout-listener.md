---
id: gate-refactor-lifecycle-relay-auth-timeout-listener
kind: story
stage: done
tags: [pi-extension]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-28
---

# Relay auth timeout leaves its challenge listener attached

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`pi-extension/src/transport/relay_client.ts:253`

## Issue
`_nextMsg` clears the auth timeout on the success path, but the timeout path rejects without removing the `ws.once("message")` listener registered at line 257, leaving a stale listener on the WebSocket until a later message or socket teardown.

## Fix
Use named cleanup shared by the timeout and message paths: clear the timer, remove the pending message listener (and any close/error listener added for the wait), then resolve or reject exactly once.

## Design checkpoint
In `pi-extension/src/transport/relay_client.ts`, keep `_nextMsg(ws): Promise<string>` private. Introduce named `cleanup`, `onMessage`, and `onTimeout` closures plus a settlement guard. Both paths call the same cleanup before resolve/reject; any future close/error callbacks must be named and join that cleanup.

## Acceptance evidence
- A fake-timer timeout rejects once and leaves no pending `message` listener.
- A successful challenge clears the timeout and removes the auth listener before post-auth frames are forwarded.
- A timeout/message race cannot consume a later data-plane frame or settle twice.

Tests belong in `pi-extension/src/transport/relay_client.test.ts`; preserve the payload-free `relay auth timeout` error.

## Implementation notes

- `_nextMsg` now uses named `cleanup`, `onMessage`, and `onTimeout` callbacks with a shared settlement guard; both settlement paths clear the timer and remove the exact challenge listener.
- Added fake-timer regressions proving timeout leaves no message listener and successful auth replaces the challenge listener with exactly one data-plane listener that remains healthy after the old timeout deadline.
- Changed `pi-extension/src/transport/relay_client.ts` and `pi-extension/src/transport/relay_client.test.ts`.
- Verification: `tsc --noEmit`; targeted relay-client suite (14 passed); full Vitest suite (944 passed, 3 skipped; 55 files).
