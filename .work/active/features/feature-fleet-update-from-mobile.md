---
id: feature-fleet-update-from-mobile
kind: feature
stage: review
tags: [pi-extension, app, workflow, deps]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-08
---

# Fleet pi update + rolling restart, drivable from mobile

## Brief

The operator's ask (2026-09-07): "run the pi updates and then execute restart
normally" — drivable from the phone, because fleet update control is "one of
my last ties to the workstation." An "Update" button in the Outpost app sends
the existing control-command plumbing to the primary paired pi, which runs
`pi update` + `pi update --extensions` and then arms a self-quiescing rolling
restart across the local fleet via hot-reload arm + local agent-mesh
broadcast. No fleet stop phase: Linux inode semantics make stopping
unnecessary — running pis keep their old binary's inode, and every wrapper
relaunch picks up the new binary automatically.

This is mostly assembly of shipped mechanisms (hot-reload arm, restart-gate
deferral, mesh broadcast, app control-command surface) into one fleet-level
device-ops action. UI surface is app settings: a confirmation-gated Update
button plus per-pi phased status (updating → arming → restarting → verified) —
existing app patterns, align at feature-design.

## Strategic decisions

- **v1 mesh scope: local fleet only** (operator, 2026-09-07) — arm-restart
  broadcast targets local broker peers on this VM only; cross-PC mesh peers
  are explicitly out of scope for v1 (single VM surface in use). A cross-PC
  extension is a clean follow-up feature if the fleet ever spans machines.
- **Not a chat command** (operator direction, 2026-09-07) — the trigger is a
  fleet-level action in the app's settings surface; this is device-ops, not
  conversation.
- **No stop phase** (revised 2026-09-07 from the original ask) — inode
  semantics + wrapper relaunch make stopping the fleet unnecessary.

## Simplification opportunity

No new restart or confirmation mechanism — deliberately reuses the hot-reload
arm + `.hot-reload-armed` + agent_settled gate, the v0.11.0 restart-gate
deferral (turns finish, background work drains first), and the existing app
control-command ack surfaces. herdr stays untouched (optional observer via
the background-aware state). If any per-pi restart path duplicates wrapper
logic, prefer driving the existing wrapper rather than a second restart
implementation.

## Design input (shaped at park, 2026-09-07)

### Shape

1. **Trigger from mobile — an "Update" button in the Outpost app**: a
   fleet-level action in the app's settings surface. The button sends the
   existing control-command plumbing to the primary paired pi; per-pi progress
   + final fleet status render in the same surface (phases: updating → arming
   → restarting → verified). Confirmation step required — it restarts every pi
   the phone can reach.
2. **Update phase**: that pi runs `pi update` + `pi update --extensions`
   (subprocess, captures result). No pis stop.
3. **Rolling restart via existing mechanisms**: the extension arms its own
   hot-reload restart (`.hot-reload-armed` + agent_settled → graceful exit →
   wrapper relaunches `pi` from PATH = new binary) AND broadcasts
   "arm-restart" to sibling pis over the **local agent mesh**
   (list_peers/agent_send — the broker already spans the fleet on this box;
   sibling outpost extensions subscribe and arm their own hot-reload). Each
   pi restarts at ITS next settle — turns finish, background work drains
   first (the v0.11.0 restart-gate deferral already covers this), making it a
   self-quiescing rolling restart.
4. **Report to phone**: per-pi arming status + final relay re-authentication
   confirmations as the fleet comes back.

### Pieces that exist (this is mostly assembly)

- Hot-reload arm + restart-gate deferral (background-aware) — shipped.
- Fleet uniformly under the restart wrapper — done 2026-09-07.
- Local mesh broadcast (agent_send) + sibling extension event handling
  (`command_surface/local_mesh_commands.ts`).
- App control-command surface.
- herdr untouched (optional observer via the background-aware state).

### Design decisions

- **Wire shape — typed app↔pi messages, not Cockpit control RPC**: new client
  message `fleet_update` in `protocol/schema/app-pi-client.schema.json` +
  new server message `fleet_update_status` in `app-pi-server.schema.json`,
  riding the existing app↔pi codegen (the `session_new`/`session_compact`
  command family). Multi-event status pushes, not request/response polling —
  the operator watches progress live. Mixed-version safe: an old extension
  answers an unknown client type with its standard error; an old app never
  sends it. Not a paired cutover.
