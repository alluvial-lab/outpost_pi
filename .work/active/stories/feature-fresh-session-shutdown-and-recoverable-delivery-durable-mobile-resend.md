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
