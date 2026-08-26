---
id: feature-fresh-session-shutdown-and-recoverable-delivery-durable-mobile-resend
kind: story
stage: implementing
tags: [app, lifecycle]
parent: feature-fresh-session-shutdown-and-recoverable-delivery
depends_on: [feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Persist and replay unconfirmed owner submissions on recovery

## Checkpoint

Add an encrypted, room-scoped mobile outbox for every unconfirmed
`user_message`. Persist the stable id and payload before channel send. On
`delivery_retry`, disconnect/reconnect, or canonical session rotation, retain
or retarget the entry and resend it only after a fresh live room snapshot,
using the original id and the current canonical `session_id`. Remove the entry
only after a matching-session live echo or history confirmation proves
acceptance.

The outbox becomes the single resend authority. Retire the existing transcript
scan plus `_resentHeldPendingIds` selection path; `UserMessageSubmitted.held`
may remain as transcript/UI provenance but must not be a competing delivery
queue. Identity-pending display state may remain in memory, while the outbox is
its durable recovery authority.

## Files

- `app/lib/domain/entities/pending_owner_delivery.dart`
- `app/lib/domain/contracts/owner_delivery_outbox.dart` and
  `app/lib/domain/contracts/contracts.dart`
- `app/lib/data/local/records/pending_owner_delivery_record.dart`
- `app/lib/data/local/hive_owner_delivery_outbox.dart`
- `app/lib/data/local/boxes.dart`
- `app/lib/config/dependencies.dart`
- `app/lib/data/sync/sync_service.dart`
- focused adapter and SyncService tests under `app/test/data/local/` and
  `app/test/data/sync/sync_service_test.dart`

## Acceptance evidence

- [ ] An entry is encrypted and durable before its first channel write; a cold
      SyncService/box reopen retains it.
- [ ] No recovery send occurs while the room is stale/offline or before a
      canonical session id exists.
- [ ] Same-session reconnect and fresh-session rotation each resend once with
      the original id; session rotation retargets durably before send.
- [ ] A late confirmation from the old session cannot delete an entry already
      retargeted to the successor session.
- [ ] Matching live echo or `session_history` confirmation deletes the outbox
      entry only after transcript confirmation is durable.
- [ ] `delivery_retry` keeps the bubble recoverable instead of appending a
      terminal failure; permanent protocol rejection still fails visibly and
      removes the entry.
- [ ] Send failure, app restart, and a second reconnect leave an unconfirmed
      entry retryable without an in-memory suppression leak.
- [ ] Owner-transition/transcript-discard recovery wipes the encrypted outbox
      with the other owner-bound transcript data.
- [ ] Flutter analyze and the full non-e2e test suite pass.

## Ordering

Depends on the retry signal contract. It can be implemented alongside the
extension drain checkpoint under one parent-feature owner.

## Implementation notes

- Execution/order: inline host worker (`openai-codex/gpt-5.6-sol`, xhigh),
  third checkpoint after the retry contract and managed drain. Drain and resend
  were graph-parallel; this serial order was chosen only because one inline
  worker owns the cross-component feature.
- Added a domain outbox port and strict Hive adapter over one common encrypted
  box. Entries are keyed by a collision-resistant peer/room/client-id tuple,
  reject malformed records instead of disappearing, and are cleared by both
  the durable Owner-transition latch and explicit unreadable-transcript discard.
- `SyncService` now appends the optimistic transcript fact, persists recovery
  intent, and only then sends. Outbox failure produces a visible `outbox_error`
  row and no channel write. Identity-pending submissions persist with a null
  target once peer identity is known.
- Recovery requires a live room plus canonical session, durably retargets before
  send, reuses the original id, and sends once per lifecycle generation. The
  transcript `held` flag remains provenance only; the prior transcript scan and
  `_resentHeldPendingIds` authority were removed.
- Live and history confirmations remove only a matching target after transcript
  durability. `delivery_retry` disarms the short timer without failing or
  deleting the entry; permanent receiver failures delete only after their
  visible failure fact is durable. A late old-session frame is gated and cannot
  clear a successor-targeted entry.
- Focused verification: encrypted adapter/reopen, malformed-state, Owner wipe,
  and discard tests passed (7); SyncService tests passed (114), including
  persist-before-wire, fail-closed storage, cold reconstruction, sent and held
  recovery, rotation retarget, stale confirmation, live/history confirmation,
  failed retry, and generation fencing; Flutter analyze passed with no issues.
- Full-suite triage: multiple complete non-e2e runs reached 968 tests with the
  outbox-owned files green. The first exposed and fixed durable-outbox test
  isolation in existing shared-Hive suites; two later runs exposed and fixed
  full-load-only assertion races in history removal and resend diagnostics.
  The current combined tree also contains concurrent uncommitted Owner-restore
  grace-period work whose pairing widget tests are being repaired by its owner;
  final authoritative non-e2e verification and this story's stage transition
  remain pending that disjoint concurrent work settling.

## Blocker

- The required combined `flutter test --exclude-tags e2e --concurrency=2`
  cannot currently complete green because the independently tracked
  `story-identity-boot-restore-race` is still `stage: implementing` with its own
  full-suite blocker. Its new Owner restore-grace path leaves two PairingPage
  widget tests hanging until their 10-minute per-test timeout; multiple real
  full runs reached 968+ otherwise-passing tests before those same two failures.
  This behavior assertion is not waived. All outbox-owned focused suites and
  Flutter analysis are green, and implementation is committed so the boundary
  E2E proof can continue; keep this child at `implementing` until the identity
  story settles and the exact required full app command passes.
