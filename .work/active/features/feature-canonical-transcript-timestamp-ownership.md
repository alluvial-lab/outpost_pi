---
id: feature-canonical-transcript-timestamp-ownership
kind: feature
stage: implementing
tags: [app, pi-extension, bug]
parent: epic-durable-transcript-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Canonical transcript timestamp ownership (close the single-clock invariant)

> **Rescoped 2026-08-03 under `epic-durable-transcript-ownership`.** The
> durable-ownership architecture (custom-entry persistence) is now owned by
> that epic. This feature is the **seed for the epic's F1 (durable foundation)
> + F2 (timestamp payoff)**; `epic-design` will reconcile — likely splitting
> Unit A (durable foundation) into F1 as a sibling feature. The 4 child stories
> below remain a valid design sketch pending that decomposition.

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

## Implementation Units (feature-design pass, 2026-08-03)

The decided design (Q1=B, extension sole authority; Q2=a, mesh authoritative)
decomposes into 4 child-story checkpoints. Trickiest unit (A) first.

### Unit A — Timestamp-ownership foundation (extension)
**Story**: `story-canonical-transcript-timestamp-ownership-ownership-foundation`
**Depends on**: none (foundation).

Make the execution/delivery hook the single canonical `ts` owner per event, so
live broadcast == history == durable replay.

**Files**:
- `pi-extension/src/session/transcript_event_log.ts` — add a recorded-`ts`
  lookup (e.g. `recordedTsFor(eventId): number | undefined`) over the existing
  `events`/`seen` structures (the log is append-only, first-writer-wins by
  `eventId`; today it exposes no ts lookup).
- `pi-extension/src/session/sdk_session_projection.ts` (~`:563-573` and the
  `toolResult` arm) — `message_end`-driven recording **reuses** the
  already-recorded `ts` (via the new lookup) for `tool_requested`/
  `tool_finished`/`user_confirmed` instead of stamping the SDK block `ts`, so
  the late hook no longer competes with the earlier execution/delivery hook.
- `pi-extension/src/index.ts` — `tool_execution_start`/`tool_execution_end`,
  `_confirmUserDelivery` broadcast sites read + reuse the owner `ts` (one
  `Date.now()` per event, shared by the history append and the live broadcast).

**Acceptance**:
- [ ] For tool-request, tool-result, and app-origin user-confirmed, the LIVE
  broadcast `ts` EQUALS the history/replay `ts` (producer-connected extension
  test, not an injected value).
- [ ] `TranscriptEventLog` exposes the recorded-`ts` lookup; no second
  `Date.now()` per logical event.

### Unit B — Extension producer-`ts` coverage (agent_done, user_message echoes, mesh cards)
**Story**: `story-canonical-transcript-timestamp-ownership-extension-producer-ts`
**Depends on**: [Unit A].

Stamp a server `ts` on the authoritative producers that still omit it.

**Files**:
- `pi-extension/src/index.ts` — `agent_end`/`agent_done` broadcast includes the
  terminal `ts`; initial + dedupe `user_message` echoes reuse the existing
  recorded `ts` (via Unit A's lookup) instead of emitting ts-less frames.
- `pi-extension/src/index.ts` `_deliverMeshMessageToAgent` (Q2=a) — stamp a
  server `ts` on the `tool="agent-network"` `tool_request`/`tool_result` pair.

**Acceptance**:
- [ ] `agent_done`, `user_message` echoes, and `tool="agent-network"` frames
  carry a server `ts` equal to their history/owner `ts` (producer-connected
  tests).

### Unit C — Error-frame `ts` (schema + extension + app + codegen)
**Story**: `story-canonical-transcript-timestamp-ownership-error-frame-ts`
**Depends on**: [Unit A] (parallel with B).

The error path is schema-spanning (like the prior feature's Unit 1), so it's its
own checkpoint.

**Files**:
- `protocol/schema/app-pi-server.schema.json` — add optional `ts` (integer,
  min 0) to the `error` message definition.
- `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` + regenerate
  `protocol.generated.ts` (`corepack pnpm generate:protocol`) and
  `protocol.g.dart` (`protocol-codegen.mjs --target dart --schema <fixture>
  --out app/lib/protocol/generated/protocol.g.dart`). Rust unchanged.
- `pi-extension/src/index.ts` error producers (incl. `provider_error`,
  `internal_error`, other renderable codes) — stamp the computed server `ts`.
- `app/lib/data/sync/sync_service.dart` — error diagnostic consumes wire `ts`
  with the `DateTime.now()` fallback.

**Acceptance**:
- [ ] Optional `ts` on error frames; extension stamps it; app consumes it;
  `check:protocol` clean; error diagnostic no longer phone-timestamped.

### Unit D — App consume + fallback cleanup
**Story**: `story-canonical-transcript-timestamp-ownership-app-consume-cleanup`
**Depends on**: [Unit B, Unit C].

Close the app-side residuals now that every producer carries server `ts`.

**Files**:
- `app/lib/data/sync/sync_service.dart` — buffered tool fallback narration uses
  one derived `requestTs` (from the wire `ts`, legacy fallback) shared with the
  `ToolRequested`, not an independent `DateTime.now()`.
- Verify EVERY authoritative producer consumes wire `ts`; `DateTime.now()` only
  for genuinely-missing fields.

**Acceptance**:
- [ ] No authoritative app event stamps `DateTime.now()` when the wire carries
  `ts`; producer-connected app tests assert real wire `ts` flow.
- [ ] The (updated) enumeration table shows zero remaining authoritative
  phone-`ts` paths.

## Implementation Order

1. **A** (ownership foundation) — design-first; resolves the durable-owner
   model (see Risks).
2. **B** and **C** in parallel after A.
3. **D** after B + C.

## Risks (pre-mortem)

- **Riskiest assumption — SDK durability agreement (Unit A).** `TranscriptEventLog`
  is process-local; the SDK owns the DURABLE record that backfills on restart.
  Reusing the execution-hook `ts` in `message_end` fixes in-process live/replay
  divergence, but post-restart backfill may re-stamp the SDK `ts`. Unit A must
  START by spiking whether the durable record can carry the execution-hook `ts`
  (so live == durable across restart). If the SDK cannot be made to agree
  durably, fall back to: the app re-syncs from `session_history` on reconnect
  (canonical by then), so the render sort tolerates a transient live≠durable
  pre-reconnect — document and accept that residual.
- Error-frame codegen (Unit C) reuses the Unit-1 pattern; low risk.

## Testing

- Producer-connected tests in every unit (extension: live `ts` == history `ts`;
  app: real wire `ts` flow) — the prior synthetic-ts tests are the anti-pattern.
- Extension: `check:protocol`, `typecheck`, `test` (full suite's only known
  nonzero-exit is the parked hot-reload flake).
- App: `flutter test --exclude-tags e2e test/domain test/data test/ui/chat`;
  the 3 `streaming`-convergence guards as sentinels.
- Final cross-model review walks the updated enumeration table to confirm zero
  remaining authoritative phone-`ts` paths.

## Out of scope

The projection render sort (done in the prior feature; correct once this
feature closes the invariant). The store. Unrelated code.

## Verification (at implement time)

`flutter test --exclude-tags e2e` (app domain/data/chat + the 3
`streaming`-convergence guards), extension `check:protocol`/`typecheck`/`test`,
cross-component `e2e/run-pairing.sh`, and a final cross-model review that
walks the (updated) enumeration table to confirm zero remaining authoritative
phone-`ts` paths.
