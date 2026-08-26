---
id: feature-fresh-session-shutdown-and-recoverable-delivery-boundary-e2e-proof
kind: story
stage: done
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
- [x] `e2e/run-pairing.sh` passes in addition to both owning subproject suites.

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

## Failure adjudication (2026-08-26)

- **Verdict — production regression, not stale test.** A clean full-harness
  reproduction reached the replacement host's explicit deferred-turn
  `pending` barrier, then produced no protected `cli_` confirmation for the
  test's 15-second observation window. The current source explained the runtime
  evidence: the timestamp-ownership path consumed the pre-wake identity
  reservation at SDK `message_end` but returned without persisting or
  publishing it, then waited for the replacement context's full-turn
  `sendUserMessage` Promise before `_confirmUserDelivery`. This contradicted the
  existing replacement contract that SDK `message_end` confirms the admitted
  prompt before the turn settles.
- The managed-shutdown drain did not justify that reorder. It still retains the
  admitted attempt in `_inflightUserDeliveries` until the full-turn Future
  settles, so a later fresh-session fence waits for it before reset/disposal.
  The earlier user `message_end` is independently the SDK acceptance signal and
  can durably confirm the app id while the attempt remains in flight; the
  10-second shutdown deadline and durable-outbox fallback remain unchanged.
- **Fix:** reserve the delivery producer timestamp and steering provenance with
  the original client id before SDK wake. When matching user `message_end`
  arrives, persist the canonical `user_confirmed` fact before publishing
  `user_input`; after full-turn settlement, the ordinary delivery confirmation
  reuses the same timestamp and identity. Focused extension tests now pin the
  pre-settlement durable confirmation and post-settlement timestamp equality.
- **Evidence:** the targeted production-backed replacement scenario passed
  1/1. The full `e2e/run-pairing.sh` then passed all 17 currently registered
  scenarios (the earlier 16-scenario expectation was stale) and the redaction
  check passed. The extension passed typecheck, 60 test files (1,103 passed / 3
  skipped), and build. The recoverable-delivery scenario remained green in the
  same full run, satisfying this checkpoint and the durable-mobile-resend
  integration follow-up.
