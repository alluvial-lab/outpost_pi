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

- [x] The prompt is persisted by the app but is not handed to the SDK while the
      fence is active.
- [x] The real generated codec and sealed owner channel carry
      `delivery_retry`; no direct test callback injects it into SyncService.
- [x] After preserved host restart and a fresh live-room snapshot, the original
      client id is resent, accepted, confirmed, and removed from the outbox.
- [x] The final transcript contains one user row for that id and the host SDK
      delivery counter records one post-recovery delivery.
- [x] A timeout/failure report states which phase failed without logging prompt
      contents or owner-channel secrets.
- [ ] `e2e/run-pairing.sh` passes in addition to both owning subproject suites.

## Ordering

Runs after both the extension shutdown/fence and app durable-resend checkpoints.

## Implementation notes

- Execution/order: inline host worker (`openai-codex/gpt-5.6-sol`, xhigh),
  final dependency layer after both implementation siblings. The app sibling's
  full-suite blocker was already durably recorded; its focused behavior was
  green, so this production-backed proof continued as the caller-directed
  parallel work available while the unrelated pairing suite remained blocked.
- Added a narrow host control/status seam that toggles the production
  owner-delivery fence, drains actual protected owner-channel tails, and counts
  calls at the real SDK adapter. It never injects a server frame into
  `SyncService`.
- Added a preserving **fresh-session** host restart: machine identity, paired
  owner-channel keys, and cwd/name state survive while a new SDK SessionManager
  and canonical session id start. The app reconnects through the real relay and
  sealed channel.
- Added `fresh_session_recoverable_delivery_e2e_test.dart`: normal signed-DH
  pair, protected ping readiness, production quiesce, SyncService send, durable
  outbox observation, zero SDK delivery, preserved fresh restart, authoritative
  room/session hydration, stable-id resend, one SDK delivery, target-matching
  confirmation, outbox removal, and one confirmed successor transcript row.
- Added deterministic host-side owner-channel drain observation to eliminate a
  timing guess without fabricating delivery. Also marked a successful direct
  first attempt in the app's per-generation recovery set, preventing room-meta
  churn from re-sending a sent-but-unconfirmed id within the same generation;
  reconnect/rotation still advances the generation and retries.
- Verification actually run: E2E host TypeScript compile passed; focused Dart
  analysis passed; extension typecheck/full test/build passed (60 files, 1,102
  passed / 3 skipped); focused app adapter and SyncService suites passed. Six
  production-backed `e2e/run-pairing.sh` runs built the current relay and host.
  The new recovery scenario passed end-to-end in four runs. One failure exposed
  and fixed a missing deterministic protected-tail drain/readiness barrier; the
  other reached successor resend/echo and exposed the host status readiness
  condition (`paired` is ready after rapid app reattach), which was also fixed.

## Blocker

- The final `e2e/run-pairing.sh` run passed the new recovery scenario plus 15
  other E2E scenarios, but the pre-existing
  `session_replacement_e2e_test.dart` repeatedly timed out waiting for its
  pre-settlement `cli_` confirmation after the real SDK delivery had entered
  the host's deferred turn. Deterministic channel readiness, SyncService writer
  binding, and protected-tail drain checks did not restore the missing live
  confirmation. This behavior failure appeared after the outbox/lifecycle
  changes and is not waived as a flake. Keep this child at `implementing` until
  that regression is root-caused and the exact full harness exits green.
