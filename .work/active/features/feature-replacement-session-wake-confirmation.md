---
id: feature-replacement-session-wake-confirmation
kind: feature
stage: done
tags: [pi-extension, app, bug, session, lifecycle]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: v0.3.0
gate_origin: null
created: 2026-07-21
updated: 2026-07-24
---

# Fix replacement-session wake confirmation gating on the full agent turn

## Brief

After a mobile `/new` (session replacement), the first message in the new
session exhibits two user-visible symptoms that are facets of one mechanism:
(1) a misattributed `sync_<ts>` echo instead of the sent `cli_` id, and (2)
the real `cli_` echo and `wake_outcome` delayed by 5.5s–71s vs. the ~100ms
baseline on a stable session. The agent was never stuck — it was working the
whole time — but the app's 20s echo-wait can fire falsely (`msgFailed
send_timeout`) and the late real echo renders as a duplicate after the agent's
turn.

Root cause is CONFIRMED and code-verified (see
`story-mobile-stuck-message-after-new-session-replacement.md`): the
replacement session context's `sendUserMessage` returns the full-turn
`Promise`, and Outpost-Pi unconditionally awaits it. The `sync_` echo is a
symptom (the `cli_`→message mapping isn't recorded until `_confirmUserDelivery`
runs after the await), not the cause.

## The design decision this feature must make

There are two separable problems, and the design must decide how far to go:

### Problem A (the echo) — record the mapping before the await

The `cli_`→message mapping is recorded in `_confirmUserDelivery`
(`pi-extension/src/index.ts:2334-2368`), which runs **after** the awaited
wake. But `message_end` fires **during** the turn, calls
`appendLegacySdkMessageToTranscript` (`sdk_session_projection.ts:468-475`),
finds no mapping, and falls back to `sync_${ts}`.

**Minimal fix:** record the `cli_` mapping **before** the awaited wake, so
`message_end` finds it and broadcasts the real `cli_` id immediately. This
kills the `sync_` echo and lets the app's echo-wait settle at ~100ms. The
existing factory-binding path already does this implicitly (the `void` return
means `_confirmUserDelivery` runs before `message_end`).

This is a behavior-preserving fix: the only observable change is that the
`sync_` echo becomes a `cli_` echo. It does not change `wake_outcome` timing.

### Problem B (the await semantics) — should `wake_outcome` gate on the turn?

`wake_outcome` is logged after `await api.sendUserMessage(...)`
(`sdk_session_projection.ts:680-688`). On the factory binding this settles in
~100ms (the API returns `void`). On the replacement binding it settles only
when the full agent turn completes (the API returns `Promise<void>` that
resolves at turn settlement).

This is a **contract question**: should `wake_outcome`/`msg_delivered` mean
"the agent was invoked" (acceptance) or "the agent turn completed"
(completion)? Currently it means different things on different bindings,
which is itself the bug. The diagnostic agent observed: "with a replacement
context, `wake_outcome` semantically means 'the agent turn settled,' not
'the agent was woken.'"

**Options:**
- **B1 (do nothing here):** once Problem A is fixed, the `sync_` echo is gone
  and the app's echo-wait settles fast — the user-visible symptoms vanish
  regardless of when `wake_outcome` fires. `wake_outcome`/`msg_delivered`
  remain turn-gated on the replacement binding, but nothing user-visible
  depends on their timing anymore. Lowest risk; defers the contract question.
- **B2 (don't await the turn):** stop awaiting the replacement context's
  `sendUserMessage` (fire-and-forget, like the factory path). `wake_outcome`
  fires at invocation, matching the factory semantic. Risk: the diagnostic
  log and any consumer of `msg_delivered` lose the "turn actually ran"
  signal; `recoverable` failure detection (stale ctx) may weaken.
- **B3 (await, but log acceptance separately):** keep awaiting, but add an
  `accepted`/`invoked` log event at call time (before the await) so the
  delivery log distinguishes "invoked" from "turn settled." Preserves the
  completion signal while making acceptance observable.

## Scope and constraints

- **No relay change.** The relay is clean in every repro; it forwards the
  app↔Pi traffic opaquely.
- **No wire/protocol change required for Problem A.** The fix is in the
  extension's record-mapping ordering (`index.ts` + `sdk_session_projection.ts`).
- **Cross-side observability is already in place** (delivery log + mobile ring
  log), so the fix can be verified against the same repro shape.
- **The `/new` lifecycle itself is not broken** — it converges in <1s. The
  stall is on the first message after replacement, not the replacement.
- **Do not conflate with the archived `session_history` replay class**
  (`story-mobile-double-messages-on-session-history-replay`, now archived
  under `.work/archive/`). That was a different, already-fixed mechanism.

## Evidence

- Primary repro capture: `debug/4c2-11f1-ae25-659bdda1075d.bin` (2026-07-21,
  full echo history across healthy + post-`/new` turns — the most documented).
- Earlier captures: `debug/4c0-11f1-ae25-659bdda1075d.bin`,
  `debug/486-11f1-ae25-659bdda1075d.bin`.
- Extension delivery log: `~/.pi/remote/debug/delivery.log`.
- Confirmed root cause + code citations:
  `story-mobile-stuck-message-after-new-session-replacement.md`.
- Parent: `feature-reconnect-reproduction.md`.
- Grandparent epic: `epic-targeting-and-session-lifecycle-contracts.md`.

## Out of scope

- The `session_history` replay eventId class (archived, fixed).
- The reconnect drop-test items (separate, environment-gated).
- Any change to the `/new` lifecycle itself (it converges cleanly).

## Design run note (2026-07-21)

This was a bounded direct-read design pass. The confirmed diagnosis supplied by
`story-mobile-stuck-message-after-new-session-replacement` was treated as an
input, not re-opened. Mapping covered the replacement binding, delivery
coordinator, transcript projection, debug-event registry, existing extension
regressions, and the app's existing echo-timer contract. No exploratory fan-out
was warranted because the remaining unknown was the explicit A-vs-B policy
choice, not codebase structure. Design-time advisory review was unavailable in
this delegated sub-agent context; per the risk-driven policy that is
non-blocking, and the later feature-level implementation review retains the
default `standard` weight.

No UI mockup is needed: this changes delivery ordering inside the extension and
adds no screen, component, or user journey. No relay work is included.

## Design decisions

- **Problem A — reserve the app message identity before waking:** compute the
  deterministic `user_confirmed` event id and enqueue the `(content → cli_ id,
  event id)` mapping before `_wakeAgent`; keep transcript confirmation,
  ingress-id recording, and the explicit `user_message` rebroadcast after a
  successful wake settlement. The current ordering awaits at
  `pi-extension/src/index.ts:2302-2334`, while the mapping is currently added
  inside the later confirmation at `pi-extension/src/index.ts:2344-2360`.
- **Failed attempts cancel only their unconsumed reservation:** make
  `rememberDeliveredUserEvent` return an identity-specific cancellation
  closure. The mapping store is a FIFO per content signature at
  `pi-extension/src/session/sdk_session_projection.ts:441-450`, and consumption
  removes its head at
  `pi-extension/src/session/sdk_session_projection.ts:963-972`; cancelling by
  entry identity preserves same-content concurrent messages and becomes a
  no-op if `message_end` already consumed the reservation.
- **Problem B — choose B1 for this feature:** retain the awaited settlement
  behavior and do not add another debug event. The app-facing acceptance signal
  is the matching `UserInput.id`, which cancels the 20-second send timer at
  `app/lib/data/sync/sync_service.dart:1019-1030`; Problem A makes that signal
  carry the original `cli_` id while the replacement Promise is still pending.
  `wake_outcome` and `msg_delivered` remain settlement telemetry emitted after
  the await at `pi-extension/src/index.ts:2302-2340`, not a uniform
  invocation-time contract.
- **Reject B2 (fire-and-forget):** the current boundary awaits Promise
  rejection and classifies stale replacement contexts as recoverable at
  `pi-extension/src/session/sdk_session_projection.ts:680-697`; the existing
  extension regression requires an asynchronously rejected replacement API not
  to emit the explicit success echo at
  `pi-extension/src/extension.test.ts:2149-2207`. Returning success before that
  rejection would weaken a verified failure guarantee.
- **Reject B3 (new invoked/accepted event):** the typed delivery-log variants
  are centrally registered at
  `pi-extension/src/session/delivery_debug_log.ts:27-56`. Adding a second wake
  milestone would expand that registry and require a new id-bearing callback or
  parameter through `SdkSessionProjectionPort.wakeAgent`, whose current
  contract mirrors the SDK arguments at
  `pi-extension/src/extension/ports.ts:126-140`, without changing any
  user-visible outcome. B1 is the shortest reversible fix; revisit B3 only if a
  real diagnostic consumer needs invocation latency independently of settlement
  latency.
- **No app, relay, wire, or `/new` lifecycle change:** the app already treats a
  matching `UserInput` id as confirmation at
  `app/lib/data/sync/sync_service.dart:1019-1030`; the replacement callback
  already rebinds the fresh SDK capabilities at
  `pi-extension/src/index.ts:1668-1680`. The change belongs solely to the
  extension's delivery/mapping order and its regressions.

## Architectural choice

Three approaches were considered:

1. **Pre-await identity reservation with settlement-gated confirmation
   (chosen).** Reserve only the mapping needed by the `message_end` projection,
   await the SDK exactly as today, cancel an unconsumed reservation on failure,
   and commit the remaining delivery confirmation after success. This fixes the
   observed echo identity/timing while preserving async stale/error detection.
2. **Normalize both bindings to fire-and-forget acceptance (B2).** Treat the
   call return as invocation success and observe any Promise rejection later.
   This makes timing uniform, but it cannot retract an already-reported success
   and conflicts with the async-rejection behavior pinned at
   `pi-extension/src/extension.test.ts:2149-2207`.
3. **Add separate invocation telemetry (B3).** Keep the await and add an
   id-correlated `wake_invoked`/`wake_accepted` milestone. This preserves
   failure handling, but it requires expanding the diagnostic registry at
   `pi-extension/src/session/delivery_debug_log.ts:27-56` and changing the
   wake port at `pi-extension/src/extension/ports.ts:126-140` merely to explain
   a known SDK return-type asymmetry.

The chosen approach follows code economy and lifecycle ownership: transcript
identity remains owned by `SdkSessionProjection`, delivery orchestration remains
in `index.ts`, and no new cross-surface contract is created. The installed SDK
makes the asymmetry explicit: `ReplacedSessionContext.sendUserMessage` returns
`Promise<void>` at
`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts:289-296`,
whereas factory `ExtensionAPI.sendUserMessage` returns `void` at the same file's
lines `893-905` (the pinned dependency is 0.80.6 at
`pi-extension/package.json:80-83`).

## Trickiest unit first: cancellable pre-await identity reservation

The reservation must exist before the replacement Promise settles, but it must
not become stale state when the SDK rejects before emitting `message_end`.
Content keys can legitimately have multiple FIFO entries, so cancellation must
remove the exact reserved object rather than `shift()` an arbitrary same-content
mapping. If `message_end` consumed it first, cancellation is a safe no-op. This
preserves the existing FIFO consumption at
`pi-extension/src/session/sdk_session_projection.ts:963-972` and the session
reset that clears all pending mappings at
`pi-extension/src/session/sdk_session_projection.ts:974-979`.

## Implementation Units

### Unit 1: Make the delivered-user mapping a cancellable reservation

**File**: `pi-extension/src/session/sdk_session_projection.ts`

```ts
rememberDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
  clientMessageId: string,
  eventId: string,
): () => void;
```

**Implementation Notes**:
- Preserve the current content-signature FIFO at
  `pi-extension/src/session/sdk_session_projection.ts:441-450`.
- Capture the exact inserted entry in the returned closure. On cancellation,
  remove that entry only if it is still present; delete the map key only when
  its queue becomes empty. This is intentionally identity-based so two
  same-text/image messages cannot cancel each other.
- Keep `consumeDeliveredUserEvent` as the single consumer at
  `pi-extension/src/session/sdk_session_projection.ts:963-972`; do not expose
  the map or introduce a second identity registry.
- Update the method's JSDoc because the returned rollback closure is a
  non-obvious lifecycle contract.

**Acceptance Criteria**:
- [ ] A remembered mapping is consumed as the original `clientMessageId` and
      `eventId`, not as `sync_<ts>`.
- [ ] Cancelling an unconsumed reservation removes only that reservation.
- [ ] Cancelling after consumption is a no-op, and equal-content sibling
      reservations retain FIFO order.
- [ ] Session reset still clears every unconsumed reservation.

---

### Unit 2: Reserve before await and commit only after successful settlement

**File**: `pi-extension/src/index.ts`

```ts
function _rememberDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
  clientMessageId: string,
  eventId: string,
): () => void;

