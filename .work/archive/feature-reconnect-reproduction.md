---
id: feature-reconnect-reproduction
kind: feature
stage: done
tags: [app, pi-extension, relay, bug, observability]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-19
---

# Reconnect reproduction & attribution (observation workstream)

## Brief

The 2026-07-02 live drop-test bug cluster is a set of **observation gaps, not
design gaps** — most bugs are explicitly unreproduced or have unconfirmed
contributors. The original epic framed these as "blocked on a reconnect
state-machine contract"; the reframed thesis is that they should **feed** the
contract from evidence, not be blocked-on or unblocked-by it. The
mobile-remote-coding skill lists the target states
(`connected idle / working / reconnecting / offline / stale-unknown`), but
those are the *target*; the contract should be updated **after** the trace
tells which state machine is actually wrong.

## Scope

For each item: reproduce with the cross-side instrumentation from
`feature-cross-side-observability` (phone ring log + relay logging +
correlation key), attribute the failure to a specific surface, then decide
whether it's app backoff / relay duplicate-connection cleanup / extension
peer-offline consumption / send queue / UI projection — or a genuine
contract gap.

Parent normalization (2026-07-18): `idea-mobile-drop-slow-recovery` and
`idea-mobile-outgoing-message-swallowed` moved here from the terminal
`feature-mobile-tui-parity-chat-resilience` because this feature already owns
their live-drop reproduction workstream; their parked scope is unchanged.

### Code-actionable items (terminal; no new live repro required)

- `idea-extension-pumps-into-dead-app-peer` →
  `story-extension-suspend-fanout-on-peer-offline`: **done in v0.1.0** at
  `.work/releases/v0.1.0/story-extension-suspend-fanout-on-peer-offline.md`.
  The relay's `peer_offline`/`peer_online` controls now suspend and resume the
  affected extension fan-out instead of pumping into the void.
- `idea-mobile-user-message-not-delivered-timeout` →
  `story-verify-resumed-session-echo-gate-rejection`: **static trace done in
  v0.1.0** at
  `.work/releases/v0.1.0/story-verify-resumed-session-echo-gate-rejection.md`.
  The trace proved the resumed-session race structurally possible. Its fix is
  also **done in v0.1.0** at
  `.work/releases/v0.1.0/story-fix-resumed-session-echo-gate-rejection.md`;
  matching pending-message echoes disarm the timeout without weakening
  session-scoped transcript acceptance.
- `idea-mobile-drop-half-open-tcp`: the observation story
  `story-relay-duplicate-auth-supersession-log` first confirmed that the relay
  did not eagerly close an old duplicate connection. The behavior follow-up
  already exists and is **done in v0.1.0** at
  `.work/releases/v0.1.0/story-relay-close-same-device-duplicate-auth.md`.
  Required per-install `device_id` distinguishes a reconnect from a genuine
  second device, and same-device duplicate auth closes prior connections.
  Therefore no duplicate child story is spawned by this design pass.

### Live-repro-only items (awaiting the next physical drop test)

These require a physical phone plus real wifi↔cellular/WireGuard transitions;
the dev VM cannot produce equivalent mobile process suspension, radio-path
changes, or half-open TCP timing. The existing instrumentation is sufficient,
so this is an **environment gate, not a design gate**. Do not fabricate a
reproduction or tune reconnect behavior from the 2026-07-02 anecdote.

- `idea-mobile-drop-slow-recovery` — the original ~5 minute recovery still
  needs a fresh live trace against the shipped eager same-device supersession
  and app half-open protections. Attribute app retry delay, transport-loss
  detection, relay auth/takeover, and external WireGuard/radio bring-up before
  changing backoff or heartbeat policy. The parked checkpoint remains
  `.work/active/stories/idea-mobile-drop-slow-recovery.md`.
- `idea-mobile-outgoing-message-swallowed` — the originally reported outgoing
  message remains unproven as server-side loss. On the next repro, join the
  app `msgSend.id`, relay `env_id_tail`, and extension delivery log's message
  `id` to determine whether the message stopped before relay ingress, at relay
  routing, at extension ingress/wake, or only at echo/UX confirmation. The
  parked checkpoint remains
  `.work/active/stories/idea-mobile-outgoing-message-swallowed.md`.

Two older active child checkpoints also have deployment/live-confirmation
work rather than open code design:
`story-mobile-send-timeout-relay-room-main-mismatch` and
`story-mobile-double-messages-on-session-history-replay`. Their source fixes
are recorded in their bodies; they remain honest deploy-and-observe checks and
are not redesigned or marked complete here.

