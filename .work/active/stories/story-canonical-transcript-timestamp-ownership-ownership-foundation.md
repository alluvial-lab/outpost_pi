---
id: story-canonical-transcript-timestamp-ownership-ownership-foundation
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Timestamp-ownership foundation (extension owns the canonical ts)

Unit A of `feature-canonical-transcript-timestamp-ownership` — the foundation.
Make the execution/delivery hook the single canonical `ts` owner per event so
live broadcast == history == durable replay. Q1 decision = B; governing
principle: the extension is the sole authoritative `ts` owner.

## Change

- `pi-extension/src/session/transcript_event_log.ts` — add a recorded-`ts`
  lookup (e.g. `recordedTsFor(eventId)`) over the existing append-only,
  first-writer-wins `events`/`seen` (it exposes no ts lookup today).
- `pi-extension/src/session/sdk_session_projection.ts` (~`:563-573` + the
  `toolResult` arm) — `message_end`-driven recording REUSES the already-recorded
  `ts` (via the new lookup) for `tool_requested`/`tool_finished`/
  `user_confirmed`, instead of stamping the SDK block `ts`, so the late hook no
  longer competes with the earlier execution/delivery hook.
- `pi-extension/src/index.ts` — `tool_execution_start`/`tool_execution_end`,
  `_confirmUserDelivery` compute ONE `Date.now()` per logical event and share it
  across the history append and the live broadcast (no second stamp).

## START with the durability spike (riskiest assumption)

`TranscriptEventLog` is process-local; the SDK owns the DURABLE record that
backfills on restart. Unit A must FIRST spike whether the durable record can
carry the execution-hook `ts` (so live == durable across restart). If the SDK
cannot be made to agree durably, fall back to: the app re-syncs from
`session_history` on reconnect (canonical by then), so the render sort tolerates
a transient live≠durable pre-reconnect — document + accept that residual.

## Acceptance

- [ ] For tool-request, tool-result, and app-origin user-confirmed, the LIVE
  broadcast `ts` EQUALS the history/replay `ts` (producer-connected extension
  test, NOT an injected value).
- [ ] `TranscriptEventLog` exposes the recorded-`ts` lookup; no second
  `Date.now()` per logical event.
- [ ] Durability outcome documented (agreement achieved OR the accepted residual).

## Ordering

`depends_on: []` (foundation). Unlocks B and C.