async function _attemptUserDeliveryOnce(
  prepared: PreparedUserDelivery,
  attemptSessionId: string,
): Promise<WakeAgentResult>;

function _confirmUserDelivery(
  msg: UserClientMessage,
  shouldSteer: boolean,
  attemptSessionId: string,
  eventId: string,
): void;
```

**Implementation Notes**:
- Before `_wakeAgent`, derive
  `deterministicTranscriptEventId(attemptSessionId, "user_confirmed", msg.id)`
  and reserve the mapping. Today derivation and mapping both occur after the
  await at `pi-extension/src/index.ts:2334-2356`.
- On a returned failure or an unexpected thrown error, cancel the reservation
  before rolling back the seeded turn/propagating. On success, do not cancel;
  `message_end` either already consumed it or will consume it later.
- Pass the precomputed `eventId` into `_confirmUserDelivery`; remove its second
  `_rememberDeliveredUserEvent` call while retaining transcript append,
  session-scoped ingress idempotency, and the explicit all-owner echo at
  `pi-extension/src/index.ts:2344-2368`.
- Keep `_inflightUserDeliveries` coalescing unchanged at
  `pi-extension/src/index.ts:2278-2287`; it remains the guard against a second
  wake while the replacement Promise is pending.
- Do not move `wake_outcome` or `msg_delivered`; under B1 they intentionally
  remain after settlement at `pi-extension/src/index.ts:2316-2340`.

**Acceptance Criteria**:
- [ ] During a pending replacement-session Promise, a user-role `message_end`
      broadcasts `user_input.id === prepared.msg.id` with the SDK timestamp;
      it never falls back to `sync_<ts>` for that app-origin message.
- [ ] A factory `void` binding retains its current success path and explicit
      `user_message` rebroadcast.
- [ ] A stale/null/non-stale rejected wake retains its current recoverability,
      turn rollback, queue/error, and no-explicit-success-echo behavior.
- [ ] Duplicate ingress remains coalesced while pending and idempotently
      re-echoed after successful settlement.

---

### Unit 3: Pin replacement ordering and reservation cleanup

**Files**:
- `pi-extension/src/extension.test.ts`
- `pi-extension/src/session/sdk_session_projection.test.ts`

```ts
test(
  "post-session_new message_end preserves the cli id before the replacement turn settles",
  async () => { /* deferred Promise + captured message_end */ },
);