## Why this is a feature, not a story

Each item needs its own reproduction pass and may surface a distinct root
cause (or confirm a shared one). The attribution is the work; the contract
follows. Grouping them keeps the workstream coherent and ensures the
observability dependency is explicit rather than re-derived per bug.

## Unblocks

- The reconnect portion of the contract gap audit
  (`feature-contract-gap-audit`) — once attributed, genuine invariant gaps
  get pinned; non-gaps get closed as code fixes via the design family.

## Out of scope

- The contract prose itself (`feature-contract-gap-audit`).
- The observability infrastructure (`feature-cross-side-observability`) —
  this feature consumes it.
- `idea-mobile-conflates-transport-and-agent-state` — misfiled under the old
  reconnect contract; its own analysis shows it's a UI-projection/turn-phase
  question, not a reconnect state machine. Routes under turn-state/UI
  projection work (consumes released `epic-bold-turn-state-machine`).

## Design run note (2026-07-18)

Delegated by the active autopilot `--all` run. This pass used direct repository
reads because the remaining design is bounded reconciliation of shipped work
plus an evidence-collection protocol; no exploratory fan-out was needed. The
effective review weight remains `standard` (caller default). A separate
design-time advisory pass was not available from this delegated sub-agent
context; Part IV makes that non-blocking, and the final implementation/review
path must still receive the caller's unchanged `standard` weight.

## Design decisions

- **Evidence-gated attribution, not speculative reconnect tuning:** keep the
  two unconfirmed observations parked until a real phone drop yields a joined
  cross-side trace. This is the least irreversible choice and preserves the
  observability-first parent strategy.
- **Advance the feature despite the environment gate:** `drafting →
  implementing` means the design is actionable; it does not claim the live
  observations were reproduced. The physical-phone constraint is recorded as
  remaining implementation evidence.
- **Do not spawn another eager-supersession story:** the proposed behavior
  follow-up already shipped as `story-relay-close-same-device-duplicate-auth`
  in v0.1.0 and `PROTOCOL.md` now describes that current contract. A duplicate
  story would manufacture work and risk reopening the solved multi-device
  discriminator decision.
- **One join key across surfaces:** use the existing message id, not timestamps
  or message previews, to attribute outgoing delivery. Timestamps establish
  latency; the id establishes identity.
- **No UI mockups:** this feature changes no screen or user journey. It consumes
  the existing debug-log/export affordance and transport diagnostics.

## Architectural choice

Three approaches were considered:

1. **Evidence-gated attribution (chosen).** Preserve the typed, privacy-safe
   diagnostic ports already shipped; execute a controlled live drop, join the
   three traces, and open a fix only for the surface proven responsible. This
   optimizes correctness and reversibility at the cost of waiting for the
   physical environment.
2. **Pre-emptive timeout/backoff tuning.** Shorten ping, retry, or send timers
   based on the five-minute anecdote. This is quick but conflates external
   radio/WireGuard delay with app and relay behavior, and can increase battery
   use or reconnect churn without fixing loss.
3. **A new cross-stack reconnect coordinator.** Centralize takeover and retry
   state. This is too broad: reachability already has a canonical contract,
   same-device relay supersession is shipped, and the remaining unknown is
   attribution rather than missing architecture.

The chosen design keeps each lifecycle owner intact: the app owns reconnect
and its persistent ring, the relay owns authenticated connection replacement
and structured transport logs, and the extension owns session ingress/wake
telemetry. Correlation joins evidence without adding a new runtime coordinator.

## Trickiest unit first: physical drop attribution

The hard part is distinguishing a true delivery loss from a delayed write,
relay takeover gap, extension delivery-pending window, or an echo/UI-only
failure. A single phone action must be correlated by id across all three
surfaces, with clocks used only for ordering. If any leg lacks the id, the
result is inconclusive and no behavior change follows.

## Implementation units

### Unit 1: Reconcile the already-shipped code-actionable paths

**Files/evidence**:
- `.work/releases/v0.1.0/story-extension-suspend-fanout-on-peer-offline.md`
- `.work/releases/v0.1.0/story-verify-resumed-session-echo-gate-rejection.md`
- `.work/releases/v0.1.0/story-fix-resumed-session-echo-gate-rejection.md`
- `.work/releases/v0.1.0/story-relay-close-same-device-duplicate-auth.md`
- `pi-extension/src/extension/owner_multiplexer.ts`
- `app/lib/data/sync/sync_service.dart`
- `relay/src/peers/connections.rs`

