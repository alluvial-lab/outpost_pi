---
id: feature-session-stable-message-delivery-stale-wake-tolerance
kind: story
stage: review
tags: [pi-extension, bug]
parent: feature-session-stable-message-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-04
---

# Stale-ctx tolerance on the wake path (no visible `internal_error`)

## Scope

Child of `feature-session-stable-message-delivery`. Implements the chosen fix:
when `_wakeAgent` (`pi-extension/src/index.ts:1859`) returns a stale-ctx
failure (or the immediate-after-replacement "agent session not bound yet"),
`_deliverUserMessage` must NOT surface `internal_error: Agent rejected incoming
message` to the phone.

## Background

The operator's reported `internal_error: …ctx is stale…` (and the follow-on
"agent session not bound yet") comes from `wakeAgent` → `sendUserMessage` on a
stale `messageApi`. Whatever the source of staleness (same-process harness
`/new`/`/resume`, or cross-process fanout to an idle pi with a replaced ctx),
a visible broken-permanent error is the wrong UX. See the parent feature for
the full corrected root-cause analysis.

## Implementation

1. In `_wakeAgent`, distinguish a **stale** failure from a **real** delivery
   failure using `isStaleContextError` (and the "agent session not bound yet"
   detail — the null-`messageApi` window). Return a distinguishable result so
   the caller can choose the wire shape.
2. In `_deliverUserMessage`, on a stale/not-bound-yet result:
   - Log a debug line (operator/dev visibility).
   - Choose wire shape (decide at implement time):
     - **(a)** Send nothing → phone's 20s send-timeout surfaces "not delivered"
       (accurate, noisy).
     - **(b)** Send a recoverable error code the app treats as "retry, not
       broken" — cleaner; needs an app-side change, so only if the app already
       has a retry path. Scope the app change as a sibling story if (b) is
       chosen.
   - Prefer (a) unless the app already supports a retry code; document the
     choice in the commit.
3. Real (non-stale) delivery failures MUST still surface `internal_error`
   unchanged.

## Acceptance criteria

- [ ] `wakeAgent` stale-ctx failure → no visible `internal_error: Agent
  rejected incoming message` on the phone.
- [ ] `wakeAgent` "not bound yet" (null messageApi window) → same tolerance.
- [ ] Real (non-stale) wake failure → `internal_error` still surfaces.
- [ ] Regression test: deliver a `user_message` to a projection whose
  `messageApi` throws stale → assert no `internal_error` sent (or recoverable
  code per chosen wire shape).
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`.

## Review (deep, fresh-context, 2026-07-04) — verdict: Block, addressed

A fresh-context gpt-5.5 review blocked on two findings:

1. **Root-cause reframing overstated coverage (Blocker).** `user_message` is
   session-scoped, so `_routeClientMessageFrom`'s `validateClientSession`
   gate rejects a foreign-session message BEFORE `_deliverUserMessage`/`wakeAgent`,
   emitting `error{code:"session_mismatch"}` — which the app renders as a
   visible ⚠ assistant-error row (`sync_service.dart:729-746`). So this fix only
   covers the **same-session stale wake** case (gate passes → stale wake →
   tolerated). The broad "idle/wrong pi is benign" claim is NOT achieved by
   this fix alone. Addressed by rescoping (below) + filing the foreign-session
   gap (`story-foreign-session-user-message-tolerance`).
2. **Missing route-level regression test (Important).** The 4 unit tests only
   prove `wakeAgent` classification, not that `_deliverUserMessage` suppresses
   `_sendDeliveryError` on recoverable (the actual phone-visible behavior).
   **Addressed:** added `stale wakeAgent on a non-disposed session tolerates
   (no visible internal_error)` in `extension.test.ts` — delivers a same-session
   `user_message` to a stale `messageApi`, asserts no `internal_error: Agent
   rejected incoming message` is sent. Passes.

Also noted (Important): null-`messageApi` tolerance is broader than stale
(always `recoverable:true`), which could mask a real binding regression for
20s. Accepted — the route-level test + the existing `console.warn` logging
are adequate for diagnosis; the binding-regression case would also surface
as "not delivered" via the phone's send-timeout.

## Scope correction (after review)

This fix tolerates **same-session stale wake**: the phone's `user_message`
carries a `session_id` that matches this pi's current session, the gate
passes, but the bound `messageApi` throws stale (ctx replaced in-process by
harness `/new`/`/resume`, or a stale-id collision). That is the operator's
reported *stale* symptom (the error string is the wakeAgent stale detail).

**Out of scope (filed separately):** cross-process foreign-session delivery —
where a duplicate pi with a *different* `session_id` receives the message and
the gate emits `session_mismatch`. That still produces a visible app error
and needs its own design (a pi cannot distinguish "duplicate delivery to the
wrong pi" from "phone held a stale session_id and is legitimately re-syncing",
so blindly tolerating `session_mismatch` would break the re-sync signal).
Tracked in `story-foreign-session-user-message-tolerance`.

## Implementation notes

- Files changed:
  - `pi-extension/src/extension/ports.ts` — added `recoverable?: boolean` to
    `WakeAgentResult`.
  - `pi-extension/src/session/sdk_session_projection.ts` — `wakeAgent` sets
    `recoverable: true` on the stale-ctx path and the null-`messageApi`
    ("agent session not bound yet") path; real delivery failures leave it false.
  - `pi-extension/src/index.ts` — `_wakeAgent` logs (warn, not error) and
    returns on recoverable; `_deliverUserMessage` skips `_sendDeliveryError`
    on recoverable (silent tolerance — phone's existing 20s send-timeout surfaces
    "not delivered" if nothing ever handles it).
- Tests added (`sdk_session_projection.test.ts` — `wakeAgent recoverable
  failures` describe block, 4 tests):
  - stale `sendUserMessage` → `recoverable: true` + binding forgotten.
  - null `messageApi` window → `recoverable: true` ("agent session not bound yet").
  - non-stale delivery error → `recoverable: false` (still surfaces).
  - successful wake → `recoverable: undefined` (not recoverable).
- Wire shape chosen: **(a) silent** — send nothing on recoverable failure.
    No app-side change needed; the phone's existing send-timeout handles the
    "nothing handled this" case accurately without a permanent broken state.
    Option (b) recoverable error code was rejected because the app has no
    existing retry-on-code path; (a) is the smaller, correct fix.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: `tsc --noEmit` clean; full suite 738 pass / 3 pre-existing
  skips / 0 regressions; `tsc` build clean, `dist/` rebuilt.
- Not deployed: needs a full pi process restart (parked
  `idea-mobile-restart-pi-session-affordance` is the mobile-path blocker).

## References

- Parent: `feature-session-stable-message-delivery.md`.
- `pi-extension/src/index.ts:1859-1873` (`_wakeAgent`),
  `:1966-1975` (`_sendDeliveryError`), `:_deliverUserMessage`.
- `pi-extension/src/session/sdk_session_projection.ts` (`wakeAgent`, `forget`).
- `.agents/skills/pi-extension-typescript/SKILL.md` (stale-context rules).
