---
kind: story
release_binding: null
parent: feature-relay-resource-bounds
stage: done
id: gate-security-unbounded-outbound-queues
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Data-plane outbound queues are unbounded

## Severity
Medium

## Location
relay/src/peers/connections.rs:15

## Issue
Live connections store mpsc::UnboundedSender<Message>, so authenticated senders can enqueue large forwarded messages faster than a slow recipient drains them and grow relay memory.

## Recommendation
Use bounded per-connection queues with explicit drop/close semantics, and add per-peer/IP data-plane rate limits.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical relay work).
- Review weight: `standard` (caller-selected; feature-level review only).
- Files changed: `relay/src/handlers/{connection_actor,control,peer,pi_forward}.rs`, `relay/src/{lib,metrics}.rs`, `relay/src/peers/{connections,registry,registry_event_publisher}.rs`.
- Tests added: deterministic capacity-one drop-newest behavior, saturation metrics, and multi-device delivery with one saturated and one healthy mailbox; existing lifecycle/routing tests now receive bounded test mailboxes.
- Simplification: `DeliveryReport` replaces ambiguous booleans at the shared registry seam; all production delivery uses non-blocking bounded `Sender::try_send` with no await under the registry lock.
- Discrepancies from design: per-connection `pi_envelope` admission (rather than a retained per-IP table) is implemented by the sibling story per the feature's explicit NAT-safe design decision; the durable Rust reference is outside this worker's allowed write scope.
- Adjacent issues parked: none.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` passed (141 unit tests plus all integration targets).
