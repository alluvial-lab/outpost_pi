---
id: feature-fresh-session-shutdown-and-recoverable-delivery-boundary-e2e-proof
kind: story
stage: implementing
tags: [pi-extension, app, lifecycle]
parent: feature-fresh-session-shutdown-and-recoverable-delivery
depends_on: [feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain, feature-fresh-session-shutdown-and-recoverable-delivery-durable-mobile-resend]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Prove quiesce-to-reconnect recovery across the owner channel

## Checkpoint

Extend the production-backed pairing harness with a narrow test-only delivery
fence/counter seam and add one cross-component scenario: pair normally, enter
quiescing, submit a mobile prompt, prove the Pi SDK delivery count does not
change, observe `delivery_retry` through `SyncService`, restart the Pi host while
preserving owner-channel/session state, wait for authoritative room recovery,
and prove the same client id is delivered and confirmed exactly once on the
successor process.

The harness seam may control the fence but must not replace the production
codec, secure channel, relay routing, SyncService, outbox, room snapshots, or
SDK delivery adapter.

## Files

- `pi-extension/test/support/e2e_pi_host_runtime.ts`
- `pi-extension/test/support/e2e_pi_host_server.ts`
- `app/test/e2e/support/pi_host_client.dart`
- `app/test/e2e/fresh_session_recoverable_delivery_e2e_test.dart` (new)
- `e2e/run-pairing.sh` only if scenario registration requires it

## Acceptance evidence

- [ ] The prompt is persisted by the app but is not handed to the SDK while the
      fence is active.
- [ ] The real generated codec and sealed owner channel carry
      `delivery_retry`; no direct test callback injects it into SyncService.
- [ ] After preserved host restart and a fresh live-room snapshot, the original
      client id is resent, accepted, confirmed, and removed from the outbox.
- [ ] The final transcript contains one user row for that id and the host SDK
      delivery counter records one post-recovery delivery.
- [ ] A timeout/failure report states which phase failed without logging prompt
      contents or owner-channel secrets.
- [ ] `e2e/run-pairing.sh` passes in addition to both owning subproject suites.

## Ordering

Runs after both the extension shutdown/fence and app durable-resend checkpoints.
