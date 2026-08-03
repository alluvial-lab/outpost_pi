---
id: feature-canonical-transcript-ordering
kind: feature
stage: drafting
tags: [app, pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Canonical transcript ordering (server-ts provenance + render sort)

## Brief

The phone transcript renders out of order after an offline-backlog flush +
reconnect: authoritative history generated during the gap arrives only on
`session_history` replay, is appended at a high arrival `seq` despite an older
server `ts`, and renders *after* newer live events (a later assistant reply
above an earlier user+assistant pair). The fix is not a comparator tweak: it
requires establishing **canonical server-`ts` provenance across every
authoritative event kind on the live path**, then sorting the rendered
authoritative bubbles by that `ts`. The store read must stay arrival/`seq`-ordered
(the lifecycle reducer depends on it across mixed clocks).

## Origin

Parked from `story-mobile-transcript-reorder-after-backlog-flush` (2026-08-03),
which carries the full forensic — including capture `963-…` showing **247
backfill events appended as new** during 07-27 02:20–02:27 reconnect bursts,
and the `9c5-…` capture (300/300 deduped, 0 appended) confirming the store was
stable by the afternoon. That story also records the **two fix attempts that
failed cross-model review** (`openai-codex/gpt-5.6-sol`, xhigh) and the
root realization driving this feature:

> The app does **not** have consistent canonical server-`ts` provenance across
> all authoritative event kinds on the live path. `AssistantDeltaReceived`,
> `ToolRequested`, and `ToolFinished` are stamped with phone-receipt
> `DateTime.now()` live; only replay supplies the canonical Pi `ts`.

- **Attempt 1 (store-level `(ts, seq)` sort):** REVERTED — mixed clocks
  phone-receipt-time deltas with server-time terminals and resurrected
  `streaming`; broke 3 convergence tests in `sync_service_test.dart`.
- **Attempt 2 (projection render-sort of authoritative bubbles only, lifecycle
  pass untouched):** REVERTED — resolved convergence (deltas never enter the
  authoritative list), but **tool bubbles still mix clocks**: the extension
  omits `ts` from live `tool_request`/`tool_result`
  (`pi-extension/src/index.ts:1356-1388`), so the app stamps tools with phone
  `DateTime.now()` (`sync_service.dart:1148-1169`); under phone/Pi skew a tool
  misorders vs. Pi-timestamped narrations. Arrival order previously kept tools
  correct, so this is a real regression.

## Chosen direction — (A) wire change

The extension already records Pi `Date.now()` for history; it just omits `ts`
from the **live** tool broadcast. Carry the canonical server `ts` on live
`tool_request`/`tool_result` (and audit the other flagged phone-`ts` live paths
— `UserInput` without `ts`, legacy/error assistant commits at
`sync_service.dart:1016-1067,1296-1299`) so every authoritative bubble has a
single-clock canonical `ts` on both live and replay paths. Then the attempt-2
projection render-sort becomes correct and lands as the final step.

Why A over the app-only **(B) anchor** alternative (give each tool bubble the
`ts` of its preceding server-`ts` message): A removes the root cause (missing
provenance) instead of papering over it, leaves no skew-dependent edge cases,
and makes the invariant "authoritative events always carry server `ts`"
explicit and enforceable. B is retained as a fallback if the wire change proves
out of scope for the next release.

## Scope sketch (for the `feature-design` pass)

Likely child stories with a `depends_on` chain:

1. **`pi-extension`: broadcast `ts` on live tool frames.** Add the canonical
   server `ts` (already captured for history) to the live `tool_request` /
   `tool_result` owner-channel broadcasts; update the app-pi schema
   (`protocol/schema/`) and generated DTOs. Backward-compatible (missing `ts`
   → phone-receipt fallback preserved for one release).
2. **`app`: consume server `ts` on live tool frames.** `ToolRequested` /
   `ToolFinished` use the wire `ts` when present (`sync_service.dart:1148-1169`);
   `ToolRequested` owns the tool bubble's sort `ts` (the request `ts`, not the
   result `ts`).
3. **`app`: canonical-ts render sort in `deriveTranscriptProjection`.** The
   attempt-2 design (parallel `messageTs`/`messageArrival` maps; sort
   `authoritativeMessages` by `(ts, arrivalIndex)` after the unchanged
   arrival-order lifecycle pass). Correct once (1)+(2) land. Includes the
   projection-layer regression test (user/assistant pair) **and** a new tool
   regression (skewed live receipt corrected by canonical replay).
4. **`app`: ts-provenance audit + cleanup.** Confirm the remaining live
   `DateTime.now()` paths (deltas are fine — they never render; but `UserInput`
   without `ts`, legacy/error assistant commits) either carry server `ts` or
   are provably excluded from the render sort.

(3) `depends_on` (1) and (2); (4) can run in parallel with (1).

## Wire-pairing & deploy note

This is an **extension ↔ app paired wire change** (additive/optional `ts` field
→ not a hard cutover, but both sides should ship together for the ordering fix
to take effect). Per `AGENTS.md` paired-wire-change discipline: rebuild the
extension `dist/`, fully restart Pi (not `/reload`), then sideload the app. The
relay is untouched (`ts` rides inside the existing owner-channel payload). If
the field is made required later, that becomes a hard-cutover pair and needs its
own release-binding note.

## Out of scope (parked latent issues, not this feature)

- **Transient partial projections during a backlog rewrite:** `box.put` per row
  + `SessionReadRepository` emits per row can expose a brief partial ordering
  during a large backlog rewrite. Non-blocking (no observed flicker); revisit
  if it surfaces.
- **`upsertTool` ignores `authoritativeIds.add` success** — broader
  `ValueKey(msg.id)` UI-key invariant; orthogonal to ordering.
- **Destructive `upsertTool` on result-before-request backfill** (review-1
  finding 3) — terminal tool status overwritten by a later pending request on
  out-of-order arrival. Pre-existing; track separately.

## Verification (per child story at implement time)

`flutter test --exclude-tags e2e` (full `app/` suite, with emphasis on
`test/domain/transcript/`, `test/data/sync/`, `test/data/local/`) +
`flutter analyze`; extension `corepack pnpm typecheck && test && build`; and a
cross-component E2E pairing smoke via `e2e/run-pairing.sh` given the wire
change. Final cross-model review before the render-sort child closes.
