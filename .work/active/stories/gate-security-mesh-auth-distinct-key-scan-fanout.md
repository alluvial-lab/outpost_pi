---
id: gate-security-mesh-auth-distinct-key-scan-fanout
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

# Distinct self-generated Pi keys bypass mesh-auth scan single-flight

## Severity
High

## Domain
Authentication & Authorization / API Security

## Location
`relay/src/handlers/pi_forward.rs:125`

## Evidence
```rust
if inner.in_flight.contains(pi_pk) {
    drop(self.scan_completed.wait(inner).unwrap());
    continue;
}
inner.in_flight.insert(pi_pk.to_string());
```

## Symptom
Concurrent forwards from distinct authenticated Pi identities can each start a
cold membership scan, multiplying SQLite reads and signature verification beyond
the existing per-key and per-connection controls.

## Root cause
`MeshAuthCache::members_of` single-flights only matching Pi keys: every distinct
cold key enters `in_flight` and calls `all_envelopes()` without a shared admission
ceiling, while the 1,024-entry cache and per-connection forwarding budget bound
retention and one connection rather than process-wide scan fanout.

## Fix approach
Keep the per-key `in_flight` single-flight and bounded positive/negative cache,
but use the process-shared cache's total in-flight key count to reject new cold
scans once the centralized concurrent-scan policy is full. Admission denial is
fail-closed as not authorized and is not cached, so a later request can retry
after admitted scans complete.

## Regression test
`relay/src/handlers/pi_forward.rs` starts simultaneous cold misses for four times
the global limit using distinct keys and asserts the maximum active scan count
never exceeds `MAX_CONCURRENT_MESH_AUTH_SCANS`.

## Remediation direction
Place a process-wide bound on concurrent/cumulative cold membership scans across
distinct source identities and move lookup work off Tokio request workers or to
an indexed membership representation. Keep the current per-key single-flight
and cache ceiling, but do not rely on them as global admission: relay auth lets
a client prove possession of arbitrarily many newly generated Pi keys, and the
per-connection forward budget still permits at least one full
`all_envelopes()` scan for each fresh identity.

## Implementation notes
- Execution capability: direct host-context implementation; this was a narrow,
  security-critical standalone fix with an explicit two-file production surface,
  so local diagnosis and bounded inline review were safer than delegation.
- Files changed: `relay/src/resource_limits.rs` centralizes a four-scan process
  ceiling; `relay/src/handlers/pi_forward.rs` enforces it while preserving
  per-key single-flight and the bounded positive/negative cache.
- Test added: `relay/src/handlers/pi_forward.rs` test
  `distinct_cold_keys_cannot_exceed_global_scan_limit` launches 16 simultaneous
  distinct cold misses and asserts active scans never exceed the centralized
  limit. Before the fix it failed with the ceiling assertion; after the fix it
  passed.
- Four-step confirmation: the focused regression passed; the full relay suite
  passed on a clean snapshot containing only this fix (150 unit tests plus all
  integration targets); the original fanout reproduction now observes at most
  four active scans; distinct over-budget identities fail closed without
  replacing the per-key single-flight or cache behavior.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and
  `cargo test` all passed from the clean relay snapshot. The primary checkout
  also contained unrelated concurrent gate-fix work, so isolation prevented
  that work from contaminating this story's evidence or commit.
- Adjacent issues parked: none. Moving SQLite work off Tokio request workers or
  adding a normalized membership index is broader architecture work; the
  required global admission bound resolves this verified vulnerability without
  bundling that redesign.
