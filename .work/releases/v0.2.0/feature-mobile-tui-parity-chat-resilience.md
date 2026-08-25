---
id: feature-mobile-tui-parity-chat-resilience
kind: feature
stage: done
tags: [app, pi-extension, workflow, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-07-15
updated: 2026-07-20
reviewed: 2026-07-19 (standard, gpt-5.6-sol fresh-context → needs fixes; 3 materials fixed + verified → done; no second pass per standard weight)
---

# Mobile/TUI parity and lifecycle-resilient chat behavior

## Brief

Ten backlog items (one roadmap + nine ideas) describe the mobile chat
experience falling short of the pi TUI across status accuracy, message
ordering, and recovery. The structural parent finding
(`idea-mobile-conflates-transport-and-agent-state`) is that the mobile status
pill conflates transport/connection state with agent/turn state — fixing that
properly subsumes several of the status/steering symptoms. The cluster is the
mobile-UX half of `epic-remote-session-resilience-refactor`'s "make mobile UI
state robust" scope:

- `roadmap-mobile-parity-with-pi-tui` — roadmap: bring mobile to parity with the pi TUI
- `idea-mobile-conflates-transport-and-agent-state` — status pill conflates transport with agent/turn state (parent structural finding)
- `idea-mobile-no-stop-button-while-awaiting-tool` — agent doesn't show "working" / no Stop button while awaiting a tool result
- `idea-mobile-no-steering-indicator-when-queued` — no "steering/queued" indicator when sending while agent is working
- `idea-mobile-queued-message-does-not-reorder` — steered message threads in place; doesn't reorder to bottom when picked up
- `idea-mobile-chat-reorder-on-return` — returning to chat sometimes reorders the latest user message below the assistant response
- `idea-mobile-chat-blank-on-tab-return` — chat renders blank on tab return; needs back-out + re-enter to rehydrate
- `idea-mobile-drop-slow-recovery` — network drop: slow end-to-end recovery (~5 min)
- `idea-mobile-outgoing-message-swallowed` — outgoing message not delivered and not surfaced
- `idea-mobile-message-duplication-send-timeout` — message duplication + send_timeout confirmation bug

## Simplification opportunity

Resolve the transport-vs-agent-state conflation as the structural fix. The
current code has already moved the Stop gate to broad whole-turn `working` and
already carries `AppTurnStatus`, tool events, and queued text, but `ChatReady`
and the AppBar still flatten those facts into `isWorking`/`isOffline` booleans
and a `working > reconnecting > online > offline` priority label. Reuse the
existing algebraic turn projection rather than creating another phase enum.

The ordering, blank, and send-confirmation findings remain individual
repro-then-fix checkpoints. Existing deterministic live/replay identity and the
just-shipped startup/generation-guard work may already have removed some of
those symptoms; the checkpoint closes on a regression test if no further source
change is necessary. The two real-network findings remain attribution work, not
implementation guesses.

## Design

### Design decisions

1. **Replace flattened Chat booleans with one composed presentation model.**
   `ChatReady` will carry a `ChatStatusProjection`, not independent
   `isWorking`, `isOffline`, `peerPresence`, and `queuedText` status facts.
   The composition has three typed parts:

   ```dart
   final class ChatStatusProjection {
     const ChatStatusProjection({
       required this.transport,
       required this.turn,
       required this.steering,
     });

     final ChatTransportProjection transport;
     final AppTurnProjection turn;
     final SteeringProjection steering;
   }

   sealed class ChatTransportProjection { const ChatTransportProjection(); }
   final class ChatTransportOnline extends ChatTransportProjection { /* room */ }
   final class ChatTransportRetrying extends ChatTransportProjection { /* attempt/delay */ }
   final class ChatTransportOffline extends ChatTransportProjection { /* reason */ }

   sealed class SteeringProjection { const SteeringProjection(); }
   final class NoSteering extends SteeringProjection {}
   final class SteeringPending extends SteeringProjection {
     final String clientMessageId;
     final String text;
   }
   ```

   `AppTurnStatus`/`AppTurnProjection` remain the single source of truth for
   `idle`, `working`, `awaitingTool`, `streaming`, `done`, `error`, and
   `stale`; no `AgentTurnPhase` mirror is added. One exhaustive ViewModel mapper
   derives transport from `ConnectionStatus` plus active-room reachability:
   `StatusOnline` with a live room → online; `StatusConnecting` or
   `StatusRetrying` → retrying; `StatusNoPeer`, `StatusOffline`, or an online
   relay whose selected Pi room is not live → offline. Transport loss marks
   turn knowledge stale/non-cancellable rather than claiming that reconnecting
   is an agent phase. The AppBar renders transport
   dot/label and agent phase independently; the composer derives Stop from
   `status.turn.working` and the steering preview from `status.steering`.

   This is deliberately more than adding booleans: display, Stop eligibility,
   and steering presentation all consume the same composed projection, and the
   old priority chain is deleted.

2. **The structural unit subsumes the status/control symptoms, not transcript
   ordering.** `idea-mobile-conflates-transport-and-agent-state`,
   `idea-mobile-no-stop-button-while-awaiting-tool`, and
   `idea-mobile-no-steering-indicator-when-queued` close as provenance when the
   composed-projection tests are green. The Stop gate is already broad in
   current source; the unit preserves that behavior and adds the missing
   `awaitingTool` label plus an explicit steering state. No production
   pi-extension change is expected: existing `tool_request`/`tool_result`,
   `user_input(streaming_behavior: steer)`, deterministic timestamped
   `user_input`, `queued_message_state`, and room snapshots are the inputs.

   `idea-mobile-queued-message-does-not-reorder` is **not** claimed as
   structurally fixed. The status split makes its pending→picked-up lifecycle
   visible, but moving a transcript row is a separate semantic-ordering defect.
   Treating it as provenance would leave the current append-order behavior
   untouched.

3. **Four findings are distinct repro-then-fix bugs.** They are:
   - `idea-mobile-queued-message-does-not-reorder` — an early steer acceptance
     is projected as a transcript row at receipt time; the projection has no
     canonical pickup anchor.
   - `idea-mobile-chat-reorder-on-return` — persisted append `seq` records
     arrival order across optimistic/live/replay paths, not necessarily the
     prompt→response relationship exposed on rehydrate.
   - `idea-mobile-chat-blank-on-tab-return` — the retained route can resume
     without a new initial store emission/rebind even though re-entering creates
     a fresh ViewModel and repopulates it.
   - `idea-mobile-message-duplication-send-timeout` — optimistic submission,
     authoritative echo, and the pending timer can be observed through different
     route lifetimes; deterministic identity/SyncService ownership may already
     fix it, but only the send→back→re-enter regression can prove that.

4. **Two findings park as live-repro-only.** `idea-mobile-drop-slow-recovery`
   and `idea-mobile-outgoing-message-swallowed` stay at `stage: drafting` and
   route to `feature-reconnect-reproduction` on the next physical
   wifi↔cellular/WireGuard drop test. Cross-side observability is already the
   correct evidence path. This feature must not tune backoff or add retry/queue
   semantics from the 2026-07-02 anecdote alone. Whichever feature records the
   next attributed trace owns the resulting fix; the other closes its copy as
   provenance.

5. **`roadmap-mobile-parity-with-pi-tui` is an umbrella, not another
   implementation unit.** Its actionable status, steering, ordering, hydration,
   and confirmation slices are represented below. It closes as provenance when
   the implementation units complete; broader future TUI parity must be scoped
   from a new concrete observation rather than keeping this umbrella open.

### Architectural choice

Three shapes were considered:

1. Add more booleans and extend the AppBar priority chain. Small diff, but it
   preserves the defect: every new phase competes with transport in one ordered
   list.
2. Add one large UI enum containing every transport×turn×queue combination.
   Exhaustive, but the cross product grows immediately and duplicates
   `AppTurnStatus`.
3. Compose independent typed projections and derive controls/display from them.
   This reuses the shipped turn algebra, keeps transport authoritative in
   `ConnectionManager`, and represents steering as an overlay rather than a
   fake turn phase.

**Choice: option 3.** It is the shortest structural model that can display
`retrying + idle`, `online + awaiting tool`, or `online + streaming + steering
pending` without inventing cross-product states.

### Implementation units

#### Unit 1: Composed transport, turn, and steering presentation

**Story:** `feature-mobile-tui-parity-chat-resilience-status-projection`

**Files:**

- `app/lib/domain/session_state.dart`
- `app/lib/domain/transcript/transcript_projection.dart`
- `app/lib/ui/chat/states/chat_state.dart`
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/lib/ui/chat/chat_page.dart`
- `app/lib/ui/chat/widgets/input_bar.dart`
- `app/test/domain/transcript/transcript_projection_test.dart`
- `app/test/ui/chat/chat_viewmodel_test.dart`
- `app/test/ui/chat/chat_page_test.dart` (new if no stable page-level home exists)
- `app/test/ui/chat/input_bar_test.dart`
- `pi-extension/src/session/turn_state.test.ts`
- `pi-extension/src/extension.test.ts`

**What it does:** introduces `ChatStatusProjection`, centralizes the exhaustive
transport mapper, retains `AppTurnProjection` as the agent-phase authority, and
removes the AppBar priority chain and `ChatReady.isWorking`. It renders transport
and agent labels side by side, shows `waiting` for `awaitingTool`, keeps Stop for
every active phase, and exposes pending steering independently. Extension tests
pin the existing tool and steer/pickup signals; production extension code changes
only if those tests disprove the assumed contract.

**Acceptance criteria:**

- [ ] `retrying + idle`, `retrying + stale`, `online + working`, `online +
      awaitingTool`, `online + streaming`, and `online + error` remain
      representable without priority loss.
- [ ] AppBar displays transport and agent phase independently; idle transport
      transitions cannot masquerade as turn transitions.
- [ ] Stop is available for `working`, `awaitingTool`, and `streaming`, and is
      absent for idle/error/stale or when no cancel target exists.
- [ ] A steer accepted during an active turn produces one pending steering
      indicator without replacing the active turn phase.
- [ ] No second agent-phase enum or handwritten phase label switch exists
      outside the central presentation mapper.
- [ ] No app↔extension wire change is introduced unless the extension contract
      test proves there is no stable pickup signal; that failure stops this unit
      for redesign rather than adding a timing heuristic.

#### Unit 2: Steering pickup anchoring and logical placement

**Story:** `idea-mobile-queued-message-does-not-reorder`

**Files:**

- `app/lib/domain/transcript/transcript_event.dart`
- `app/lib/domain/transcript/transcript_projection.dart`
- `app/lib/data/local/records/transcript_event_record.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/domain/transcript/transcript_projection_test.dart`
- `app/test/data/sync/sync_service_test.dart`
- `pi-extension/src/extension.test.ts`

**What it does:** distinguishes delivery acceptance from semantic pickup for a
steered message using additive metadata on the existing user transcript events
(defaulting old records to canonical/confirmed). The early steer echo resolves
delivery and drives `SteeringPending` but does not anchor a transcript bubble.
The deterministic timestamped user-input/message-end event is the pickup anchor;
it inserts the prompt once after the prior response and clears the steering
indicator. Session replay uses the same identity and placement. Do not mutate
Hive sequence numbers or add a view-only sort override.

**Acceptance criteria:**

- [ ] A steered message is visibly pending after acceptance but does not split
      the previous assistant response in the transcript.
- [ ] Pickup materializes exactly one user bubble after the previous response
      and clears the pending indicator.
- [ ] Duplicate early echoes, duplicate pickup events, and session replay remain
      idempotent by stable message/event identity.
- [ ] Cancel, failure, disconnect, and session replacement converge pending
      steering to an explicit terminal or stale state; none leave a permanent
      indicator.
- [ ] Old transcript records lacking the additive pickup metadata still parse
      and retain their current order.

#### Unit 3: Stable prompt/response order after rehydrate

**Story:** `idea-mobile-chat-reorder-on-return`

**Files:**

- `app/lib/domain/transcript/transcript_projection.dart`
- `app/lib/data/local/transcript_event_store_hive.dart`
- `app/lib/data/sync/session_history_replay.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/domain/transcript/transcript_projection_test.dart`
- `app/test/data/sync/session_history_replay_test.dart`
- `app/test/data/sync/sync_service_test.dart`

**What it does:** first pins the reported leave/re-enter inversion with
controlled optimistic, early-echo, assistant, and replay event order. If it
still reproduces, the pure transcript projection derives one semantic order
from stable message identity and `replyTo`/pickup relationships; raw append
`seq` remains the event-log replay order, not the UI's prompt/response contract.
A global wall-clock sort and in-place stored-seq rewrites are rejected because
they create new cross-device/tie races. If the current deterministic identity
work already passes the regression, this unit closes with that evidence and no
source change.

**Acceptance criteria:**

- [ ] A prompt always precedes assistant messages that reference it before and
      after leave/re-enter.
- [ ] Live projection, cold read, and repeated `session_history` replay yield
      the same message IDs and order.
- [ ] Tool rows and multi-segment assistant output keep their existing relative
      order.
- [ ] No duplicate row or stale transcript tail is introduced to repair order.

#### Unit 4: Active-chat resume rehydration

**Story:** `idea-mobile-chat-blank-on-tab-return`

**Files:**

- `app/lib/ui/chat/chat_page.dart`
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/lib/data/repositories/session_read_repository.dart` (only if its watch
  contract fails to replay the current snapshot)
- `app/test/ui/chat/chat_viewmodel_test.dart`
- `app/test/ui/chat/chat_page_test.dart` (new if needed)

**What it does:** reproduces background→resume while the same chat route stays
mounted. If the retained subscription does not republish, the route owns a
lifecycle listener and calls an idempotent ViewModel resume refresh that reloads
the active session from the local read repository and requests authoritative
sync. The method reuses the shipped generation/serialization guards; it does not
reach into a disposed ViewModel through an app-global `BuildContext`. If the new
bootstrap ownership already prevents blanking, close on the regression evidence.

**Acceptance criteria:**

- [ ] A populated chat remains populated, or repopulates from local storage,
      after pause/resume without back navigation.
- [ ] Resume may request authoritative sync but never clears visible history
      while waiting for network.
- [ ] Repeated resume events install no duplicate subscriptions and duplicate no
      rows.
- [ ] Dispose or session switch during refresh prevents every stale emission.

#### Unit 5: Navigation-safe send confirmation and dedupe

**Story:** `idea-mobile-message-duplication-send-timeout`

**Files:**

- `app/lib/data/sync/sync_service.dart`
- `app/lib/domain/transcript/transcript_projection.dart`
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/test/data/sync/sync_service_test.dart`
- `app/test/ui/chat/chat_viewmodel_test.dart`
- `pi-extension/src/extension.test.ts` (only if ACK/echo correlation is shown
  to be wrong)

**What it does:** turns the operator's exact send→back while pending→re-enter
sequence into a deterministic regression. The process-owned `SyncService`, not
the route, remains owner of pending timers and confirmation. Optimistic,
delivery-accepted, canonical-pickup, late-confirmation, and replay events
project one message ID; timeout only changes the existing unconfirmed message's
status and a later confirmation wins. Current deterministic identity and
lifecycle work may satisfy the test without another production fix.

**Acceptance criteria:**

- [ ] Leaving and re-entering during a pending send shows one bubble with one
      stable ID.
- [ ] A real echo resolves sending state even when the original route was
      disposed; its timer cannot later emit a false `send_timeout`.
- [ ] A real timeout marks that bubble failed once and never reinserts it.
- [ ] Late confirmation or replay converges failed/pending to one confirmed row
      and the true latest exchange remains the transcript tail.
- [ ] Extension changes are limited to a proven ID/echo contract defect; no new
      ACK family is added speculatively.

### Implementation order

1. `feature-mobile-tui-parity-chat-resilience-status-projection`
2. `idea-mobile-queued-message-does-not-reorder`
3. `idea-mobile-chat-reorder-on-return`
4. `idea-mobile-chat-blank-on-tab-return` (semantically independent after Unit
   1; may proceed beside Unit 3 if one feature owner controls shared files)
5. `idea-mobile-message-duplication-send-timeout` after both ordering and
   hydration evidence are green
6. Close the three structural symptom stories and roadmap umbrella as
   provenance; leave the two live-drop stories drafting

The declared DAG is:

- status projection: `depends_on: []`
- queued pickup order: `depends_on: [status projection]`
- return order: `depends_on: [queued pickup order]`
- blank-on-resume: `depends_on: [status projection]`
- duplication/timeout: `depends_on: [return order, blank-on-resume]`

### Testing

Use the smallest surfaces that prove the contracts:

- **Pure projection table:** one table-driven test over transport × turn proves
  the two axes do not flatten each other; focused cases cover awaiting-tool Stop
  and pending steering. Do not snapshot every color/copy variant.
- **Steer lifecycle reducer:** accepted→pending→picked-up and
  accepted→disconnect/session-replace paths, including duplicate/replay events.
- **Ordering regression:** construct the adverse event arrival order directly,
  materialize, dispose/reload from Hive, replay the same history, and compare IDs
  and order.
- **Resume regression:** a fake lifecycle edge and controlled repository stream
  prove retained-route hydration and disposal guards without real sleeps.
- **Send regression:** fake channel + controlled echo/timer proves
  send→back→re-enter, real confirmation, timeout, and late confirmation.
- **Extension contract tests:** only the existing tool phase, early steer echo,
  canonical timestamped pickup, and stable ID behavior needed by the app. No
  full cross-component end-to-end harness is added.

Run focused tests during each unit, then from `app/` run `flutter analyze` and
`flutter test --concurrency=1`; from `pi-extension/` run `corepack pnpm
typecheck` and the targeted Vitest files when extension tests/source changed.
Use the serial Flutter run because the current suite has documented legacy
scheduler sensitivity.

### Simplification

- Delete the AppBar's `working > reconnecting > online > offline` priority
  chain and remove duplicated `ChatReady.isWorking`/status booleans as the
  composed model lands.
- Reuse `AppTurnStatus`; do not introduce a mobile-only phase enum or enrich
  `room_meta` with a parallel phase field.
- Keep semantic ordering in the pure transcript projection; do not mutate
  append-only event order or add a second view-only list sorter.
- Reuse the shipped generation guards and per-session read streams; do not add a
  global lifecycle singleton for one route.

### Mockups

No mockup is required. This is a minor composition of the existing AppBar dot,
status text, Stop affordance, and queued preview—not a new screen, journey,
palette, or shared component. The pi TUI remains the interaction reference.

### Risks

- **Riskiest assumption:** the existing two-stage steer evidence is stable: an
  early `user_input(streaming_behavior: steer)` proves delivery acceptance and
  the later deterministic timestamped `user_input` proves semantic pickup. If a
  real Pi run does not emit the latter for steered input, Unit 2 must stop and
  design an explicit generated-protocol pickup event; timing-based inference is
  not acceptable.
- **Second risk:** changing semantic projection order can disturb tool/multi-
  segment assistant ordering or old records. The failure condition is any
  difference between live, cold-read, and replay order for the same stable IDs.
  Keep the change in the pure reducer and preserve append order as fallback.

### Rollback

The structural change is app-internal and additive at the transcript-record
edge; no relay route, auth, or required wire field changes. Revert the composed
projection and restore the old AppBar mapper as one app commit if necessary.
Pickup metadata must be optional with backward-compatible defaults, so an older
app can ignore it and still read the event log (it may regain the old ordering
bug, but not lose data). Distinct bug units can be reverted independently in
reverse dependency order. Any unexpected required wire change is a separate
paired app/extension rollback boundary and must update `PROTOCOL.md`; none is
planned here.

## Implementation

Completed all five implementation units and closed the three structural symptom
items plus the roadmap umbrella as provenance. The app now carries one composed
chat status with typed transport, the existing turn algebra, and steering;
transport loss cannot masquerade as an agent phase, awaiting-tool remains
cancellable, and steering is a separate overlay.

Steered sends now distinguish early delivery acceptance from deterministic
semantic pickup using backward-compatible transcript metadata. Pending steering
does not split the previous response; timestamped pickup anchors one prompt row
and replay remains idempotent. The pure transcript projection additionally
enforces the stable `replyTo` prompt-before-response relationship without
rewriting append sequence. Retained chat routes refresh their local canonical
projection on resume under generation/session guards, and regression evidence
confirms process-owned send confirmation survives route disposal/re-entry. A
correlated steer rejection now immediately clears pending steering and marks the
existing submission failed.

### Verification

- `flutter analyze lib test` — passed with zero issues.
- `flutter test --concurrency=1` — passed, 748 tests.
- Targeted transcript/store/history/SyncService/ChatViewModel/AppBar/InputBar
  suites — passed serially throughout implementation.
- `corepack pnpm typecheck` in `pi-extension/` — passed.
- Targeted `src/extension.test.ts` active-steering contract — passed and proves
  early steer echo followed by timestamped same-ID pickup.
- Full `src/extension.test.ts` ran 192/193 green; the sole unrelated existing
  cwd-lock test failed acquiring its first lock in the shared environment.
- `flutter build apk --debug` was attempted twice. Dependency/Gradle setup
  progressed after redirecting `GRADLE_USER_HOME`, but Android asset compression
  failed because the documented `/home/agent/.gradle-tmp` is read-only in this
  sandbox. No build artifact is committed.

`idea-mobile-drop-slow-recovery` and
`idea-mobile-outgoing-message-swallowed` remain at `stage: drafting` with their
live-repro `## Parked` notes, as designed.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor`. 10 `roadmap-mobile-*` / `idea-mobile-*`
items captured during the 2026-07 mobile testing window.

## Review findings (fresh-context review, gpt-5.6-sol, standard weight)

Review verdict: `needs fixes`. Three material findings (all verified by the
orchestrator against current code). These must be fixed before this feature
closes.

### Material 1 — Awaiting-tool state is lost in the real SDK event order
`app/lib/domain/transcript/transcript_projection.dart:235-259`.
`AssistantMessageCommitted` sets the turn idle before `ToolRequested`. The
extension emits `agent_message(ts)` before `tool_execution_start`, so the common
sequence `UserInput → AgentMessage → ToolRequest` leaves `streaming == null`
and `turn.working == false`; the tool request cannot transition to `awaitingTool`.
The UI then lacks the `waiting…` state and cancel target.
**Fix:** preserve/recover the active reply anchor through assistant commits until
`AgentDone`, or let `ToolRequested` derive it from the preceding assistant reply.
Add the exact production-order regression and assert `awaitingTool`, `canCancel`,
and the original cancel target.

### Material 2 — A rejected steer incorrectly terminates the primary turn
`app/lib/data/sync/sync_service.dart:1230-1245`.
A correlated steering rejection correctly schedules `_failPendingSend`, but then
unconditionally calls `_discardStreamingState()` and `_setTurnIdle()`. The
extension rolls back only the steer and preserves the prior active turn, so the
app incorrectly drops its primary streaming state and Stop target. The new test
at `app/test/data/sync/sync_service_test.dart:797` does not assert preservation
of that turn.
**Fix:** distinguish a pending-steer rejection from a primary-turn error. Clear/fail
only the steering overlay while retaining the previous turn, streaming buffer,
and cancel target; add corresponding assertions.

### Material 3 — Pending steering does not converge on cancel or failed persistence
`app/lib/data/sync/sync_service.dart:1161-1187`, `app/lib/data/sync/sync_service.dart:535-549`.
`Cancelled` records failure only for the active turn's `targetId`; any separate
`SteeringPending.clientMessageId` remains pending in the event log and is
re-projected indefinitely. Additionally, `_failPendingSend` clears steering only
indirectly through successful persistence; its persistence-independent `finally`
convergence does not clear the matching steering overlay.
**Fix:** terminalize the pending steering ID when cancellation clears the Pi
steering queue, and clear matching in-memory steering under the existing lifecycle
check even if failure persistence throws. Add accepted→cancel and failed-append
regressions.

### Review invariant summary
- Transport/turn independence: PASS structurally
- Three subsumed symptoms closed: FAIL (awaiting-tool lost in real order — material 1)
- Four distinct bugs fixed: FAIL overall (Unit 2's cancel/failure convergence incomplete — materials 2+3)
- Async-gap-before-mutation guards: PASS
- Terminal turn convergence independent of persistence: PASS for turn state (steering convergence is the separate finding)
- No BuildContext-after-await-without-mounted: PASS
- Parked items left drafting: PASS
- Extension change is test-only: PASS
- Test-integrity: no tests weakened/gamed; the awaiting-tool test omits the known production order, the steering-rejection test omits primary-turn preservation, no accepted-steer→cancel convergence test exists — these gaps allowed the material findings.

## Corrective follow-up

All three material review findings were corrected without changing the wire or
advancing the feature from `stage: review`.

1. The transcript reducer now retains an active reply anchor across a committed
   assistant message until a terminal event. The exact production order
   `UserInput → AgentMessage → ToolRequest` now projects `awaitingTool`, remains
   cancellable, and keeps the original user-message cancel target.
2. A correlated pending-steer rejection now fails and clears only that steering
   overlay. The primary turn, streaming buffer, and Stop target remain active;
   steering failures also preserve that turn when the event log is rebuilt.
3. Cancellation now writes a terminal failure for a separate pending steering
   ID, and both cancellation and `_failPendingSend` clear the matching in-memory
   overlay under lifecycle guards even when transcript persistence fails.

Corrective commits:

- `5f94426` — material 1 reply-anchor recovery.
- `0e79a2e` — materials 2–3 steering rejection/cancellation convergence.

Verification from `app/`:

- `flutter test test/domain/transcript/transcript_projection_test.dart test/data/sync/sync_service_test.dart --concurrency=1` — passed, 108 tests.
- `flutter analyze lib test` — passed with zero issues.
- `flutter test --concurrency=1` — passed, 751 tests.
