---
kind: story
release_binding: v0.2.0
parent: feature-relay-resource-bounds
stage: done
id: gate-security-auth-challenge-no-timeout
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-20
---

# Auth challenge step can be held open indefinitely

## Severity
Medium

## Location
relay/src/handlers/peer.rs:83

## Issue
After a valid hello, the relay waits on stream.next().await for auth without a timeout, so unauthenticated clients can hold pre-auth sockets/tasks open indefinitely.

## Recommendation
Add an auth-response timeout like HELLO_TIMEOUT_MS and close the socket if auth is not received promptly.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical relay work).
- Review weight: `standard` (caller default; feature-level review only).
- Files changed: `relay/src/handlers/peer.rs`.
- Tests added: paused-time stalled-step timeout and non-text handshake rejection at the shared helper boundary.
- Simplification: hello and auth now use one cancellation-safe timeout helper and one five-second policy constant.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: focused handshake helper and existing invalid-signature integration tests passed.
