---
id: feature-session-lifecycle-contract
kind: feature
stage: drafting
tags: [pi-extension, app, relay, docs]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---
status: superseded
superseded_by: feature-contract-gap-audit, feature-reconnect-reproduction
superseded_date: 2026-07-04
---

> **SUPERSEDED 2026-07-04.** Split into `feature-contract-gap-audit`
> (session-lifecycle/transcript-identity invariants, harvested after review)
> and `feature-reconnect-reproduction` (reconnect attribution, gated on
> observability) under the reframed `epic-targeting-and-session-lifecycle-contracts`.
> See `.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`.

# Session-lifecycle & reconnect state-machine contract

## Brief

Pin two state machines that are currently improvised per surface, in
`PROTOCOL.md` + `docs/ARCHITECTURE.md`:

1. **Session-lifecycle (stale-ctx contract):** when a captured SDK ctx/pi may be
   used, what invalidates it (`newSession`/`fork`/`switchSession`/`reload`/
   `resume`/daemon-respawn), and what tolerates the gap window. Includes the
   **canonical transcript-event identity** contract (the live-vs-replay
   `eventId` collision root cause).
2. **Reconnect state machine:** the states the mobile-remote-coding skill
   already lists (`connected idle / working / reconnecting / offline /
   stale-unknown`), the transitions, who owns each state, and the rehydration
   contract.

## Scope

- `PROTOCOL.md` + `docs/ARCHITECTURE.md` sections pinning both state machines.
- Property/conformance tests against the invariants (the session-replacement
  harness from `feature-session-replacement-harness-and-observability` is the
  verification surface).
- Fold the grounded findings from already-active items into the contract:
  - `story-fix-stale-ctx-wrapactionctx-crash` (crash guard) → the
    "unguarded getter read" anti-pattern becomes a contract rule.
  - `story-mobile-chat-blank-on-pair-after-pre-pair-work` (backfill) → the
    "SDK is the durable owner; the log is the replay source" invariant.
  - `story-mobile-assistant-message-duplicated-live-replay` → the canonical
    transcript-event identity contract.

## Unblocks

- `story-fix-stale-ctx-messageapi-rearm-on-reload` (reopened)
- `story-mobile-assistant-message-duplicated-live-replay`
- The 2026-07-02 reconnect bug cluster:
  `idea-mobile-drop-slow-recovery`, `idea-mobile-drop-half-open-tcp`,
  `idea-extension-pumps-into-dead-app-peer`,
  `idea-mobile-outgoing-message-swallowed`,
  `idea-mobile-user-message-not-delivered-timeout`
- `idea-mobile-conflates-transport-and-agent-state`

## Out of scope

- The targeting model (separate feature `feature-targeting-delivery-contract`).
- Code changes — flow from the contract via the design family.
