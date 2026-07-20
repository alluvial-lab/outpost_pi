---
id: epic-remote-session-resilience-refactor
kind: epic
stage: done
tags: [pi-extension, app, relay, workflow]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-06-27
updated: 2026-07-20
---

# Remote session resilience refactor

Bold refactor arc for Remote Pi's mobile/workstation remote-coding experience: make session state, mesh/relay semantics, and mobile UI state robust under reconnects, multi-client use, `/new`, dropped events, and long-running agent turns.

## Drivers

- Mobile and workstation can attach to the same remote Pi session, but session/control semantics need to be explicit and observable.
- A bug is already filed where mobile status can stay stuck on `Working` after the agent is idle: `.work/backlog/remote-pi-mobile-working-status-stuck.md`.
- The Pi extension and Flutter app likely both need state-machine cleanup rather than one-off patches.
- The full codebase should receive multi-model adversarial review before/alongside invasive changes.

## Arc sketch

Sequence the arc as **reference → review → design → refactor**, with only urgent narrow patches allowed to bypass the full track.

1. **Stabilize the agent substrate first.** Build enough platform-style reference surface for agents to reason correctly about the stack before asking them to review or refactor it:
   - `feature-agent-reference-surface`
   - `feature-mobile-remote-coding-best-practices-skill`
2. **Patch only small/high-confidence live bugs while research runs.** `story-mobile-working-status-stuck` may proceed as a narrow bugfix if reproduction is clear, but should record any architectural findings back into the epic rather than ballooning into the refactor.
3. **Run adversarial review after the first reference pass, before the bold refactor.** Reviewers should receive the new stack references, `PROTOCOL.md`, recent stale-context history, and the mobile/mesh best-practices checklist:
   - `feature-adversarial-codebase-review`
4. **Deduplicate and design the state-machine refactor.** Convert accepted findings into implementation stories grouped by boundary: pi-extension authoritative session/room state, app state/rendering, relay protocol/semantics, tests/smokes.
5. **Implement in thin vertical slices.** Prefer one observable session-state behavior per slice (`/new`, reconnect hydration, dropped turn_end, multi-client attach) with tests/smokes at each boundary.
6. **Final cross-model review + live soak.** Re-run focused adversarial review on the refactored paths and soak via real mobile/workstation use before considering upstream PRs.

## Initial decomposition

- `feature-agent-reference-surface` — platform-style language/library/dev-cycle references for Remote Pi agents.
- `feature-mobile-remote-coding-best-practices-skill` — targeted research + durable best-practices skill/checklist for mobile remote-coding mesh apps.
- `feature-adversarial-codebase-review` — multi-model adversarial review of app, pi-extension, relay, cockpit/site where relevant.
- `story-mobile-working-status-stuck` — reproduce and fix stale `Working` status.

## Decomposition (2026-07-18 epic-design pass)

The 2026-06-29 reframing was superseded by the 2026-07 `scope` pass, which
promoted the residual targeted patches + the mobile-UX cluster into 6 child
features. Two of those shipped this session (the app + piext-delivery
lifecycle-ownership features); four remain at `stage: drafting`. This epic
closes when those four ship.

The bold-refactor epics (`epic-bold-*`) remain the architectural reconception
track and are NOT children of this epic. This epic holds only the targeted,
shippable-before-reconception resilience work.

### Child features

- `feature-app-async-lifecycle-ownership` — app-side async ownership +
  convergence (generation guards, per-peer persistence, transcript
  degradation, mesh publication). **DONE 2026-07-18.**
- `feature-piext-lifecycle-delivery-promise-policy` — pi-extension failure
  policy for discarded delivery/lifecycle promises. **DONE 2026-07-18.**
- `feature-outbound-buffer-on-peer-offline` — buffer Pi→app frames while the
  app peer is known offline; flush on reconnect. Builds on the shipped
  `story-extension-suspend-fanout-on-peer-offline` (v0.1.0), which added the
  suspend; this adds the buffer. depends on: `[]`
- `feature-mobile-native-session-process-control` — expose `session_new` +
  `EXIT_DAEMON_FRESH_SESSION` (exit 42 → supervisor respawn) as a mobile
  control surface. depends on: `[feature-remote-pi-fork-vendor-and-mobile-surface]`
  (shares the mobile-surface scope)
- `feature-mobile-tui-parity-chat-resilience` — resolve the transport-vs-agent
  state conflation (the structural parent finding) + the mobile chat
  ordering/blank/recovery symptoms. depends on: `[]`
