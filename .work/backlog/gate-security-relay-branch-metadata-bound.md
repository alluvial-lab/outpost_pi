---
id: gate-security-relay-branch-metadata-bound
created: 2026-09-07
updated: 2026-09-07
tags: [security, relay, pi-extension]
release_binding: null
gate_origin: security
---

# Enforce the branch metadata size limit at relay admission

## Severity
Medium

## Domain
Input Validation & Injection / API Security

## Relevance
Release-relevant finding from the v0.12.0 security gate; nonblocking and unbound per `gate_finding_routing`.

## Location
`relay/src/protocol/generated/room.rs:126`

## Evidence
```rust
patch.branch = Some(map.next_value::<Option<String>>()?);
```

The schema caps `branch` at 256 characters in hello, snapshots, and patches
(`protocol/schema/relay-control.schema.json:47,71,95`), but the generated Rust
visitor admits an arbitrary string. `decode_relay_frame` applies only the
whole-message ceiling before Serde dispatch (`relay/src/protocol/frame.rs:72-115`),
and the control handler passes the patch directly into retained room state
(`relay/src/handlers/control.rs:188-217`). Hello admission similarly omits a
branch field-size check (`relay/src/auth/challenge.rs:82-101`).

An authenticated relay client can therefore retain a multi-megabyte branch via
`room_meta_update`, rather than the intended small field. The post-merge
publisher copies that value into every subsequent metadata update and fans it
out to subscribers (`relay/src/peers/registry_event_publisher.rs:158-195`).
This creates avoidable retained-memory and fan-out amplification within the
existing raw-frame limit; authentication requires a client-owned key, not
proof of an operator pairing.

There is also a concrete cross-endpoint mismatch: the extension's generated
subscriber validator rejects a 257-character branch, so later full-meta
updates carrying the retained invalid branch are rejected as a whole. A
read-only Node probe of `isRelayServerControlFrame` confirmed a 256-character
branch is accepted and a 257-character branch is rejected. Rust admission and
retention were verified by source inspection, not a live relay attack.

Existing string-patch fields have adjacent baseline validation gaps; this item
tracks the newly introduced branch surface, not a claim that v0.12.0 introduced
all metadata resource risk. It is separate from the already-tracked room
subscription authorization finding.

## Remediation direction
Generate or apply schema-derived branch bounds at both hello and authenticated
patch admission, before committing room state. Preserve omission/null-clear
semantics. Add matching Rust and endpoint cases at the limit and one beyond,
including a rejected patch leaving prior room state intact. Keep the sampler's
branch output within the same contract so an unusually long local Git branch
cannot emit invalid metadata. Do not hand-edit generated Rust alone.
