---
id: feature-session-stable-message-delivery-stale-wake-tolerance
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-session-stable-message-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-03
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

## References

- Parent: `feature-session-stable-message-delivery.md`.
- `pi-extension/src/index.ts:1859-1873` (`_wakeAgent`),
  `:1966-1975` (`_sendDeliveryError`), `:_deliverUserMessage`.
- `pi-extension/src/session/sdk_session_projection.ts` (`wakeAgent`, `forget`).
- `.agents/skills/pi-extension-typescript/SKILL.md` (stale-context rules).