- `feature-remote-pi-fork-vendor-and-mobile-surface` — fork setup + mobile
  build smoke. **~90% done** (4 of 5 child stories shipped extension-0.5.4 /
  app-v1.1.1); only `story-remote-pi-mobile-mode-client-slice` remains
  (conditional). depends on: `[]`

### Standalone stories (also children)

- `story-stale-command-ui-notify-guard` — safe command-notification helper.
  depends on: `story-stale-session-bound-surface-deep-audit` (shipped
  extension-0.5.4, in `.work/releases/`). Dependency is met; this story is
  ready to implement.
- `story-stale-action-boundary-regression-tests` — replacement-boundary
  regression tests for app action surfaces. Same met dependency.

### Cross-epic dependencies (resolved)

- `feature-outbound-buffer-on-peer-offline` ↔ `feature-reconnect-reproduction`
  (sibling epic `epic-targeting-and-session-lifecycle-contracts`): the
  reconnect-repro feature's `idea-extension-pumps-into-dead-app-peer` was the
  same gap, already addressed by the shipped `story-extension-suspend-fanout-on-peer-offline`
  (v0.1.0). The outbound-buffer feature is the next step beyond suspend
  (buffer instead of drop). No active dependency edge; the reconnect-repro
  feature's live-repro items (`idea-mobile-drop-slow-recovery`,
  `idea-mobile-outgoing-message-swallowed`) overlap with
  `feature-mobile-tui-parity-chat-resilience`'s symptom list — those route to
  whichever feature designs first; the other closes its copy as a provenance
  checkpoint.
- `idea-mobile-conflates-transport-and-agent-state` (F3's parent structural
  finding) was misfiled under the old reconnect contract; it's a UI-projection
  / turn-phase question and routes under `feature-mobile-tui-parity-chat-resilience`,
  not the sibling epic.

### Simplification arcs

- `feature-outbound-buffer-on-peer-offline` — replaces the silent drop with a
  bounded buffer; the shipped suspend logic stays.
- `feature-mobile-tui-parity-chat-resilience` — the transport-vs-agent-state
  conflation fix subsumes several status/steering symptoms; distinct
  reproducible bugs reduce to one-line fixes once the structural split lands.
- `feature-remote-pi-fork-vendor-and-mobile-surface` — close as ~done after
  reconciling the one conditional child story.

### Decomposition risks

- `feature-mobile-tui-parity-chat-resilience` is the largest and most
  open-ended (10 backlog items, several requiring live phone repro). Its
  design pass must decide which symptoms are structurally subsumed by the
  conflation fix vs. which are distinct bugs needing individual repro — and
  which live-repro-only items park until the next drop test.
- `feature-outbound-buffer-on-peer-offline` has real semantics decisions
  (buffer location, bound/overflow policy, flush ordering vs. `session_sync`,
  teardown interaction) that are design-bearing, not mechanical.
- `feature-mobile-native-session-process-control` depends on the
  mobile-surface feature's scope; if the fork-vendor feature closes as
  ~done, the dependency is met by the shipped build path.

## Draft acceptance

- Clear architecture notes for authoritative session state, working/idle state, reconnect hydration, and multi-client behavior.
- Review findings are deduplicated and converted into scoped work items.
- Refactor is split into app and pi-extension implementation stories with verification plans.

## Epic completion (2026-07-19)

All 8 children reached `stage: done` through the implement-orchestrator +
review cycle (standard weight). This epic's residual targeted patches +
mobile-UX cluster are complete; the bold-refactor epics (`epic-bold-*`)
remain the separate architectural reconception track.

| Child | Outcome |
|---|---|
| `feature-app-async-lifecycle-ownership` | done (6 review findings fixed) |
| `feature-piext-lifecycle-delivery-promise-policy` | done (ready, no findings) |
| `feature-remote-pi-fork-vendor-and-mobile-surface` | done (reconciled ~complete) |
| `feature-outbound-buffer-on-peer-offline` | done (2 blockers fixed) |
| `feature-mobile-tui-parity-chat-resilience` | done (3 materials fixed) |
| `feature-mobile-native-session-process-control` | done (1 blocker + 3 material fixed) |
| `story-stale-command-ui-notify-guard` | done (bounded inline review) |
| `story-stale-action-boundary-regression-tests` | done (bounded inline review) |

