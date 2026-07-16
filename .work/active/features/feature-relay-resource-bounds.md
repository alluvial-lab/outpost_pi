---
id: feature-relay-resource-bounds
kind: feature
stage: drafting
tags: [relay, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-16
---

# Relay: bound unauthenticated/authenticated resource consumption and retained state

## Brief

Four security gate findings describe unbounded resource consumption on the
relay — an unauthenticated client can hold sockets/tasks open indefinitely,
authenticated senders can grow memory without limit, and the auth path scans
persisted mesh storage on every miss. Together these are DoS / resource-exhaustion
vectors. This feature bounds each:

- `gate-security-auth-challenge-no-timeout` — unauthenticated clients can hold pre-auth sockets/tasks open indefinitely
- `gate-security-pi-envelope-auth-scan-rate-limit` — every `pi_envelope` auth miss falls through to `store.all_envelopes()` and scans persisted mesh blobs
- `gate-security-subscription-empty-target-retention` — repeated subscribe/replace calls with new target names grow memory indefinitely
- `gate-security-unbounded-outbound-queues` — authenticated senders enqueue forwarded messages faster than a slow recipient drains

## Simplification opportunity

Add pre-auth timeouts/ceilings, a negative cache + per-frame limiter on the
envelope-auth path, retention bounds on subscription target maps, and a bounded
outbound queue with backpressure/drop policy. Behavior change: resource
exhaustion now fails closed (drop/disconnect) instead of growing unbounded.

## Source

Promoted from backlog by `scope` (2026-07-15). 4 `gate-security-*` findings
(auth-challenge, pi-envelope-auth-scan, subscription-retention,
unbounded-outbound-queues) from the v0.6.0 release `gate-security` pass.
