---
id: story-foreign-session-user-message-tolerance
kind: story
stage: drafting
tags: [pi-extension, app, bug]
parent: feature-session-stable-message-delivery
depends_on:
  - feature-session-stable-message-delivery-stale-wake-tolerance
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
review_origin: deep-review 2026-07-04
---

# Cross-process foreign-session `user_message` still surfaces a visible error

## Origin

Surfaced as a Blocker in the deep review of
`feature-session-stable-message-delivery-stale-wake-tolerance`. The tolerance
fix only covers the **same-session stale wake** case. The cross-process
**foreign-session** case (the original operator scenario: two pis on same
machine+cwd+identity, phone message fans out to both) is NOT covered.

## The gap

`user_message` is session-scoped (`session_scope.ts`). When the relay fans a
phone `user_message` out to a duplicate/idle pi whose `currentRemoteSessionId`
differs from the phone's `session_id`, `_routeClientMessageFrom`'s
`validateClientSession` gate rejects it BEFORE `_deliverUserMessage`/`wakeAgent`,
emitting `error{code:"session_mismatch"}` (`index.ts:2070-2079`,
`session_gate.ts:14-30`). The app renders generic errors as a ⚠ assistant-error
row (`app/lib/data/sync/sync_service.dart:729-746`).

So the duplicate/idle pi still produces a visible error on the phone — just
`session_mismatch` instead of `internal_error: …stale…`. The broad "idle/wrong
pi is benign" design intent is not achieved.

## Why this is hard (design needed, do NOT one-line-fix)

A pi **cannot distinguish** two cases from the `user_message` alone:

1. **Duplicate delivery to the wrong pi** (cross-process fanout, this bug) —
   should be silently tolerated.
2. **Phone held a stale `session_id` and is legitimately re-syncing** after a
   replacement — the `session_mismatch` error is the *intended* signal that
   tells the phone "your session_id is stale, re-sync via `session_sync`."
   Silently tolerating it would break the re-sync path.

So blindly dropping `session_mismatch` for `user_message` is wrong. The
disambiguation needs design — candidates to evaluate at design time:

- **Distinguish by sender/origin.** A `user_message` from a known owner peer
  that just paired (vs. a re-sync from an existing owner) might carry different
  signals. Investigate whether the relay or the envelope can distinguish
  "duplicate delivery" from "stale client session_id."
- **Tolerate only when this pi is idle AND not the intended target.** If this
  pi has no active turn and another pi on the same (owner_pk, room) is
  working, treat the foreign-session `user_message` as benign. Requires
  knowing about the sibling pi — non-trivial cross-process state.
- **Suppress the app-side rendering of `session_mismatch` for `user_message`.**
  App-side change: don't render `session_mismatch` on a `user_message`
  in-reply-to as a ⚠ row; treat it as a benign drop + trigger a `session_sync`.
  Smallest fix, but moves the tolerance to the app and may mask the legitimate
  re-sync signal for *all* session mismatches, not just duplicates.
- **Prevention (out of scope here, tracked in the parent feature):** refuse a
  second pi on the same identity+room. Conflicts with multi-device-owner
  design.

## Acceptance criteria (to be refined at design)

- [ ] A duplicate-delivered foreign-session `user_message` to an idle pi does
  NOT surface a visible error on the phone.
- [ ] A legitimate stale-`session_id` re-sync still produces the signal that
  triggers `session_sync` (the re-sync path is NOT broken).
- [ ] Regression test for both cases.

## References

- Parent feature: `feature-session-stable-message-delivery.md`.
- Sibling (same-session tolerance, done): `feature-session-stable-message-delivery-stale-wake-tolerance.md`.
- `pi-extension/src/index.ts:2070-2079` — the session gate that emits `session_mismatch`.
- `pi-extension/src/session/session_gate.ts:14-30` — `validateClientSession`.
- `app/lib/data/sync/sync_service.dart:729-746` — app renders `ErrorMessage` as ⚠ row.
- Relay fanout: `relay/src/peers/connections.rs:94-114`, `relay/src/peers/registry.rs:33`.
