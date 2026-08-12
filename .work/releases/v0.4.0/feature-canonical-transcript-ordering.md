---
id: feature-canonical-transcript-ordering
kind: feature
stage: done
tags: [app, pi-extension, bug]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-03
updated: 2026-08-11
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
authoritative bubbles by that `ts`. The store read stays arrival/`seq`-ordered
(the lifecycle reducer depends on it across mixed clocks).

## Origin

Parked from `story-mobile-transcript-reorder-after-backlog-flush` (2026-08-03),
which carries the full forensic (capture `963-…`: 247 backfill events appended
during 07-27 02:20–02:27 reconnect bursts; `9c5-…`: 300/300 deduped by
afternoon) and the two fix attempts that failed cross-model review
(`openai-codex/gpt-5.6-sol`, xhigh):

- **Attempt 1 (store-level `(ts, seq)` sort):** mixed phone-receipt-time deltas
  with server-time terminals, resurrected `streaming`; broke 3 convergence
  tests. Reverted.
- **Attempt 2 (projection render-sort of authoritative bubbles only):** resolved
  convergence, but tool bubbles still mix clocks — the extension omits `ts` from
  live `tool_request`/`tool_result`, so the app stamps tools with phone
  `DateTime.now()`; under skew a tool misorders vs. narrations. Reverted.

Root realization: the app lacks consistent canonical server-`ts` provenance
across all authoritative event kinds on the live path (`AssistantDeltaReceived`,
`ToolRequested`, `ToolFinished`, and some user/error paths use phone/local
time live; only replay supplies the canonical Pi `ts`).

## Architectural choice — (A) wire change

Carry the canonical server `ts` on the live `tool_request`/`tool_result` frames
(the extension already computes `Date.now()` for the history log at
`pi-extension/src/index.ts:1349,1373,1381` — it just omits it from the live
broadcast at `:1356-1361,:1387-1388`), then land the attempt-2 projection
render-sort now that every authoritative bubble carries a single-clock
canonical `ts`.

Chosen over **(B) app-only anchor** (give each tool the `ts` of its preceding
server-ts message): A removes the root cause (missing provenance) rather than
papering over it, leaves no skew-dependent edge cases, and makes the invariant
"authoritative events always carry server `ts`" explicit. B is retained as the
documented fallback if the wire change is deferred.

## Design decisions

- **`ts` on the wire is OPTIONAL (additive).** No hard cutover this release:
  old app ignores it (keeps the `DateTime.now()` fallback); old extension
  omitting it → new app falls back. A later required-`ts` bump would be its own
  hard-cutover pair. Rationale: ship the fix without forcing a paired
  extension+app version constraint.
- **Tool bubble sorts by REQUEST `ts`** (the earlier of request/result), not
  result `ts`. A tool call occupies the timeline position where it started, and
  the result mutates that same bubble rather than defining a new position.
  Implemented as `messageTs[toolCallId] = min(existing, ts)` on every tool
  upsert, so it holds whether request or result arrives first (backfill can
  deliver result-before-request).
- **Both `tool_request` and `tool_result` carry `ts`.** The result frame's `ts`
  is needed when only a result is delivered live, and keeps the wire uniform.
- **Store read stays `(seq, eventId)`.** The lifecycle reducer is order-
  sensitive across mixed clocks; only the rendered authoritative list is
  re-sorted, after the unchanged arrival-order pass.
- **Deltas (`AssistantDeltaReceived`) are untouched.** They never enter
  `authoritativeMessages` (only set `streaming`); their phone-receipt `ts` does
  not participate in the render sort.

## Implementation Units

### Unit 1 — Extension: broadcast canonical `ts` on live tool frames
**Story**: `story-canonical-transcript-ordering-extension-broadcast-tool-ts`

**Files**:
- `pi-extension/src/index.ts` — `tool_execution_start` (~1342) and
  `tool_execution_end` (~1369) handlers.
- Shared protocol schema source (the codegen input under the protocol root's
  `schema/` dir, consumed by `tools/protocol-codegen`; pin the exact file when
  implementing). Regenerates `pi-extension/src/protocol/generated/protocol.generated.ts`
  and `app/lib/protocol/generated/protocol.g.dart`.

