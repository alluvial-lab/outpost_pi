---
id: gate-security-rooms-dedup-cache-unbounded
kind: story
stage: implementing
tags: [security, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-19
---

# Rooms-check dedup state retains attacker-selected peer IDs for the connection lifetime

## Severity
High

## Domain
API Security / Input Validation & Injection

## Location
`relay/src/handlers/connection_actor.rs:261`

## Evidence
```rust
self.last_rooms_resp.insert(target_peer, resp.clone());
self.metrics.inc_rooms_emitted(1);
messages.push(resp);
```

## Remediation direction
Bound or eliminate the per-connection `last_rooms_resp` map and validate every
control-frame peer identifier to the canonical fixed-size identity shape before
using it as a retained key. An LRU/TTL ceiling must account for key and response
bytes, not only entry count. Preserve response dedup for legitimate peers
without retaining every unique `rooms_check` target ever supplied; the existing
per-window request-cost limit does not bound lifetime retention or fresh
connection budgets.
