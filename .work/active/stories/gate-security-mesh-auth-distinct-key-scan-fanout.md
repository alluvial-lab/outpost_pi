---
id: gate-security-mesh-auth-distinct-key-scan-fanout
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

## Remediation direction
Place a process-wide bound on concurrent/cumulative cold membership scans across
distinct source identities and move lookup work off Tokio request workers or to
an indexed membership representation. Keep the current per-key single-flight
and cache ceiling, but do not rely on them as global admission: relay auth lets
a client prove possession of arbitrarily many newly generated Pi keys, and the
per-connection forward budget still permits at least one full
`all_envelopes()` scan for each fresh identity.