- **Phase reporting split — extension reports what it knows, app derives the
  rest**: `updating` and `arming` (+ per-pi ack table) are emitted by the
  coordinator extension; `restarting`/`verified` are DERIVED app-side from
  room/presence recovery (the coordinator is itself restarting — it cannot
  report its own exit; the app already tracks room re-announce on
  reconnect). The app holds a fleet-update-in-progress flag that ALSO
  suppresses the connection-lost error UX for the update window (expected
  mass disconnect ≠ metronome flap).
- **Mesh arm protocol**: coordinator broadcasts arm-restart to local broker
  peers (existing mesh trust model — local peers are trusted agent
  endpoints); each sibling's outpost handler writes its OWN nonce'd armed
  file (never a cross-process file write) honoring the existing
  `.hot-reload-enabled` host toggle and disposed state, then replies an ack
  `{ state: armed | deferred | declined, reason? }`. Ack timeout (~5s,
  broker is local) reports `no-ack` — an old-dist sibling simply doesn't
  restart; nothing is forced.
- **Update failure — report + skip restart** (park decision): nonzero exit
  or timeout (~10 min) → `update_failed` status with captured output tail;
  no arming; fleet stays on the old binary (safe by construction).
- **Self-arm via the internal API** — the coordinator uses the same arming
  path an external command would (own nonce, own pid, idle-gated claim at
  agent_settled), never a bespoke restart code path.
- **Idempotence**: one fleet_update at a time per pi; a second request while
  running returns `already_running` status.
