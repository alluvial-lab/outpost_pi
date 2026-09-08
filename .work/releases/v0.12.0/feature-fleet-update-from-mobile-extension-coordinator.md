---
id: feature-fleet-update-from-mobile-extension-coordinator
kind: story
stage: done
tags: [pi-extension]
parent: feature-fleet-update-from-mobile
depends_on: [feature-fleet-update-from-mobile-wire-protocol]
release_binding: v0.12.0
gate_origin: null
created: 2026-09-07
updated: 2026-09-08
---

# Extension: fleet coordinator (update subprocess + self-arm + mesh broadcast) + sibling arm handler

Design element: Unit 2 of the feature body — read "Implementation Units /
Unit 2" for the FleetUpdateCoordinator signature, the phase-emission
ordering rule (status before any arm; self-arm LAST), the sibling
arm-restart mesh message + ack states, and the safety rails (existing
.hot-reload-enabled toggle, own-nonce armed files, settle-gated claims).

## Acceptance evidence

- Unit tests (injected fakes): success path phase order (`src/extension/
  fleet_update.test.ts` — updating emitted before the subprocess call,
  arming emitted after ack collection, armSelf the final action of the
  run); update failure → update_failed with output tail, no peer list /
  mesh request / self-arm; concurrent request → already_running (with the
  second request's update_id) and the gate reopening after the first run;
  ack table with armed/deferred(reason)/declined(reason)/no-ack(timeout +
  thrown) rows plus duplicate-roster collapse; mesh body is exactly
  `{kind: "outpost-pi.arm-restart", update_id}`; hung subprocess failed by
  the update timeout without arming; failing localPeers → empty arming
  table instead of blocking; update_failed detail truncated to 4000 chars.
- Sibling handler tests: arms when enabled and idle; stages the armed file
  and reports deferred+reason while a turn is active; declines with reason
  when disposed / toggle off / arm-file write failed (arm never invoked on
  the first two).
- Live lane on one VM: DEFERRED TO OPERATOR at deploy — this worker runs on
  the live pi fleet and must never restart/kill/arm a pi process or write
  live armed/claimed/marker files. The lane is: load the new dist (one full
  pi restart per the ESM bootstrap note), enable `/outpost-pi hot-reload
  on`, then trigger a fleet update from the app and observe the wrapper
  bounce across the fleet (the already-verified 2.3s-bounce rail).
- `corepack pnpm check:protocol && typecheck && test && build` green —
  65 files, 1145 passed, 3 skipped (pre-existing skips).

## Implementation notes

Reconciled the prior worker's uncommitted state (kept the coordinator
shape, dispatch wiring, and `_tryArmHotReload` refactor) and completed:

- `pi-extension/src/extension/fleet_update.ts` — FleetUpdateCoordinator
  (one run per process; emit `updating` before the subprocess; on failure
  emit `update_failed` and stop; collect sibling acks; emit `arming` with
  the per-peer table; `armSelf` LAST so the coordinator's own restart
  cannot orphan the report). Also hosts the sibling arm handler factory,
  the `outpost-pi.arm-restart` mesh predicate/body builder (single source
  for the mesh kind, shared with the interception in
  `command_surface/local_mesh_commands.ts`), and `localPeerAddresses` —
  the broker `list_peers` reply → local-only roster discriminator
  (structured `peers_detailed` without a `pc` label, legacy fallback
  without `:`), extracted from the join handler so the coordinator and the
  cross-PC bridge use one definition.
- Sibling interception in `local_mesh_commands.ts`: a well-formed arm
  request is answered synchronously with the handler's ack (declined
  when no handler is wired) and never reaches `deliverMeshMessage`, so it
  cannot wake the agent. The sibling writes only its OWN nonce-bound armed
  file via the existing `_tryArmHotReload` path (daemon mode and the
  `.hot-reload-enabled` owner-only-file toggle both decline); the existing
  agent_settled gate (`_maybeRestartForExtensionReload`) owns the actual
  restart, making a busy sibling "deferred" the rolling-restart semantics.
- `index.ts` wiring: client-message dispatch for `fleet_update` (after the
  session gate; `handleRequest(msg.id)` correlates the run to the request
  id), status events broadcast to all attached owners, self-arm through
  the same `_tryArmHotReload` used by the interactive command, and
  `hasActiveWork` = turn projection working OR background activity
  (matching the restart-gate deferral).
- Discoveries (judgment calls):
  - `pi update --all` replaces the design's `pi update` + `pi update
    --extensions` pair — one subprocess updates the pi binary and all
    installed packages (verified via `pi update --help`). The child also
    gets `timeout: DEFAULT_FLEET_UPDATE_TIMEOUT_MS` + SIGKILL so a hung
    update cannot outlive the coordinator's race deadline.
  - v1 local-only scope is enforced coordinator-side: `localPeers` filters
    the aggregated roster to broker-local addresses. The sibling side does
    not additionally verify sender locality — matching the design's trust
    model (paired mesh peers, arm gated on the host toggle) and the
    existing cross-PC agent-message authority; noted for any future
    cross-PC fleet extension.
  - Daemon pis decline sibling arms ("hot-reload disabled") and a daemon
    coordinator's self-arm is a no-op (supervisor owns its restart), so a
    daemon-coordinated run updates + restarts siblings but picks up its
    own new binary at the next supervisor cycle.
- Safety: no code path in this story signals, kills, or restarts any
  process; the only new file writes are the process's own armed file
  through the pre-existing owner-only `wx`-guarded path.

Verification:

- `cd pi-extension && corepack pnpm check:protocol` — passed (no drift).
- `cd pi-extension && corepack pnpm typecheck` — passed.
- `cd pi-extension && corepack pnpm test` — passed (65 files, 1145 passed,
  3 skipped).
- `cd pi-extension && corepack pnpm build` — passed.

## Ordering constraints

Depends on the wire-protocol story. Live lane requires one pi restart to
load the new dist (ESM) — the bootstrap note in the feature's Risks.
