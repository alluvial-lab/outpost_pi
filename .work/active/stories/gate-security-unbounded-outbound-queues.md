---
kind: story
release_binding: null
parent: feature-relay-resource-bounds
stage: drafting
id: gate-security-unbounded-outbound-queues
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
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