- **UI** (operator-locked at park): settings `_FleetSection` (the page's
  existing section pattern), confirmation dialog ("restarts every pi on
  this VM"), phase progress + per-pi ack list, disabled-with-reason when no
  pi room is connected.
- **Trust**: `fleet_update` is a session-scoped client message inside the
  sealed owner channel — same authority as `user_message` (which can drive
  the agent anyway); no new trust surface. Local-only v1 (strategic lock).

## UI alignment

ux-ui plugin installed; no parent epic. Skipped as minor composition
reusing existing patterns: settings section, confirmation dialog, phase
list. No mocks produced.

## Architectural choice

**Coordinator-pi orchestration over the existing rails** — the pi the app's
room is attached to runs the update, arms itself, and drives siblings via
the local agent mesh — over (a) app-orchestrated per-pi commands (the app
  would need to address each pi individually; rooms are sub-channels of one
  peer and the phone may hold only one owner channel — wrong topology) and
  (b) a fleet supervisor daemon (new always-on process, new failure mode,
  duplicates what the mesh + wrapper already do). The coordinator pattern
  needs no new infrastructure: subprocess + armed-file + mesh request/reply
  all exist; the fleet is self-quiescing because every exit is settle-gated
  by the shipped restart-gate deferral.

## Implementation Units

### Unit 1: wire protocol — fleet_update + fleet_update_status
**File**: `protocol/schema/app-pi-client.schema.json`,
`protocol/schema/app-pi-server.schema.json`, regenerated
`pi-extension/src/protocol/generated/protocol.generated.ts` +
`app/lib/protocol/generated/relay_frames.g.dart` (or the app-pi generated
file the codegen owns for these unions — verify exact output paths against
the `appPiClient`/`appPiServer` catalog entries),
`protocol/fixtures/` rows
**Story**: `feature-fleet-update-from-mobile-wire-protocol`

Client message (session-scoped):
```ts
{ type: "fleet_update"; id: string; session_id: string }
```
Server status event (push, repeatable):
```ts
{
  type: "fleet_update_status";
  update_id: string;            // correlates one run
  phase: "updating" | "arming" | "update_failed" | "already_running";
  detail?: string;              // output tail on failure, else phase note
  peers?: Array<{ peer: string; state: "armed" | "deferred" | "declined" | "no-ack"; reason?: string }>;
}
```
(`restarting`/`verified` are app-derived — see design decisions; they are
NOT wire phases.)

**Acceptance Criteria**:
- [x] Codegen green; TS + Dart generated types committed; discriminator
      maps (`CLIENT_MESSAGE_DISCRIMINATORS`, server types) include both
      messages; session-scoped list gains `fleet_update`
- [x] Fixture rows: request + each status variant
- [x] Unknown-type behavior verified: old-extension-style handler answers
      an unrecognized client type with the standard error (existing codec
      test pattern)

### Unit 2: extension fleet coordinator + sibling arm handler
**File**: new `pi-extension/src/extension/fleet_update.ts`; wiring in
`pi-extension/src/index.ts` (client-message dispatch +
`session_start`/agent_settled hooks reuse); sibling handler in
`pi-extension/src/extension/command_surface/local_mesh_commands.ts`
**Story**: `feature-fleet-update-from-mobile-extension-coordinator`

```ts
/** Drives one fleet update run: pi update → self-arm → mesh arm broadcast
 *  → ack aggregation → status events. One run at a time per process. */
export class FleetUpdateCoordinator {
  constructor(opts: {
    emitStatus: (ev: FleetUpdateStatusEvent) => void;
    runUpdate: () => Promise<{ ok: boolean; outputTail: string }>;  // pi update + --extensions, ~10min timeout
    armSelf: () => void;            // internal nonce'd armed-file write
    localPeers: () => string[];     // broker-local peers only (v1: no cross-PC)
    meshRequest: (peer: string, body: unknown, timeoutMs: number) => Promise<{ ack?: unknown } | null>;
    updateTimeoutMs?: number;
    ackTimeoutMs?: number;          // default 5000
  })
  async handleRequest(): Promise<void>   // idempotence gate → phases
  inFlightForTest(): boolean
}
```

Sibling side (local_mesh_commands family): mesh message
`{ kind: "outpost-pi.arm-restart", update_id }` → if `.hot-reload-enabled`
missing/off or disposed → ack `{ state: "declined", reason }`; else write
own armed file (existing nonce/ts discipline) → ack
`{ state: "armed" }` ("deferred" when a turn is active — the claim happens
at that pi's next settle, which IS the rolling-restart semantics).

Sequence: emit `updating` BEFORE subprocess; on failure emit
`update_failed` and stop; on success emit `arming` AFTER acks collected
(never after self-arm — see Risks), THEN armSelf last (coordinator is the
final pis to arm so its exit can't orphan the report).

**Acceptance Criteria**:
- [ ] Unit tests (injected fakes): success path phase order; update
      failure → no arm; second request → `already_running`; ack table with
      declined/deferred/no-ack rows; status-before-self-arm ordering
- [ ] Sibling handler tests: arms when enabled, declines with reason when
      toggle off/disposed, own-nonce file written (fs-mocked)
- [ ] Live lane (one VM): trigger via harness → wrapper bounce observed on
      all pis (the story-fix-new-wedge-bare-pi wrapper path is the verified
      2.3s-bounce rail)
- [ ] `corepack pnpm typecheck && test && build` green

### Unit 3: app Fleet section + update state machine
**File**: `app/lib/ui/settings/settings_page.dart` (_FleetSection), new
`app/lib/ui/settings/fleet_update_viewmodel.dart`, dispatch hook where
ServerMessage frames land (`app/lib/data/sync/sync_service.dart` family),
command send via the existing client-message path
**Story**: `feature-fleet-update-from-mobile-app-ui`

- Viewmodel state machine:
```dart
sealed class FleetUpdateState {}
class FleetIdle extends FleetUpdateState {}
class FleetUpdating extends FleetUpdateState {}        // wire: updating
class FleetArming extends FleetUpdateState { final List<FleetPeerAck> peers; } // wire: arming
class FleetUpdateFailed extends FleetUpdateState { final String detail; }
class FleetRestarting extends FleetUpdateState {}     // derived: owned rooms went offline mid-run
class FleetVerified extends FleetUpdateState {}       // derived: rooms re-announced with fresh session meta
class FleetUpdateLost extends FleetUpdateState {}      // derived: no recovery within timeout → error UX
```
- Derivation rules: `arming`/`updating` + transport drop → `restarting`
  (suppress reconnect-error banner while a run is active — scoped flag,
  cleared on terminal state); rooms re-announced → `verified`; no recovery
  in ~5 min → `FleetUpdateLost` (normal error UX resumes).
- Button: disabled with reason when no owned room connected; confirmation
  dialog on tap; sends `fleet_update` to the connected room's pi.

**Acceptance Criteria**:
- [ ] Viewmodel tests: wire-event → state mapping; drop-during-run →
      restarting (no error banner); recovery → verified; timeout → lost
- [ ] Widget tests: confirmation gate, disabled-with-reason, phase + ack
      list rendering
- [ ] `flutter analyze && flutter test --exclude-tags e2e` green
- [ ] Optional-if-heavy (implementation judgment): pairing-suite lane for
      trigger → status → update_failed path

---

## Implementation Order

1. `…-wire-protocol` (both sides compile against it)
2. `…-extension-coordinator` ∥ `…-app-ui` (independent sides; app testable
   against fixture status events)

## Simplification

- The operator's manual loop (ssh → pi update → wrap/restart each pane) is
  DELETED by this feature — that workflow is the thing being cut.
- No new supervisor/daemon, no per-pi addressing protocol, no chat-command
  parsing: deliberately assembled from subprocess + armed-file + mesh
  request/reply. Nothing else in the area gets simpler or more complex.

## Testing

- **Coordinator state machine**: unit tests with injected fakes protect
  phase order, failure skip, idempotence, and the report-before-self-arm
  ordering (the orphaned-report regression).
- **Sibling arm handler**: decline reasons + own-nonce arming (the trust
  boundary is the armed file, already hardened — keep it that way).
- **App derivation rules**: the restarting/verified/lost transitions are
  the novel app logic — viewmodel tests carry them.
- **Reconnect-suppression scope**: the flag must clear on every terminal
  path (scan-lifecycle class) — test each terminal explicitly.
- **Live lane**: one real VM bounce (wrapper path already proven live).

## Risks

- **Orphaned report** (coordinator exits before the app processes `arming`):
  mitigated by ordering (status emitted before any arm, self-arm LAST) +
  app-side derivation — the app never NEEDS the final wire event.
- **Mass-disconnect UX**: an active run suppresses reconnect-error banners;
  a run that never recovers re-enables them via `FleetUpdateLost` timeout.
- **Bootstrap**: the feature must already be in the fleet's dist before the
  button works (ESM: dist loads at process start) — first use follows the
  deploy that ships it; note in release notes.
- **Old-dist siblings**: no handler → no ack → reported `no-ack`; they stay
  on the old binary until their next manual restart. Safe by design.
- **`pi update` PATH drift**: the wrapper relaunches `pi` from PATH — the
  same PATH the coordinator resolved; if PATH differs per pane the fleet
  still converges on next wrapper cycle. Acceptable; not designed around.
- **Subprocess hang**: 10-min timeout → update_failed. No retry loop.

## Design-time advisory review

Skipped (risk-driven policy): assembly of shipped mechanisms with no new
trust surface; the two novel logics (phase ordering, app derivation) are
unit-pinned. The live lane is the integration backstop.

## Implementation summary

All three child stories are now `stage: done` in their frontmatter:

- `feature-fleet-update-from-mobile-wire-protocol` — typed client/server wire
  messages, generated projections, fixtures, and compatibility behavior
  (commit `9768e4b67`).
- `feature-fleet-update-from-mobile-extension-coordinator` — update subprocess,
  status ordering, local mesh arm acknowledgements, and settle-gated sibling
  restart orchestration (commit `932d9e1e3`). Its live bounce lane remains
  operator-deferred because this task is forbidden from restarting the live
  fleet.
- `feature-fleet-update-from-mobile-app-ui` — settings Fleet section,
  confirmation gate, typed send path, reconnect suppression, room/session
  recovery derivation, and deterministic lifecycle-safe widget coverage (commit
  `aa43449fd`).

The app side keeps the route and embedded settings sheet ViewModel provisioning
parallel with `SettingsViewModel`. The coordinator's own report-before-arm
ordering and the app's room/session-pinned recovery rules are covered by their
respective unit suites. The chat error-banner consumption of the app's
suppression flag remains an explicit review discovery, not an unrequested chat
surface change.

## Integrated verification

- `pi-extension`: the completed coordinator story recorded passing
  `corepack pnpm check:protocol`, `typecheck`, `test` (1,145 passed, 3 skipped),
  and `build`.
- `app`: `flutter analyze` passed with no issues; the fleet ViewModel and widget
  suites passed (22 + 5 tests).
- The required full app command, `flutter test --exclude-tags e2e
  --concurrency=2`, passed all 1,060 tests. The run emits the repository's
  existing offline `google_fonts` diagnostics, but the suite exits green.

## Implementation notes addendum (2026-09-07, orchestrator)

- The story-3 worker's flagged "blocker" was NOT pre-existing and is now
  FIXED: story 1 updated the shared catalogs (`protocol/fixtures/app-pi/`)
  but not the per-type contract catalog `.orchestration/contracts/fixtures/`
  (+ its two classification sets in `app/test/protocol_test.dart` and
  `app/test/protocol_codegen/server_messages_codegen_test.dart`). Added
  `fleet_update_status.jsonl` (all four phases incl. full ack table) +
  `fleet_update.jsonl` and classified both. Both suites green.
- Full app suite: 1051 passing; `sync_service_test.dart` timeout-themed
  tests flake under full-suite parallel load (rotating failures across runs,
  3/3 green in isolation, additive-only diff to sync_service.dart — one
  ignored-cases switch entry). Recorded as pre-existing load-flake, not a
  regression; parked for the flake backlog if it recurs.
- chat_page's reconnect-banner CONSUMPTION of the suppression flag remains
  viewmodel-complete-but-unwired (story-3 discovery) — carried into review.

## Review fixes

Applied 2026-09-08 for the nine confirmed review findings. The feature remains
at `stage: review`; the live fleet lane remains operator-deferred and no live
process or marker was touched.

1. **Restart identity was too weak.** Recovery now pins the selected peer,
   room, and baseline `RoomInfo.startedAt`; verification requires the pinned
   room to return with a changed start marker, even when the SDK session id is
   reused. Covered by the same-session and changed-`startedAt` ViewModel tests.
2. **Idle arms could miss the restart gate and deferred arms could expire.**
   Fleet sibling staging evaluates the existing idle gate immediately after
   the acknowledgement boundary, while deferred fleet arm files refresh their
   timestamp only at the existing gate and only after nonce/update fencing.
3. **Inbound mesh arms lacked local/replay boundaries.** The coordinator caches
   the broker's structured local roster, rejects non-local senders, and
   atomically consumes update ids in owner-only marker files. Replayed commits
   are declined after process restart; cross-PC peers remain out of scope.
4. **One-phase arm broadcast could restart before the `arming` report.**
   Siblings now answer a prepare request without arming; after the coordinator
   emits `arming`, it sends commit requests and arms itself last. The phase
   ordering and single-consumption behavior are unit-tested.
5. **An active run could wedge without a terminal signal.** Recovery timers
   are armed from both `updating` and `arming`, remain active through transport
   recovery, and converge to `FleetUpdateLost` when no pinned room returns.
   Terminal paths cancel timers and clear suppression.
6. **Fixture tests hard-coded a stale file count.** Extension fixture checks
   now validate required catalog entries and typed content rather than a
   literal count; the same catalog/content rule is used by the codec suite.
7. **The coordinator could target itself as a sibling.** Local roster
   selection now removes the coordinator's own mesh address before prepare
   requests, with duplicate addresses collapsed by the coordinator.
8. **Recovery could follow a newly selected peer or room.** The app keeps the
   original peer/room/update id pinned throughout disconnects and ignores
   mismatched status or room snapshots. A switched-peer regression test covers
   the boundary.
9. **Completion copy overstated fleet certainty.** Verified UI text now reports
   `coordinator verified · N/M Pis acked`, using only coordinator-reported
   acknowledgements; a coordinator self-arm failure is surfaced as an explicit
   no-restart terminal state instead of a false success.

Validation after these fixes:

- `cd pi-extension && corepack pnpm check:protocol && corepack pnpm typecheck
  && corepack pnpm test && corepack pnpm build` — passed (65 files, 1,154
  tests passed, 3 skipped).
- `cd app && flutter analyze` — passed with no issues.
- `cd app && flutter test --exclude-tags e2e --concurrency=2` — passed (1,060
  tests).
- No relay, telemetry, protocol schema, live process, or live marker changes.