**Change**:
```ts
ownerPi.on("tool_execution_start", (event) => {
  ...
  const ts = Date.now();                 // already computed for _appendTranscriptEvent
  _appendTranscriptEvent({ ..., ts });   // unchanged
  ...
  _owners.broadcast(_withCurrentSession({
    type: "tool_request",
    tool_call_id: event.toolCallId,
    tool: event.toolName,
    args,
    ts,                                  // NEW: canonical server ts
  }));
});
```
Same for `tool_result` (`error`/`result` variants). Schema: add optional
`ts` (integer, epoch ms) to the `tool_request` and `tool_result` message
definitions. Run `corepack pnpm generate:protocol` (extension) and the app's
protocol regenerate step.

**Acceptance**:
- [ ] Live `tool_request`/`tool_result` broadcasts carry `ts` (epoch ms) equal
  (±tolerance) to the `_appendTranscriptEvent` history `ts` for the same call.
- [ ] Generated TS + Dart wire types include the optional `ts` field;
  `corepack pnpm check:protocol` passes; existing extension tool tests updated
  and green.

### Unit 2 — App: consume server `ts` on live tool frames
**Story**: `story-canonical-transcript-ordering-app-consume-tool-ts`
**Depends on**: Unit 1

**Files**:
- `app/lib/protocol/generated/protocol.g.dart` — `ToolRequest`/`ToolResult`
  (generated; gain optional `ts`).
- `app/lib/data/sync/sync_service.dart:1101` (`case ToolRequest`) and `:1162`
  (`case ToolResult`).

**Change**:
```dart
case ToolRequest(:final toolCallId, :final tool, :final args, :final ts):
  ...
  toolEvents.add(ToolRequested(
    ...
    ts: ts != null
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : DateTime.now(),   // fallback for old extension / frame without ts
    ...
  ));
```
Same fallback for `ToolFinished` in the `case ToolResult` arm.

**Acceptance**:
- [ ] A live `tool_request` with `ts` yields a `ToolRequested` carrying that
  server `ts` (not `DateTime.now()`).
- [ ] A frame without `ts` still falls back to `DateTime.now()` (no regression
  for old extension).

### Unit 3 — App: canonical-`ts` render sort in `deriveTranscriptProjection`
**Story**: `story-canonical-transcript-ordering-projection-render-sort`
**Depends on**: Unit 2 (transitively Unit 1 — needs server `ts` on tools to be correct)

**Files**:
- `app/lib/domain/transcript/transcript_projection.dart`.

**Change** (the verified attempt-2 design, now correct): thread each
authoritative message's event `ts` (ms) + an arrival index into `messageTs` /
`messageArrival` during the pass (`appendAuthoritative(msg, ts)` and
`upsertTool(tool, ts)`); leave the arrival-order lifecycle pass byte-for-byte
unchanged; AFTER the pass, sort `authoritativeMessages` by `(ts, arrivalIndex)`
before assembling `messages`. For tools: `messageTs[toolCallId]` takes the
`min` of the request/result `ts` so the bubble sorts by request time regardless
of arrival order.

```dart
authoritativeMessages.sort((a, b) {
  final byTs = (messageTs[a.id] ?? 0).compareTo(messageTs[b.id] ?? 0);
  if (byTs != 0) return byTs;
  return (messageArrival[a.id] ?? 0).compareTo(messageArrival[b.id] ?? 0);
});
```
The existing prompt-before-reply fixup stays (same-`ts` safety net).

**Acceptance**:
- [ ] Regression: live user(T)+assistant(T+100), then replay-backfill
  user(T+50)+assistant(T+60) → messages `[cli_1, cli_2, msg_2, msg_1]`
  (canonical), red before the sort.
- [ ] **Tool regression (new):** with phone clock skewed ahead, a tool
  request/result carrying server `ts` lands between its surrounding narrations,
  not after them; result-before-request backfill still sorts by request `ts`.
- [ ] The 3 `streaming`-convergence tests in `sync_service_test.dart`
  (compaction-live, compaction-replay, history-replay) stay green — lifecycle
  pass untouched.

### Unit 4 — App: ts-provenance audit of remaining live `DateTime.now()` paths
**Story**: `story-canonical-transcript-ordering-ts-provenance-audit`
**Depends on**: none (parallel with Unit 1)

**Files**: `app/lib/data/sync/sync_service.dart` — the other live
`DateTime.now()` paths flagged by review: `UserInput` without `ts`
(~:1016-1067), legacy/error assistant commits (~:1296-1299); confirm deltas
(~:894) are provably excluded from the render sort (they only set `streaming`).

**Change**: for each path, either thread a server `ts` (if the wire carries
one) or document why it is excluded from the authoritative render list. Fix any
path found to leak phone `ts` into an authoritative bubble, with a test.