The current relay replacement boundary is:

```rust
pub(crate) fn insert(
    &self,
    peer_id: &str,
    room_id: &str,
    device_id: &str,
    tx: mpsc::Sender<Message>,
) -> ConnectionInsert;
```

**Acceptance criteria**:
- [x] Extension fan-out consumes peer reachability and skips an offline app
      peer without adding an unbounded replay queue.
- [x] A matching pending echo can disarm the app timeout while transcript
      mutation remains fail-closed by session identity.
- [x] Same-device duplicate auth closes the old connection while different
      `device_id`s coexist.
- [x] No new follow-up story duplicates terminal v0.1.0 work.

### Unit 2: Capture one controlled live network-transition trace

**Existing diagnostic contracts**:
- `app/lib/domain/contracts/debug_log.dart`
- `pi-extension/src/session/delivery_debug_log.ts`
- `relay/src/handlers/peer.rs`
- `relay/src/handlers/connection_actor.rs`

```dart
const ConnStatusEvent({
  required super.ts,
  required this.status,
  this.attempt,
  this.delayMs,
  this.peerTail,
  this.room,
}) : super(tag: DebugTag.connStatus);

const MsgSendEvent({
  required super.ts,
  required this.id,
  this.blocked,
}) : super(tag: DebugTag.msgSend);
```

```ts
export interface DeliveryDebugLog {
  log(event: DeliveryDebugEvent): void;
}
```

The existing `DeliveryDebugEvent` union variants used here are
`msg_received`, `wake_outcome`, and `msg_delivered`; their required shared
correlation field is `id`.

**Implementation notes**:
- Run with app debug capture/export enabled, relay persistent logs enabled, and
  `OUTPOST_PI_DEBUG_LOG=1` set before a full Pi process restart.
- Record a baseline online send, then one send at the controlled transition
  boundary, then one post-recovery send. Do not repeat aggressively enough to
  create ambiguous concurrent ids.
- Capture timestamps for `connStatus`, `connChannelLost`, relay
  `authenticated`/same-device close, and extension ingress/wake/delivery.
- Keep payloads out of relay/extension logs; only the operator-exported app
  preview may contain its already-bounded text field.

**Acceptance criteria**:
- [ ] A physical phone performs a real wifi↔cellular/WireGuard transition.
- [ ] The app export, relay file log, and extension delivery log cover the same
      time window and the test message id is recoverable on every leg it
      reached.
- [ ] Slow recovery is split into device loss detection, configured retry
      delays, relay authentication/takeover, and external network bring-up.
- [ ] The outgoing-message result is classified as accepted, delayed,
      rejected, or absent at each boundary; no conclusion is inferred from a
      missing timestamp alone.

### Unit 3: Attribute, close, or emit the proven fix

**Files**:
- `.work/active/stories/idea-mobile-drop-slow-recovery.md`
- `.work/active/stories/idea-mobile-outgoing-message-swallowed.md`
- the proven owning source/test boundary only (app, relay, or extension)

**Implementation notes**:
- Update the parked checkpoint with the trace and explicit epistemic result.
- If the shipped protections make the symptom disappear, record successful
  live verification; do not create a code story.
- If a concrete defect is proven, scope one focused fix under the owning
  surface with a regression test at its stable boundary. A genuine invariant
  gap feeds `feature-contract-gap-audit`; a local defect does not become
  contract prose merely because it occurred during reconnect.

**Acceptance criteria**:
- [ ] Every reproduced symptom has one evidence-backed disposition: fixed by
      shipped behavior, app defect, relay defect, extension defect, external
      network delay, or still inconclusive.
- [ ] Any new fix names the exact failed boundary and protects it with the
      smallest useful regression test.
- [ ] No unconfirmed claim is promoted into `PROTOCOL.md` or a state-machine
      contract.

## Implementation order

1. Treat the terminal v0.1.0 stories as satisfied prerequisites; do not reopen
   or duplicate them.
2. Deploy the current app/relay/extension artifacts and enable the existing
   diagnostics.
3. Run the physical-phone drop protocol and export all three traces.
4. Attribute by id and timestamps, then close the parked observations or scope
   only the proven fix.
5. Let `feature-contract-gap-audit` consume only verified invariant gaps.

## Child story disposition

