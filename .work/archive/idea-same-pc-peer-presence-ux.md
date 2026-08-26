---
id: idea-same-pc-peer-presence-ux
created: 2026-07-02
updated: 2026-07-02
tags: [mesh, ux, design-exploration]
status: superseded
superseded_by: operator discard 2026-08-26 (groom) — see body note
---

# Same-PC cross-cwd peer presence UX — how should it flow?

## Retired (operator discard, 2026-08-26)

The triggering annoyance (sibling projects appearing noisily) was not
recollectionable at groom time; the UX questions below were never answered
and the operator chose to discard rather than park indefinitely. The
entanglement analysis (leader consumes `peer_joined`/`peer_left` for the
cross-PC inventory push, `broker_remote.ts:304`) is retained in this body —
it constrains any future presence-scoping work.

## Why this was parked

Observed live: two pi sessions on one PC in different cwds
(`remote_pi` and `patchbay`) show up noisily against each other. The operator
asked to unpack the *UX* of how same-PC peer presence should flow across
project boundaries, rather than just "make it quieter." This is a
design-exploration capture for scope/design time — no kind, stage, parent, or
decomposition decided yet.

## Current situation (grounded, from the running system)

- One machine-wide broker. All local UDS peers register into it regardless of
  cwd. Address form is `<cwd>@<name>` (plan/38) — cwd is first-class on the
  wire and in `peers_detailed`.
- **Work channel is already cwd-scoped.** `broker.ts` `_resolveTargets`:
  `broadcast` only reaches peers with `p.cwd === sender.cwd`. So cross-cwd
  announcements don't bleed. This is fine and should be preserved.
- **Roster is global.** `list_peers` returns the full machine roster via
  `_allPeerInfos()` — every peer in every cwd. That's why `patchbay` appears
  in `remote_pi`'s peer list and vice-versa. Informational + pull-based, but
  cross-project clutter.
- **Presence events are global.** `_broadcastSystem` sends `peer_joined`/
  `peer_left` to every peer regardless of cwd (no cwd filter, unlike
  `broadcast`). On receipt, each peer fires `_refreshSessionPeerCount` → a
  `list_peers` round-trip + footer refresh
  (`local_mesh_commands.ts:297`). So a sibling project's start/stop causes
  broker round-trips and footer re-renders in unrelated projects.

## The UX questions to unpack at design time

These are open questions, not answers:

1. **What's the right default view of "peers"?** Same-project only (same cwd /
   shared path prefix), with an explicit `--all` for the whole machine? Or
   is machine-wide the honest default because there's only one broker?
2. **Should presence events cross project boundaries at all?** If a peer in
   `/home/agent/projects/patchbay` joins, does the agent in
   `/home/agent/projects/remote_pi` need to be woken/refreshed? Probably not
   for *work* — but it may matter for *awareness* ("is anyone else coding on
   this box right now").
3. **What does the agent *do* with same-PC cross-cwd peers?** Today: nothing
   actionable (broadcast can't reach them; `agent_send` works but is rarely
   the right move across projects). Is the roster noise pure cost, or is
   there a latent capability (cross-project ask, shared context) worth
   keeping visible?
4. **Operator mental model.** "patchbay is another pi session on this PC" —
   is the expected model "other agents on my machine are ambient" (so
   presence is a feature) or "other projects are noise" (so presence should
   be suppressed by default)? The answer drives the whole design.

## Entanglement that constrains the solution space (do not lose this)

The presence broadcasts are **not purely cosmetic** — the leader (which may
live in a *different* cwd) consumes `peer_joined`/`peer_left` to call
`onLocalPeersChanged` → push `peers_update` to cross-PC siblings
(`broker_remote.ts:304`). If presence broadcasts were naively cwd-scoped, the
leader would miss other-cwd joins and the cross-PC inventory would go stale.
Any UX-driven scoping must **separate "cross-PC inventory tracking" from
"peer-facing presence"** first, or route inventory through a different signal.

## Candidate directions (raw, for design time — not decisions)

- **Client-side roster filter** — `list_peers` agent tool + `remote-pi peers`
  CLI default to same-project (same cwd / shared path prefix), `--all` for the
  full machine. No protocol change; `peers_detailed.cwd` already on the wire.
  Cheapest; kills the roster noise the agent actually sees but leaves event
  churn.
- **Split presence from inventory** — broker keeps a full local inventory
  signal for the leader/cross-PC path, but scopes the *peer-facing*
  `peer_joined`/`peer_left` to same-cwd. Medium cost; requires untangling the
  two consumers of the broadcast.
- **Per-project broker** — full isolation, but breaks the single-leader-
  hosts-cross-PC-bridge model. Large cost; likely overkill.

## References

- `pi-extension/src/session/broker.ts` — `_resolveTargets` (cwd-scoped
  broadcast), `_broadcastSystem` (global presence), `_allPeerInfos` (roster).
- `pi-extension/src/extension/command_surface/local_mesh_commands.ts:297` —
  presence-event handler that triggers the `list_peers` round-trip + footer
  refresh.
- `pi-extension/src/session/broker_remote.ts:304` — `onLocalPeersChanged`,
  the cross-PC inventory push fed by presence broadcasts.
- `pi-extension/src/index.ts:431` — `_refreshSessionPeerCount`.
- `.pi/remote/skills/agent-network/SKILL.md` — the agent-facing presence model
  (pull-based, no join/leave wake).