test(
  "delivered-user reservation cancellation preserves same-content FIFO mappings",
  () => { /* reserve, cancel/consume, assert ids */ },
);
```

**Implementation Notes**:
- Extend the existing app-driven replacement regression beside
  `pi-extension/src/extension.test.ts:1979-2054`: bind a fresh replacement API
  whose Promise is manually deferred, route the post-`session_new` app message,
  fire the registered user `message_end` before resolving the Promise, and
  assert the live `user_input` carries the original `cli_` id.
- Before resolving the deferred Promise, assert that the explicit
  `user_message` echo and `wake_outcome`/`msg_delivered` settlement records have
  not fired. That pins the B1 contract rather than accidentally implementing
  B2 or B3.
- After resolving, assert one successful confirmation path and no `sync_` id.
  The transcript log already dedupes repeated deterministic `eventId`s at
  `pi-extension/src/session/transcript_event_log.ts:10-18`.
- Add focused unit coverage for cancellation/FIFO behavior next to the existing
  ingress-idempotency and live-user identity tests at
  `pi-extension/src/session/sdk_session_projection.test.ts:428-470` and
  `pi-extension/src/session/sdk_session_projection.test.ts:531-565`.
- Do not add an app test: matching `UserInput.id` already disarms the timer at
  `app/lib/data/sync/sync_service.dart:1019-1030`, and existing app tests cover
  echo dedupe/timer cancellation at
  `app/test/data/sync/sync_service_test.dart:683-713` and
  `app/test/ui/chat/chat_viewmodel_test.dart:711-718`.

**Acceptance Criteria**:
- [ ] The regression fails on the current ordering because the pre-settlement
      `message_end` emits `sync_<ts>`.
- [ ] It passes after Units 1-2 with the original app id before Promise
      settlement.
- [ ] The existing async-rejection regression remains green.
- [ ] The focused tests use a deferred Promise/event hook, not wall-clock
      sleeps.

## Implementation Order

1. Implement Unit 1's identity-specific reservation cancellation and its
   focused FIFO/cleanup tests.
2. Implement Unit 2's pre-await reservation, failure cancellation, and
   post-settlement confirmation split.
3. Add Unit 3's deferred replacement regression, then run the focused tests.
4. Run `corepack pnpm typecheck`, `corepack pnpm test`, and
   `corepack pnpm build` from `pi-extension/` using the sandbox cache/store
   environment documented in `pi-extension/CLAUDE.md`.
5. Rebuild `dist/`, fully restart Pi (not `/reload`), and repeat the documented
   phone `/new` repro with `OUTPOST_PI_DEBUG_LOG=1`: the first echo must retain
   the sent `cli_` id and arrive before the 20-second app timeout; the later
   `wake_outcome` may still coincide with turn settlement under B1.

## Child story disposition

No child stories are spawned. Units 1-3 are one tightly coupled extension
change: the reservation API exists only to make the ordering safe, and the
deferred test is the acceptance evidence for that same change. Separate story
checkpoints would add dependency bookkeeping without enabling independent
acceptance or ownership.

## Simplification

- Move the existing mapping write instead of adding a second echo path, wire
  message, relay behavior, or app-side timeout exception.
- Reuse the deterministic event id and content-signature queue already owned by
  `SdkSessionProjection` at
  `pi-extension/src/session/sdk_session_projection.ts:124-125` and
  `pi-extension/src/session/sdk_session_projection.ts:441-450`.
- Remove the mapping write and event-id derivation from
  `_confirmUserDelivery`; pass the one precomputed id forward so delivery has
  one identity source.
- Retain both existing `user_input` and `user_message` confirmation frames:
  they serve the live deterministic transcript path and all-owner delivery
  acknowledgment respectively at
  `pi-extension/src/session/sdk_session_projection.ts:468-503` and
  `pi-extension/src/index.ts:2361-2368`. Suppressing either is a broader
  transcript/fan-out behavior change and is not required here.

## Testing

- **Regression boundary:** the extension-level `session_new → user_message →
  message_end-before-Promise-settlement` test protects the exact production
  ordering that caused the bug.
- **Complex-unit test:** reservation cancellation with equal content protects
  against stale mappings and wrong-message cancellation; this is the only new
  isolated logic.
- **Preserved failure contract:** keep the existing asynchronous replacement
  rejection test at `pi-extension/src/extension.test.ts:2149-2207` unchanged.
- **Existing app evidence:** app echo handling already proves same-id
  confirmation dedupes and disarms the timer at
  `app/test/data/sync/sync_service_test.dart:683-713`; no new Flutter test is
  justified for an extension-only ordering change.
- **No test removal:** no duplicate, tautological, or obsolete test was found
  in the touched surface.
- **Design-only pass:** no build or test command is run now because production
  code is intentionally unchanged in feature-design; implementation must run
  the commands in the order above.

## Risks

- **Riskiest assumption:** the SDK emits the persisted user `message_end` before
  a replacement context's Promise settles. The confirmed repro establishes
  that ordering, and the deferred regression makes it deterministic. If an SDK
  upgrade reverses it, the mapping still works; the early-echo timing benefit
  disappears and the regression will expose the contract change.
- **Stale reservation after failure:** recording before await can poison a
  later equal-content message if rejection happens before consumption.
  Identity-specific cancellation in Unit 1 is required, not optional.
- **Promise settles after `message_end` with failure:** the app may already have
  received a matching `user_input` because persistence proves the prompt
  entered the session, while later `wake_outcome` reports failure. Under B1
  those are deliberately different signals: acceptance vs. SDK settlement.
- **Session replacement during the pending attempt:** the mapping store is
  cleared by session reset at
  `pi-extension/src/session/sdk_session_projection.ts:974-979`, while the
  attempt retains its captured session id at
  `pi-extension/src/index.ts:2247-2254`; the cancellation closure must tolerate
  the reset as a no-op and must not remove a new session's entry.
- **Live verification can load stale code:** `dist/` is not rebuilt
  automatically, and `/reload` does not reliably re-import it. The smoke test
  requires a build plus full Pi process restart as documented in `AGENTS.md`.
- **Fallback:** if the full extension regression cannot deterministically drive
  the event order, retain the reservation unit tests and add a narrow test-only
  seam to the existing extension harness; do not weaken the assertion or use a
  sleep-based timing test.

## Implementation notes

- Execution capability: inline host implementation; the four-file extension change was cohesive and its integration points were explicit in the completed design, so implementation fan-out would have added handoff cost without independent ownership value.
- Review weight: standard (caller override); stop at `stage: review` for the orchestrator's fresh-context pass.
- Files changed: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/index.ts`, `pi-extension/src/session/sdk_session_projection.test.ts`, and `pi-extension/src/extension.test.ts`.
- Tests added/removed: added one deferred replacement-session integration regression covering `session_new → user_message → message_end` before turn settlement, plus four focused reservation tests covering identity-specific cancellation, cancel-after-consume, equal-content FIFO, and session-reset cleanup; removed none.
- Simplification: derived the deterministic delivery event id once before wake, passed it into confirmation, and removed the duplicate post-settlement derivation/mapping write; shared failed-attempt turn rollback inside the touched delivery function.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: the new integration regression failed before the production fix with `user_input.id === sync_1700001500000`, then passed after Units 1–2; `corepack pnpm typecheck` passed with zero errors, `corepack pnpm test` passed 884 tests with 3 skipped across 52 files, and `corepack pnpm build` completed successfully.

