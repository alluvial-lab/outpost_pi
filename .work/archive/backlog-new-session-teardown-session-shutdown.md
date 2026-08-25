---
status: folded
folded_into: feature-fresh-session-shutdown-and-recoverable-delivery
id: backlog-new-session-teardown-session-shutdown
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, lifecycle]
---

# /new (fresh session) bypasses session_shutdown teardown

## Origin
gate-refactor R2 (v0.4.0); deferred from v0.4.0 per operator (heavier redesign).

## Location
pi-extension/src/index.ts:3005-3007.

## Issue
The restart-managed session_new path sends an ACK, resets projection state, then calls process.exit(EXIT_FRESH_SESSION) after a fixed 100 ms. Direct exit bypasses session_shutdown and therefore the teardown in composition_root.ts:137-151 (owner-channel drain, relay stop, stale-context clearing, mesh closure). The 100 ms delay does not prove the ACK or reset-history frame has drained.

## Work
Introduce a fresh-session shutdown handshake that first awaits the normal lifecycle/resource drains, then terminates with the fresh-session result. Do not use a fixed delay as the delivery boundary.
