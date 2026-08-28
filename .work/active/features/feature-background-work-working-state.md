---
id: feature-background-work-working-state
kind: feature
stage: done
tags: [pi-extension, app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Background work should hold the working state — not a bare "online" bubble

## Brief

While the agent waits on background tools/subagents (e.g. an e2e battery
worker), the app shows only the single "online" bubble. The sole cue that
we're waiting is the agent's own prose ("I'll report when it lands") —
fragile, purely conventional, and invisible if the narration is missed.
The working projection must reflect harness-side background work, so the
operator can trust the status surface instead of agent narration.

Field report (operator, 2026-08-27, during the v0.10.1 release e2e
battery): the orchestrator agent waited on a long-running background
worker; the app showed a bare online bubble throughout.

## Root shape

The `working` projection derives from the SDK turn lifecycle: turn ends →
agent_settled → working=false. Background agents (pi-subagents tasks) run
harness-side beyond any turn — the room/app has no signal that
orchestrator work continues.

Related: `story-offline-state-liveness-ux` (same surface, opposite
failure — dead-looking when alive vs alive-looking when idle). Deliberately
independent: neither assumes the other's output, but design should keep
the two status-surface changes coherent.

## Investigation result (2026-08-27, explorer pass)

The pi-subagents package (`@gotgenes/pi-subagents` v19.3.5, loaded from
`~/.pi/agent/npm/node_modules/`) emits lifecycle events on the shared
`pi.events` bus — the same bus the extension already subscribes to for
`subagents:child:*` in `runtime_coordinator.ts`:

- `subagents:created` — background records only, emitted before
  concurrency admission (includes queued). Payload `{ id, type,
  description, isBackground: true }`.
- `subagents:completed` / `subagents:failed` — terminal states, payload
  includes `{ id, status, ... }`.
- `subagents:resumed` — terminal state of a resumed run, same shape.

Payloads arrive as `unknown` (EventBus is `emit(channel, data: unknown)`)
and must be structurally narrowed, never blindly cast. `subagents:child:
disposed` is NOT a completion signal (sessions are retained for resume).
The package also exports an in-process query service
(`getSubagentsService().listAgents()`), but importing it would require
dependency wiring to a package that resolves from `~/.pi/agent/npm/`, not
the extension's own node_modules — the event bus avoids that coupling.

The package's in-memory registry is cleared of completed records on
session start/switch; there is no durable live-task state to poll.

## Architectural choice

**Event-bus tracker in the extension + additive `RoomMeta.background` +
a fourth status axis in the app.** The tracker keeps a `Set<string>` of
live background agent ids from `subagents:created`/`completed`/`failed`/
`resumed`, publishes `background: boolean` on 0↔n transitions through the
existing `room_meta_update` path, and the app renders a distinct
"orchestrating…" status chip.

Alternatives rejected:

- **OR into the existing `working` boolean extension-side** — minimal app
  change, but collapses turn-work and background-work into one bit. The
  field report is explicitly about the operator reading these as
  different situations, and the app's `ChatStatusProjection` architecture
  composes transport/turn/steering without flattening axes; ORing at the
  extension would fight both.
- **Direct `getSubagentsService()` import + polling** — authoritative,
  but requires package-resolution wiring into `~/.pi/agent/npm/`
  (fragile across installs) for a signal the event bus already carries.

Tradeoff accepted: an event-sourced set can drift if the extension
re-subscribes mid-flight (hot reload). That window is closed by the
restart-gate hardening below; a manual pi restart kills the tasks anyway,
which is self-consistent.

## Design decisions

- **Three states, not two**: idle / working (turn) / orchestrating
  (background) — the operator explicitly reads these as different
  situations; the wire keeps the axes separate so the app chooses the
  rendering.
- **Wire shape**: additive optional `background?: boolean` on `RoomMeta`
  — backward-compatible (old apps ignore the key; the Rust relay treats
  meta as opaque and is untouched; the app's preserve convention treats
  absence as "no change").
- **Signal source**: `pi.events` channels with structural narrowing; no
  direct package import.
- **Restart gate consults the tracker**: `_maybeRestartForExtensionReload`
  fires on `agent_settled`, which ignores background tasks — today an
  armed hot reload can kill a running background worker. The gate now
  defers while the set is non-empty, and a drain-to-zero transition
  re-attempts it (armed requests carry a 5-min TTL and are never consumed
  by a deferral, so nothing is lost if background outlives the window).
- **Background does not gate the composer or add a cancel affordance**:
  the operator can keep messaging during background work (same as idle
  today); `isWorking`/Stop stay turn-scoped. v1 shows state only.
- **Label/iconography**: `orchestrating…` chip reusing `colors.working` —
  no new palette entries (design-system tokens contract). Turn status
  takes precedence when both are active; the background chip shows when
  the turn is idle/done/stale.
- **Session replacement clears the set** — matches the package clearing
  completed records on session start/switch; late terminal events for
  absent ids are no-ops.

## Implementation Units

### Unit 1: BackgroundActivityTracker
**File**: `pi-extension/src/extension/background_activity.ts`
**Story**: `story-background-work-ext-tracker`

```ts
import type { EventBus } from "./ports"; // same type runtime_coordinator uses

export interface BackgroundActivitySnapshot {
  readonly activeCount: number;
}

/** Tracks live background subagents via pi.events lifecycle channels. */
export class BackgroundActivityTracker {
  constructor(onChange: (snapshot: BackgroundActivitySnapshot) => void);
  /** Idempotent per bus identity (mirror observeChildLifecycle's guard). */
  subscribe(bus: EventBus): void;
  /** Session replacement/reset: drop all tracked ids, emit if non-empty. */
  clearForSessionBoundary(): void;
  get activeCount(): number;
  dispose(): void;
}
```

**Implementation Notes**:
- `subagents:created` → add `id` (background-only channel per package
  semantics; still require `typeof id === "string"`). `subagents:
  completed` | `failed` | `resumed` → delete `id`. Emit `onChange` only
  on 0↔n transitions (room-meta traffic stays bounded).
- Narrow every payload as `{ id?: unknown }` and bail on non-string —
  the bus is typed `unknown` end to end.
- Do NOT use `subagents:child:disposed` as completion (sessions are
  retained after completion for resume).

**Acceptance Criteria**:
- [ ] Fake-bus test: created/completed/failed drive the count; malformed
      payloads (`null`, `{}`, `{id: 7}`) are ignored without throwing.
- [ ] `onChange` fires only on 0↔n transitions, not per event.
- [ ] `subscribe` twice on the same bus registers one listener set.
- [ ] `clearForSessionBoundary` empties the set and emits when it was
      non-empty.

### Unit 2: RoomMeta field + publish wiring
**File**: `pi-extension/src/transport/relay_client.ts` (type),
`pi-extension/src/extension/relay_transport.ts` (patch type),
`pi-extension/src/index.ts` (wiring)
**Story**: `story-background-work-ext-tracker`

```ts
// relay_client.ts — RoomMeta gains:
/** True while background subagents (pi-subagents tasks) are queued/running
 *  beyond the agent turn. Optional — older apps ignore it. */
background?: boolean;

// index.ts:
function _publishBackground(active: boolean): void {
  _publishRoomMetaPatch({ background: active });
}
```

**Implementation Notes**:
- Extend `sendRoomMeta`'s patch type and `_publishRoomMetaPatch`'s patch
  type with `background?: boolean` (mirrors `working`).
- Wire the tracker in `composition_root.ts` next to
  `observeChildLifecycle(eventBus)` (same guarded
  `(pi as Partial<ExtensionAPI>).events` access), with `onChange` →
  `_publishBackground(activeCount > 0)`.
- Session reset paths that already call `_publishWorking(false)`
  (new-session reset and dispose in `index.ts`) also call
  `clearForSessionBoundary()` + `_publishBackground(false)`.

**Acceptance Criteria**:
- [ ] `room_meta_update` control frames carry `background: true/false`
      only on transitions (integration test at the relay_transport seam,
      following existing room-meta test patterns).
- [ ] Session replacement publishes `background: false`.

### Unit 3: Restart-gate hardening
**File**: `pi-extension/src/index.ts`
**Story**: `story-background-work-ext-tracker`

**Implementation Notes**:
- In `_maybeRestartForExtensionReload`, add an early guard alongside the
  existing ones: if `tracker.activeCount > 0`, return WITHOUT consuming
  the armed request (deferral, not cancellation — the 5-min TTL and the
  restart-loop's re-arm behavior handle long-running work).
- On the tracker's drain transition (n→0), re-invoke
  `_maybeRestartForExtensionReload(lastSettledCtx)`, where the
  `agent_settled` handler stores its minimal
  `Pick<ExtensionContext, "isIdle">` ctx in module state.
- This closes a latent hazard independent of the UX goal: today an armed
  hot reload fires at `agent_settled` and would kill running background
  tasks (in-memory, process-bound).

**Acceptance Criteria**:
- [ ] Armed reload + active background task → no restart, armed file
      intact; drain → restart proceeds (unit test at the gate function
      with a fake tracker).

### Unit 4: App room snapshot + parsing
**File**: `app/lib/data/transport/connection_manager.dart`
**Story**: `story-background-work-app-surface`

**Implementation Notes**:
- Parse `background` from `room_meta_updated` meta with the same
  preserve convention as `working` (absent key → preserve existing;
  explicit value → set). Room snapshot model gains the field.

**Acceptance Criteria**:
- [ ] Meta with/without `background` updates the room snapshot correctly
      (mirror of the `working` preserve tests).

### Unit 5: App projection + indicator
**File**: `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`,
`app/lib/ui/chat/chat_page.dart` (`_ChatStatusIndicator`)
**Story**: `story-background-work-app-surface`

```dart
// ChatStatusProjection gains a fourth axis (transport/turn/steering stay as-is):
final bool background; // room-level: background subagents active
```

**Implementation Notes**:
- ViewModel composes `background` from the active room's snapshot (same
  authority/stale-gating scope as the room's `working`).
- `_ChatStatusIndicator`: when `status.background` and the turn status
  maps to no active label (idle/done/stale), render an `orchestrating…`
  chip in `colors.working`. Turn status (working/streaming/awaitingTool/
  error) takes precedence when active.
- Composer unchanged: `isWorking` and the Stop affordance stay
  turn-scoped; background does not gate input.

**Acceptance Criteria**:
- [ ] Widget test: background + idle turn → 'orchestrating…' chip;
      background + working turn → 'working…' wins; no background →
      unchanged rendering.
- [ ] `flutter analyze` clean.

---

## Implementation Order
1. `story-background-work-ext-tracker` (Units 1-3) — the signal source
   and wire field must exist first.
2. `story-background-work-app-surface` (Units 4-5) — consumes the field.

## Simplification

- A trustworthy "orchestrating" state retires the narration convention
  (agents prose-reporting wait-state) as an operator expectation — update
  operator-facing docs to stop prescribing it once shipped.
- No parallel indicator: the chip composes into `_ChatStatusIndicator`'s
  existing label stack; no new widget hierarchy.
- The tracker deliberately does NOT duplicate the package's registry —
  it is a projection (id set) with transitions only, not a status store.

## Testing

- Extension unit tests (fake bus): tracker transitions, malformed-payload
  tolerance, idempotent subscribe, boundary clear — protects the
  untrusted-payload contract.
- Extension integration: `room_meta_update` frames carry `background` on
  transitions — protects the wire contract at the relay seam.
- Restart-gate test: deferral + drain-retry — protects the
  don't-kill-running-work invariant.
- App: connection_manager preserve/parse mirror test — protects the
  meta-parsing contract; widget test for the three-state mapping and
  turn-precedence — protects the operator-visible behavior.
- No test removals identified.

## Risks

- **Package event contract drift**: the `subagents:*` channels are
  exported constants of `@gotgenes/pi-subagents` but carry no cross-repo
  compatibility guarantee. A rename/shape change degrades to today's
  behavior (idle chip) — fail-quiet, not fail-wrong. The narrowing keeps
  malformed payloads from crashing the extension.
- **Hot-reload drift window**: events between unsubscribe/re-subscribe are
  lost (set undercounts). Closed for the armed-reload path by Unit 3;
  manual pi restart kills the tasks anyway (self-consistent).
- **`resumed` edge**: resuming a completed background agent shows idle
  during the resumed run (only its terminal `resumed` event fires).
  Accepted: resume is an operator-initiated action with narration.
- **Sibling pi processes** (patchbay etc.) each see only their own
  subagents — correct scope: the room reflects this pi.

## Mockups

Skipped (fallback tier): minor composition reusing the existing
`_ChatStatusIndicator` label stack and existing palette tokens; no
net-new screen or journey. (Seam names verified 2026-08-27: earlier
`_nlIndicator`/`nlProjection` references were grep artifacts.)

## Implementation summary (2026-08-27)

Both checkpoints landed and verified:

- `story-background-work-ext-tracker` (done, `0c99f262a` + supplemental
  `04e0ebb5f`): `BackgroundActivityTracker` with structural payload
  narrowing and transition-only onChange; `RoomMeta.background` through
  relay_client → sendRoomMeta → `_publishRoomMetaPatch`; tracker wired in
  composition_root beside `observeChildLifecycle`; session-reset paths
  clear + publish false; `_maybeRestartForExtensionReload` defers while
  background is active and re-attempts on drain (armed file preserved
  during deferral). The supplemental commit carries the extension.test.ts
  end-to-end coverage the worker correctly kept out of its scoped commit
  (transition-edge `room_meta_update` frames; armed-file lifecycle through
  deferral → drain → SIGTERM).
- `story-background-work-app-surface` (done, `235414321`): `background`
  parsed with the `working` preserve convention in connection_manager
  (`RoomInfo.background`); `ChatStatusProjection` background axis with
  live-room gating; `orchestrating…` chip in `_ChatStatusIndicator` with
  turn-status precedence; composer untouched.

## Integrated verification (2026-08-27)

- pi-extension: `corepack pnpm typecheck` clean; `pnpm test` 63 files,
  1,118 passed / 3 skipped (pre-existing skips).
- app: `flutter analyze` no issues; `flutter test --exclude-tags e2e` 996
  passed.

Both child checkpoints done + integrated verification green → feature
advances to review. Effective review_weight: standard (default; no caller
or project override).

## Review record (2026-08-27)

- **Effective weight**: standard (default). **Passes**: 1 independent
  fresh-context pass (cross-model: gpt-5.6-sol xhigh) + receiver-confirmed
  fix round, closed without a second pass per standard policy.
- **Verdict**: Request changes → fixed → approved on re-verification.
- **Findings adjudicated**:
  - B1 (Blocker, confirmed): `background` bypassed the canonical
    relay-control schema (`additionalProperties: false` in roomMeta /
    roomMetaPatch / helloRoomMeta) — the relay dropped the field and the
    feature could not work end-to-end. Design flaw from the feature-design
    pass (assumed relay-opaque meta without checking the generated
    contract). Fixed through the canonical path: schema + mergePatchSemantics
    + regenerated TS/Dart/Rust + relay merge/broadcast (incl. room
    announcements) + fixtures + SPEC/ARCHITECTURE roll-forward + round-trip
    relay test (`d13b85fec`).
  - B2 (Blocker, confirmed): `_goIdle()` cleared the tracker on ordinary
    relay stop although background tasks outlive the relay connection —
    orphaning the state and re-arming the hot-reload kill hazard. Clear
    moved to true session-replacement/dispose boundaries; reconnect
    republishes live background state; stop/start + drain tests added.
  - I1 (Important, confirmed): done/stale agent labels suppressed the
    background chip, violating the designed precedence. Background now wins
    over done/stale (turn-active labels still win); widget cases added.
  - Nits: none filed.
- **Post-fix verification (orchestrator-run)**: protocol check green;
  extension 63 files / 1,119 passed / 3 skipped (pre-existing); relay
  fmt+clippy+tests green; app analyze clean / 996 passed.

Feature complete: both child checkpoints done, integrated verification
green, review blockers fixed and re-verified.