## Review (2026-07-21)

**Verdict**: Approve (standard weight, fresh-context independent pass)

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fresh-context reviewer independently confirmed the reservation lifecycle (identity-specific cancellation, cancel-after-consume no-op, session-reset tolerance, both failure paths cancel, success does not), confirmed `_confirmUserDelivery` no longer double-records, confirmed B1 preserved (`wake_outcome`/`msg_delivered` remain post-settlement), and independently re-ran the fail-before/pass-after test-integrity check by reverting the production files. Build/test green: 884 passed, 3 skipped. Scope confirmed extension-only (no app/relay/wire changes). The only unverified item is the live phone `/new` smoke test — that requires rebuilding `dist/` + a full Pi restart + a physical phone repro, which is the deploy/verify step, not the code-review step.

## Live verification (2026-07-22)

**Verified live on the operator's phone** after `dist/` rebuild + full Pi process restart.

Capture: `debug/591-11f1-9656-5799420aa9fe.bin`. Post-`/new` message
`cli_019f8864-1410-7435-bd02-4bb1106ebf5e` (room `DnDBxuh7KVyt`, new session
`e71cf5af`):

- First echo carried the **correct `cli_` id** at **+71ms** (vs. the pre-fix
  `sync_<ts>` wrong-id echo at +0.3s). **Zero `sync_` echoes** in the capture.
- **No `msgFailed send_timeout`** (pre-fix: false timeout at 20s).
- **No stuck message, no duplicate after the agent turn.**
- `wake_outcome`/`msg_delivered` landed at +10s (turn settlement) — B1 as
  designed; not user-visible-harmful.

Root-cause mechanism confirmed working in production: the `cli_`→message
mapping is now reserved before the awaited wake, so `message_end` finds it and
broadcasts the real `cli_` id immediately instead of the `sync_<ts>` fallback.

**Remaining (separate symptom, not this fix):** the operator still observes a
brief red "timeout" on pressing "New session" itself. This is NOT the
post-`/new` message bug fixed here — no `msgFailed` is logged for the `/new`
command, and the replacement converges in ~1s. It is an app-side UI affordance
on the `/new` command frame, a different symptom class. Parked story
`story-mobile-send-timeout-relay-room-main-mismatch.md` may be related; handle
separately.
