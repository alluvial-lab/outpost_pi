---
id: feature-canonical-transcript-timestamp-ownership
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

# Canonical transcript timestamp ownership (close the single-clock invariant)

## Brief

`feature-canonical-transcript-ordering` shipped the projection render-sort
(Unit 3), which is correct for every authoritative bubble that carries a
canonical server `ts`. A systematic enumeration (see
`story-canonical-transcript-ordering-systematic-ts-provenance-sweep`) proved
the remaining gaps are not patchable piecemeal — they stem from **timestamp
ownership** being decided by first-writer-wins process-local dedupe, so live
broadcasts and durable replay disagree, and from an unresolved question about
**app-facing mesh tool notifications**. This feature closes the invariant.

## Design decisions (operator, 2026-08-03)

- **Q1 — timestamp ownership: (B).** The execution/delivery hook owns each
  event's canonical `ts` (it fires first AND broadcasts live, so its `ts` is
  available at broadcast time); `message_end` is changed to **reuse** the
  already-recorded `ts` instead of stamping a fresh one, so live == replay ==
  durable-across-restart. Governing principle: **the extension (Pi/SDK) is the
  sole authoritative `ts` owner; the app is consumer-only** (`DateTime.now()`
  only as a transient fallback for a genuinely-missing field); the app's own
  clock is confined to non-authoritative optimistic UI state (`UserMessageSubmitted`
  local tail). The relay has no transcript-`ts` role (opaque transport).
- **Q2 — app-facing mesh tool notifications: (a) authoritative.** The
  `tool="agent-network"` cards (`_deliverMeshMessageToAgent`) are real
  transcript bubbles. Rationale: keeps the inbound peer message + the agent's
  reply in ONE coherent, reconnect-durable, canonically-ordered transcript, so
  future hide/filter/UX changes are a single-place view-layer operation over a
  complete dataset (the `tool="agent-network"` discriminator already exists).
  Mechanical consequence (consistent with Q1): the **extension stamps a server
  `ts`** on these frames; the app consumes it.

## Origin / seed

The complete gap surface is enumerated in
`.work/active/stories/story-canonical-transcript-ordering-systematic-ts-provenance-sweep.md`
(read it — it is the ground-truth table for this feature). Summary of what's
broken and why:

- **Live/replay `ts` divergence** for tools (start hook stamps a fresh
  `Date.now()`; `message_end` already recorded the SDK `ts`; the start hook's
  history append loses the dedupe), tool-result across restart, and app-origin
  user confirmation (`_confirmUserDelivery` vs SDK `message_end`).
- **Missing live `ts`** on `agent_done`, error frames (no schema `ts`), initial
  + dedupe `user_message` echoes.
- **App phone-time stamping** in fallback paths (buffered tool narration,
  error diagnostics, agent-network tool frames).
- **Mesh path** `_deliverMeshMessageToAgent` broadcasts app-facing
  `tool_request`/`tool_result` with no `ts` → app persists them as
  authoritative bubbles with phone time.

## The two design questions (front this feature's design pass)

### Q1 — Durable timestamp ownership

Which hook owns the canonical `ts` for each event, and how does that owner
survive process restart / late hooks? Today ownership is implicit
(first-writer-wins on the deterministic event id), so the SDK `message_end`
timestamp (recorded early for tools/user/assistant) competes with the
delivery/execution hooks' `Date.now()` and they disagree across restart.

Candidate: **SDK `message_end` is the durable owner** for user/assistant/tool
events; every live broadcast *looks up and reuses* the already-recorded `ts`
rather than stamping a new one; `TranscriptEventLog` exposes the recorded `ts`
by event id so broadcast sites read it. Requires deciding what owns events
that have no SDK `message_end` (errors, agent_done boundary, mesh
notifications).

### Q2 — App-facing mesh tool notifications

`_deliverMeshMessageToAgent` deliberately sends app-facing `tool_request`/
`tool_result` (the app renders them in the tool timeline). Two resolutions:

- **(a) Authoritative:** they are real transcript bubbles → they need a server
  `ts` (the extension stamps one; app consumes it).
- **(b) Non-authoritative:** they are UI-only state → stop persisting them as
  `ToolRequested`/`ToolFinished`; render them from a non-authoritative channel
  so they don't enter the render sort.

## Mechanical closure (once Q1/Q2 are decided)

- Add optional `ts` to error frames (schema + dart fixture + regen; pattern
  from Unit 1) and stamp it at every error producer.
- Fix initial + dedupe `user_message` echoes to reuse the existing server `ts`.
- App: derive one `requestTs` for the buffered tool narration + tool request;
  consume wire `ts` everywhere it exists.
- Producer-connected tests (extension asserts live `ts` == history `ts`;
  app asserts real wire `ts` flow).

## Out of scope

The projection render sort (done in the prior feature; correct once this
feature closes the invariant). The store. Unrelated code.

## Verification (at implement time)

`flutter test --exclude-tags e2e` (app domain/data/chat + the 3
`streaming`-convergence guards), extension `check:protocol`/`typecheck`/`test`,
cross-component `e2e/run-pairing.sh`, and a final cross-model review that
walks the (updated) enumeration table to confirm zero remaining authoritative
phone-`ts` paths.
