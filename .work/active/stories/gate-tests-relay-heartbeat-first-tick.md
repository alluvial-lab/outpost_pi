---
id: gate-tests-relay-heartbeat-first-tick
kind: story
stage: done
tags: [testing, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-01
updated: 2026-07-28
---

# Relay heartbeat first-tick timing has only partial test coverage

## Severity
Medium

## Location
relay/src/handlers/peer.rs:125

## Issue
AC uncovered (bound item: epic-bold-reachability-contract-state-machine-step-4): Relay behavior remains the same: first ping after 25s, then every 25s. Only partial coverage.

## Recommendation
Add a paused-time Tokio test or extract a heartbeat-construction helper to assert no immediate ping and the first/repeated ticks occur at RELAY_WS_PING_INTERVAL.

## Implementation notes
- Extracted `relay_heartbeat` from the WebSocket routing loop without changing its interval policy.
- Added paused-time `heartbeat_first_tick_waits_one_full_interval_then_repeats`, which proves no immediate tick, no pre-25-second tick, the first 25-second tick, and the following interval tick.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` passed from `relay/` (160 unit tests plus all integration suites).
- Parked issues: none.