The 2 live-repro items (`idea-mobile-drop-slow-recovery`,
`idea-mobile-outgoing-message-swallowed`) remain parked at `drafting` under
`feature-mobile-tui-parity-chat-resilience` (now done) — they route to
`feature-reconnect-reproduction` (sibling epic) on the next live drop test.

## Epic aggregate review findings (fresh-context, gpt-5.6-sol, standard weight)

Review verdict: `needs fixes`. Two material cross-feature findings (both
verified by the orchestrator). These must be fixed before the epic closes.

### Material 1 — reconnect trusts stale room liveness; can resend into unconfirmed room
`app/lib/data/transport/connection_manager.dart:1512-1525` (transport loss
clears `working` but retains `_liveRoomIds`), `:954-958` (`isRoomLive()` trusts
retained set on reconnect), `:601-605,1523-1525` (online transition emits
cached snapshot before fresh replies), `app/lib/data/sync/sync_service.dart:747-767`
(SyncService resends held messages), `:807-815` (ID enters
`_resentHeldPendingIds`), `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:361-365`
(UI projects cached as online).
During relay reconnect, before a fresh `rooms` snapshot confirms the Pi room
exists, the app can render the room online, resend a held message to a
still-offline Pi room (relay drops it, app-side send succeeds), then suppress
retry when the room later becomes genuinely live. Cross-feature conflict between
reconnect hydration, held-message recovery, and transport projection.
**Fix:** invalidate live-room confirmation when transport leaves `StatusOnline`,
or track a connection-generation/snapshot epoch so cached rooms remain stale
until a fresh snapshot confirms them. Resend held messages only after
confirmation. Add a deterministic regression: live room → disconnect →
reconnect-to-relay-only → room stays stale, held message NOT resent → fresh
RoomsSnapshot confirms → message resends exactly once.

## Corrective follow-up

Material 1 is fixed by clearing `ConnectionManager`'s live-room confirmation set
when the transport leaves `StatusOnline`. Cached room metadata remains available,
but reconnecting to the relay alone now projects the room stale; only a fresh
room control snapshot can mark it live again. `SyncService` gates held-message
recovery on that current confirmation and revalidates both lifecycle identity and
room liveness after the transcript-store async read and before each send.

Deterministic controlled-completer/fake-channel coverage proves live room →
transport loss → held send → relay-only reconnect remains stale with no resend →
fresh `RoomsSnapshot` → original message id resends exactly once. Verification:
`flutter analyze lib test`, the focused connection/sync tests, and
`flutter test --concurrency=1` (758 tests) all pass.

### Material 2 — exit-42 `/new` contract unproved at the real daemon seam
`pi-extension/src/index.ts:2610-2612` (ACK → reset → scheduled exit),
`pi-extension/src/daemon/rpc_child.ts:265-266,413` (exit 42 omits `--continue`),
`pi-extension/src/daemon/supervisor.ts:604-609` (immediate respawn). Code is
coherent by inspection, but the child story
`feature-mobile-native-session-process-control-reconnect-verification:39-41,67-68`
explicitly required extension-side ACK-before-exit + successor identity/room
tests; its implementation only records code inspection (`:54-56`). The app test
uses a fabricated channel.
**Fix:** add deterministic TypeScript coverage proving: (1) daemon `session_new`
emits `action_ok` + resets state before scheduling exit 42; (2) `RpcChild`
records exit 42 + omits `--continue` exactly once; (3) `Supervisor` immediately
respawns without crash backoff; (4) successor preserves daemon room/config
identity while publishing fresh session identity.

### Corrective follow-up

Added deterministic extension and daemon seam coverage in
`pi-extension/src/extension.test.ts`, `pi-extension/src/daemon/rpc_child.test.ts`,
and `pi-extension/src/daemon/supervisor.test.ts`. The tests cover ACK/reset
ordering before the scheduled exit, exit-42 observation with one fresh-session
spawn, immediate respawn without crash backoff, and successor room/config
continuity with a fresh `session_id` room-meta publication. The epic remains at
`stage: review` pending aggregate-review closure.

### Epic-goal check
- Reconnect robustness: FAIL (stale room liveness resend race — material 1)
- `/new` handling: FAIL on verification (material 2)
- Dropped events: FAIL (app→Pi held-message reconnect race — material 1)
- Working/idle convergence: PASS
- Cross-feature coherence: FAIL (stale-liveness seam — material 1)
- Scope-boundary honesty: PASS
- Parked live-repro items: legitimate (need physical phone); but the
  stale-liveness race is statically demonstrable, not deferrable.