**Acceptance**:
- [ ] Audit note recorded: every authoritative-bubble-producing event kind
  carries server `ts` on the live path, OR is documented as excluded from the
  render sort.
- [ ] Any leak found is fixed + tested.

## Implementation Order

1. **Unit 4** (audit) — parallel; establishes the full provenance surface.
2. **Unit 1** (extension wire `ts` + schema + regen) — parallel with Unit 4.
3. **Unit 2** (app consume) — `depends_on` Unit 1.
4. **Unit 3** (projection render sort) — `depends_on` Unit 2 (transitively 1).

## Wire-pairing & deploy

Additive optional `ts` → **not a hard cutover**; both sides should still ship
together for the ordering fix to take effect. Per `AGENTS.md`: rebuild extension
`dist/`, fully restart Pi (not `/reload`), then sideload the app. Relay
untouched (`ts` rides inside the existing owner-channel payload). A future
required-`ts` bump becomes its own hard-cutover pair.

## Testing

- **Extension (Unit 1):** live broadcast carries `ts`; `check:protocol` clean;
  generated types round-trip in both languages.
- **App (Unit 2):** `ToolRequested`/`ToolFinished` use server `ts` when present;
  fallback when absent.
- **App (Unit 3):** projection render-sort regression (user/assistant + the new
  tool skew/result-before-request case); the 3 convergence tests as
  no-lifecycle-regression guards.
- **Cross-component:** `e2e/run-pairing.sh` smoke for the wire change.
- Final cross-model review (`openai-codex/gpt-5.6-sol`) before Unit 3 closes.

## Risks (pre-mortem)

- **Riskiest assumption:** the codegen round-trips the optional `ts` cleanly for
  both TS and Dart and old apps tolerate the extra field. Mitigation: optional
  field + fallback; run both codegen + full suites + the e2e pairing smoke.
- **Tool `min`-ts logic:** long-running tools (request ≪ result) sort by request
  time — correct (tool appears where it started). Low risk; covered by the tool
  regression.
- **Unaudited live `DateTime.now()` path leaking into the render sort** — this
  is exactly Unit 4's job; it must close before the feature closes.

## Out of scope (parked latent issues)

- Transient partial projections during a backlog rewrite (per-row `box.put` +
  per-row repository emit). Non-blocking; revisit if it flickers.
- `upsertTool` ignoring `authoritativeIds.add` success (broader `ValueKey`
  invariant).
- Destructive `upsertTool` on result-before-request backfill (terminal status
  overwritten by a later pending request) — pre-existing; track separately.

## Implementation summary (2026-08-03)

All four child stories landed and verified; the feature is review-ready.

| Unit | Story | Commit | Outcome |
|---|---|---|---|
| 1 — extension broadcasts tool `ts` | `…-extension-broadcast-tool-ts` | `0a048de` | optional `ts` on LIVE `toolRequest`/`toolResult` schema + dart IR fixture; extension broadcasts the history `Date.now()` on owner-channel tool frames; TS+Dart regenerated; Rust untouched (app-pi excluded by design) |
| 2 — app consumes tool `ts` | `…-app-consume-tool-ts` | `a51fd5f` | `ToolRequested`/`ToolFinished` use the wire `ts` with `DateTime.now()` fallback, mirroring the existing user/assistant/compaction pattern |
| 3 — projection render sort | `…-projection-render-sort` | `455dce8` | `deriveTranscriptProjection` sorts the authoritative bubbles by canonical server `ts` (arrival-index tiebreak) AFTER the unchanged arrival-order lifecycle pass; tool bubbles take the earliest request/result `ts` |
| 4 — ts-provenance audit | `…-ts-provenance-audit` | `c9c9495` | confirmed user/assistant/compaction already thread server `ts`; **found + fixed** an `AgentDone` fallback leak (phone→server `ts`); error-diagnostic documented as a wire-has-no-`ts` compat exception |

Key as-built notes:

- **Dart protocol source-of-truth** is the committed fixture
  `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` (maintained in
  lockstep with the schema), regenerated via
  `protocol-codegen.mjs --target dart --schema <fixture> --out protocol.g.dart`.
  There is no `generate:dart` wrapper script (a tooling gap worth a future
  cleanup); the orchestrator derived the command by reproducing a byte-identical file.
- A **pre-existing** hot-reload restart-sweep `ENOENT` race makes the full
  extension suite exit nonzero on HEAD too (all 962 tests pass); parked as
  `backlog-extension-hot-reload-restart-sweep-enoent-race` (`ac8c4c5`), not
  folded into any item.