- Done in v0.1.0:
  `story-extension-suspend-fanout-on-peer-offline` →
  `story-verify-resumed-session-echo-gate-rejection` →
  `story-fix-resumed-session-echo-gate-rejection` (the verify/fix dependency
  is preserved in their terminal bodies).
- Related behavior follow-up already done in v0.1.0:
  `story-relay-close-same-device-duplicate-auth` (`depends_on: []`, parented at
  the epic when it was scoped). No new child is needed.
- Awaiting physical environment, deliberately left at `stage: drafting`:
  `idea-mobile-drop-slow-recovery` and
  `idea-mobile-outgoing-message-swallowed` (`depends_on: []`).
- Existing deploy/live-confirmation leftovers, also not redesigned here:
  `story-mobile-send-timeout-relay-room-main-mismatch` and
  `story-mobile-double-messages-on-session-history-replay`.

## Simplification

- Removed the duplicated, contradictory live-repro list from this feature body.
- Reused the shipped typed diagnostic registries and message id; no new trace
  schema, retry queue, reconnect coordinator, or duplicate eager-close story.
- Retained the existing per-surface lifecycle owners rather than introducing a
  cross-stack abstraction for an unproven defect.

## Testing

- **No design-phase builds/tests:** this pass changes only the work item and
  intentionally avoids the memory-constrained repo's heavy suites.
- **Live interface evidence:** one baseline send and transition-boundary send
  protect the end-to-end delivery contract while the three logs identify the
  failed seam.
- **Regression testing after attribution:** run only the owning surface's
  focused test first; implementation verification later runs the documented
  subproject suite. Do not add tests to surfaces the trace exonerates.
- **No test removal:** no obsolete production test was identified by this
  design-only reconciliation.

## Risks

- **Riskiest assumption:** the operator can reproduce the transition while all
  three logs are enabled and clock skew is small enough for ordering. Fallback:
  identity still joins message flow; if a leg has no id, report the run as
  inconclusive and repeat rather than guessing.
- **Environment blocker:** the dev VM has no physical phone and cannot model
  radio switching, mobile OS suspension, or the real half-open path. Units 2–3
  await the next operator live drop test.
- **False confidence from shipped fixes:** eager relay supersession and app
  half-open guards may remove one contributor without proving the original
  five-minute delay's full cause. Re-run before tuning.
- **Observability privacy:** payload/body/`ct` fields must remain absent from
  relay and extension diagnostics; preserve the existing typed scrubbers.
- **Downstream audit contamination:** `feature-contract-gap-audit` must not
  convert an inconclusive trace into a durable contract claim.

## Implementation status (autopilot, 2026-07-19)

The code-actionable scope of this feature is **done in v0.1.0** (see "Code-actionable
items" above): the peer-offline fan-out suspension, the resumed-session echo-gate
fix, and the same-device duplicate-auth supersession are all shipped. The two
app-side stories (`story-mobile-double-messages-on-session-history-replay`,
`story-mobile-send-timeout-relay-room-main-mismatch`) have their source fixes
landed; their sole remaining acceptance criterion is `[ ] DEPLOY + VERIFY` —
rebuild extension `dist/`, restart pi, sideload an app APK to a physical phone,
and confirm via a fresh ring log.

The live-repro-only items (`idea-mobile-drop-slow-recovery`,
`idea-mobile-outgoing-message-swallowed`) require a physical phone plus real
wifi↔cellular/WireGuard transitions the dev VM cannot produce.

**This is an environment gate, not a design or implementation gap.** No work is
spawned against it in the current autopilot run; fabricating a reproduction or
tuning reconnect behavior from the 2026-07-02 anecdote would violate the
discipline this feature's own body prescribes. The feature remains at
`implementing` pending operator live-drop deploy+verify. When a phone is
available: rebuild + sideload, run the three-log capture, attribute the
remaining items, and advance per the acceptance criteria.

Downstream `feature-contract-gap-audit` (depends_on this feature) remains
blocked until this reaches `review`/`done`. That is the correct state — the
audit must consume reproduction evidence, not pre-write contracts from
unverified assumptions.

## Retirement (2026-07-28)

Closed. The observation workstream ran its course: the observability unlock
(feature-cross-side-observability, shipped v0.1.0) resolved 3 of 5 cluster
bugs and left 2 as unreproduced-with-instrumentation (no recurrence in 3+
weeks). The send-timeout story's original relay-drop mechanism was a misread
(directionality backwards; zero phone-originated drops); its real cousin
(the `_activeRoom` reorder) shipped independently 2026-07-08. Archived with
the parent epic.
