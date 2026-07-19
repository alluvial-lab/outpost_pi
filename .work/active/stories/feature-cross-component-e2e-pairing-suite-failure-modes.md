---
id: feature-cross-component-e2e-pairing-suite-failure-modes
kind: story
stage: done
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: [feature-cross-component-e2e-pairing-suite-infra, feature-cross-component-e2e-pairing-suite-cross-room-pairing]
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-19
---

# Add pairing failure-mode contracts

## Checkpoint

Implement Unit 5 in `app/test/e2e/pairing_failures_e2e_test.dart`: invalid
auth, consumed token, expired token, and service-level relay unavailability.
Run serially against fresh Pi-host generations and restore Toxiproxy in teardown.

**Invariants**:
- Invalid relay auth closes before pairing and leaves the QR token usable.
- Consumed/expired tokens return typed `pair_error` without corrupting peers.
- Losing the app relay path after QR fails within deadline and saves no peer.

## Acceptance evidence

- [x] Invalid-auth probe speaks only hello/challenge/auth; a subsequent valid production pair with the same QR proves no token consumption.
- [x] A second real owner using a consumed QR receives `PairingError.code == token_consumed` and does not replace the first record.
- [x] Production `pair --ttl 10` expires without a clock hook and yields `token_expired` with no saved peer.
- [x] Pinned Toxiproxy disables only the app path after QR; pairing fails boundedly, storage stays empty, and teardown restores connectivity.
- [x] Failure logs omit nonce, signature, token, keys, URI, and transcript content.

## Test integrity

If a failure contract exposes a product bug, park it and keep the honest
failing test as a linked skip with a one-line reason; do not soften the expected
error or persistence invariant. Fix stale fixtures and mock-service drift
in-session. Never merely assert that "some exception" occurred, mock the
WebSocket, delete a flaky case, or game an assertion to make the suite green.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected).
- Review weight: `standard` (caller).
- Files changed: `app/test/e2e/pairing_failures_e2e_test.dart`.
- Tests added: raw invalid domain-signature rejection followed by valid production pairing; two real Owner identities against a consumed token; production minimum-TTL expiry; and Toxiproxy interruption of an authenticated app path before `pair_request` completes.
- Simplification: failure tests reuse the golden `PairingStack` and assert typed error codes/classes plus production storage state; no WebSocket mock or clock hook exists.
- Discrepancies from design: the proxy case establishes the real authenticated app transport before disabling it, then interrupts `performPairing`; disabling the listener before `WsTransport.connect` also surfaced an unrelated unhandled `WebSocketChannel.ready` error and did not represent the designed mid-pair interruption.
- Adjacent issues parked: none (the pre-connect error was avoided by matching the specified after-QR interrupted-operation boundary; no production source was changed).
- Verification: `e2e/run-pairing.sh` passed all seven golden/regression/failure cases.