## Integrated verification

- App: `flutter test --concurrency=2 --exclude-tags e2e test/domain test/data
  test/ui/chat` → **524 passed** (incl. the new user/assistant + tool
  regressions and the 3 `streaming`-convergence guards as no-lifecycle-regression
  sentinels).
- Extension: `check:protocol` ✅, `typecheck` ✅, focused tool-visibility 8/8 ✅,
  generated-dart `flutter analyze` ✅. Full suite green save the parked flake.
- Wire compatibility: `ts` is optional on every path; old app/extension fall
  back to `DateTime.now()`. No hard cutover.
- Not yet run: cross-component E2E pairing smoke (`e2e/run-pairing.sh`) and the
  deploy (extension `dist/` rebuild + full Pi restart + app sideload) — these
  are deploy/UAT steps, not story verification.

## Review (standard, pass 1 — `gpt-5.6-sol` xhigh): REQUEST CHANGES

Core fix (Unit 3) sound; neither prior regression reintroduced; tool min-ts,
backward-compat, agent-network exclusion all confirmed safe. But the
single-clock invariant Unit 3 relies on is **not yet fully achieved** — 4
remaining clock-mixing paths in edge/secondary paths (the main
user/assistant/tool path is fixed):

1. **Tool live/history `ts` divergence.** `message_end` records `tool_requested`
   with the SDK assistant `ts` (`sdk_session_projection.ts:563-573`);
   `tool_execution_start` broadcasts a fresh `Date.now()` whose history append
   is discarded (duplicate event-id, first-writer-wins). So live tool `ts` ≠
   replay tool `ts` → a tool bubble can shift on reconnect. Fix: one ts owner
   (reuse the recorded request ts in the broadcast, or make `tool_execution_start`
   the sole recorder).
2. **Buffered assistant fallback narration** (`sync_service.dart:1140-1150`)
   uses `DateTime.now()` while the tool uses wire `ts`. When the deterministic
   `agent_message` is absent (frame loss/compat), narration sorts by phone time
   + tool by server time → attempt-2 failure under skew. Fix: derive one
   `requestTs` from the wire `ts` (legacy fallback) for both.
3. **`AgentDone` producer gap.** The audit's app-side consume is dead code: the
   extension records a terminal `ts` but omits it from the live `agent_done`
   frame (`index.ts:1457-1474`), so the app always hits `DateTime.now()`. Fix:
   extension includes `ts` in the `agent_done` broadcast.
4. **Error diagnostics** — no `ts` on the wire (schema `:188-197`); the app
   creates an authoritative `AssistantMessageCommitted` with phone time
   (`sync_service.dart:1310-1326`). Under skew an error bubble misorders. Fix:
   optional `ts` on error frames (schema+extension+app, like a mini-Unit-1),
   OR model diagnostics as non-authoritative/local-tail.

This is the third round of clock-provenance discovery (attempt 1: deltas;
attempt 2: tools; now: tool-history-divergence + fallback narration +
agent_done producer + error diagnostics) — strong signal that fully closing
the single-clock invariant is a deeper arc than one feature pass. Decision
pending operator input: grind another corrective wave vs. land the main fix +
park these 4 edge-path findings as follow-ups.

## Blocker

Feature held at `stage: review` pending resolution of the 4 review findings
above (or an explicit operator decision to ship the main-path fix and track
the edge gaps as follow-up stories).

## Resolution (operator, 2026-08-03)

**Shipped as-is; closure spun to a new feature.** Units 1–4 are verified and
fix the observed reorder bug on the dominant user/assistant/tool path. A
systematic enumeration (option C; recorded in
`story-canonical-transcript-ordering-systematic-ts-provenance-sweep`) proved
the single-clock invariant is a design arc, not a patch — it found the 4 review
gaps + 3 more + a mesh-path scope contradiction, and showed closure needs a
durable timestamp-*owner* design + an app-facing-mesh-notification decision.

This feature therefore closes at `done` with the residual gap paths
(skew-dependent: error diagnostics, fallback narration, restart/backfill
tool-result divergence, app-facing mesh tool notifications) **fully enumerated
and documented** in the sweep story, not hidden. Full invariant closure is
spun to `feature-canonical-transcript-timestamp-ownership` (drafting), seeded
by that enumeration. Operator override to close despite the REQUEST-CHANGES
review: the main fix ships; the closure is tracked separately.
