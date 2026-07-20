---
id: gate-security-rooms-dedup-cache-unbounded
kind: story
stage: review
tags: [security, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-20
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

## Implementation notes

- **Execution capability:** direct inline repair; the defect is isolated to the
  relay control-frame boundary and one connection-owned cache, so delegation
  would add handoff cost without improving evidence.
- **Root cause:** `ConnectionActor::last_rooms_resp` was an unbounded `HashMap`
  keyed by unvalidated control-frame strings, so each distinct attacker-selected
  `rooms_check` target remained for the authenticated connection lifetime.
- **Fix:** replace the map with a per-connection LRU cache capped at 64 entries
  and 256 KiB of combined peer-key and serialized-response bytes; oversized
  responses remain deliverable but are not cached. Both ceilings live in
  `relay/src/resource_limits.rs`. All presence/rooms control-frame peer lists now
  reject identifiers that are not canonical standard-base64 encodings of valid
  32-byte Ed25519 public keys before subscription, lookup, or dedup retention.
- **Files changed:** `relay/src/handlers/connection_actor.rs`,
  `relay/src/handlers/control.rs`, `relay/src/peers/identity.rs`,
  `relay/src/peers/mod.rs`, and `relay/src/resource_limits.rs`.
- **Regression tests:** `relay/src/handlers/connection_actor.rs` adds
  `rooms_dedup_cache_does_not_retain_unbounded_unique_peers` (the pre-fix run
  failed after observing 65 retained attacker-selected peers) and
  `rooms_dedup_cache_bounds_key_and_response_bytes`; `relay/src/handlers/control.rs`
  adds canonical-identity rejection and verifies an invalid `rooms_check` emits
  no snapshot or dedup metric activity. Existing legitimate-peer dedup coverage
  remains green with canonical peer ids.
- **Verification completed before parallel relay builds caused contention:** the
  new retention regression failed against the old unbounded map, then passed
  after the fix; the canonical-id rejection, invalid-frame drop, byte-ceiling,
  and legitimate rooms dedup tests passed; `cargo fmt --check` and
  `cargo clippy -- -D warnings` each passed on the repaired code. A full
  `cargo test` was started but could not complete reliably because other agents
  were concurrently editing/building the same relay tree; per operator stop,
  no further Cargo commands or commit were attempted. The story remains at
  `stage: implementing` pending serialized full-suite verification.
- **Adjacent issues parked:** none; unrelated concurrent relay security fixes
  were left untouched.
