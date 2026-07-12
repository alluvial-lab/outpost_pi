---
id: feature-targeting-delivery-contract
kind: feature
stage: done
tags: [pi-extension, app, relay, docs]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---
status: superseded
superseded_by: feature-contract-gap-audit
superseded_date: 2026-07-04
---

> **SUPERSEDED 2026-07-04.** Restructured into `feature-contract-gap-audit`
> (targeting audit + typed-error spike) under the reframed
> `epic-targeting-and-session-lifecycle-contracts`. See
> `.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`.

# Targeting & delivery contract (App↔Pi data-plane)

## Brief

Pin, in `PROTOCOL.md`, the App↔Pi data-plane targeting model that is currently
load-bearing but undocumented. This is the upstream contract for the
`story-foreign-session-user-message-tolerance` gap and the typed-error-codes
direction (operator Q1, 2026-07-04).

Seed draft (premise corrected, collision section invalidated): `.work/drafts/draft-protocol-targeting.md`.

## Scope

- `PROTOCOL.md` section pinning: `owner_pk` (per-machine), `room_id`
  (per-`(cwd, assigned-name)`, cwd-lock disambiguates), relay fanout to every
  conn at `(owner_pk, room)`, `user_message` targets one session via
  `session_id`.
- **Typed error codes:** disambiguate `session_mismatch` into
  `session_superseded` (phone's session_id is stale → re-sync) vs
  `not_my_session` (message was for a different pi → silent drop). Wire-format
  work in the generated protocol (TS + Dart) + app-side handling per code.
  Extension distinguishes via the session parent-chain.
- Property/conformance tests against the pinned invariants.

## Unblocks

- `story-foreign-session-user-message-tolerance`
- `story-fix-stale-ctx-messageapi-rearm-on-reload` (reopened)

## Out of scope

- The stale-ctx lifecycle contract (separate feature
  `feature-session-lifecycle-contract`).
- The `#2` stale-error repro (separate observe-and-diagnose task; do not block
  on it).

## Open decisions (from operator sanity-check, 2026-07-04)

- Typed-error-codes direction confirmed in principle; exact code names
  (`session_superseded` / `not_my_session`) to be finalized at design time.
- "Collision policy" question INVALIDATED (no collision occurred); the
  contract documents the cwd-lock as the disambiguator and treats two-same-named-pis
  as a lock violation to detect, not a topology to support.
