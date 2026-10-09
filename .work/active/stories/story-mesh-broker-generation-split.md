---
id: story-mesh-broker-generation-split
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-09
updated: 2026-10-09
---

# Mesh broker generation split: mass-restart election races partition the local mesh

## Brief

The local agent-network broker is hosted by whichever session wins a UDS
leader election (`session/leader_election.ts` `joinOrLead`: connect-probe,
else stale-unlink, else bind). During a fleet-wide restart sweep, that
election races itself into **multiple live broker generations**: sessions
that connect during a rebind window register with whichever generation owns
`broker.sock`'s dentry at their connect moment, established UDS connections
keep serving superseded generations forever, and nothing ever reunifies
them. Symptom surface:

- Partitioned rosters — `list_peers` shows a fraction of the fleet (the
  incident: 9 of 17) while every session process is alive and connected.
- Cross-island unicast **silently drops** (broker: "no such peer → silent
  drop") — senders see the opaque 5s `sendWithAck` timeout,
  indistinguishable from peer-offline (same observability gap class the
  re-UUID story just closed on the parse path).
- Silent partial-mesh operation: each island believes it is the mesh.

This recurs on **every** fleet-wide sweep that includes the current broker
host — i.e. every fleet bounce — until fixed at the source. The operator's
fleet runs 16 residents + fleet-root + a Claude-lane MCP peer; tonight's
19:15Z sweep (13 sessions) partitioned it into three generations within
~40 seconds of staggered starts.

## Incident record (2026-10-09, live-diagnosed)

Post-sweep state, established by pairing `/proc/net/unix` accepted-socket
inodes with client-socket peer inodes via `ss -xn` (every session alive and
connected — just to different brokers):

| Broker host (generation) | Registered clients |
|---|---|
| `nextup` (Oct-6 session, pre-sweep leader — never bounced) | fleet-root, outpost_pi, orogen, personal-coordination, table, animal-future, proving-grounds, nxuC-mesh-server (9) |
| `SNC/platform` (sweep session) | SNC, video, org, voxel-client-audio (5) |
| `SNC/games/library` (sweep session) | ARD, agent-workspace (3) |

Remediation executed live at 19:33Z (marker hot-reload of the two orphan
broker hosts — idle, transcripts preserved) re-formed the mesh as **two**
islands of 8+8: the path generation moved to a broker hosted by
voxel-client-audio; the pre-sweep leader (nextup) still held its island via
live accepted sockets. Full unification was deferred to nextup's scheduled
fresh bounce (its death drops the last superseded generation's connections;
all clients then re-resolve the path onto the live generation — no race,
because the path target survives).

Secondary observation: the Claude-lane MCP child (`nxuC`) lost its broker
connection during the remediation churn and only reconnects on demand —
cross-island silence from that lane is this defect's shadow, not a bug in
the lane.

## Mechanism (code-level)

`joinOrLead(sockPath)` per attempt:

1. `existsSync(sockPath)` → `_tryConnect` with **`PROBE_TIMEOUT_MS = 500`**.
2. Probe failure (timeout or ECONNREFUSED) → `_removeStaleSock` —
   **unlinks the socket file without proving its listener is dead**.
3. `_tryBind` → first binder becomes leader; EADDRINUSE losers retry
   (30–100ms jittered backoff, 20 attempts) and land as followers.

Failure chain under mass restart:

- **F1 (false death):** a slow/overloaded-but-alive broker misses the 500ms
  probe; the prober declares it dead.
- **F2 (unlink a live listener):** `_removeStaleSock` removes a path whose
  bound listener is still alive. Unlink does not kill a UDS listener — its
  inode and all accepted connections keep working; it is merely unreachable
  through the path. The next binder creates a fresh dentry → new generation.
- **F3 (no reunification):** clients of a superseded generation hold live
  connections and a valid register; nothing carries a generation identity,
  so neither broker nor client can detect the split. The broker's
  `name → connection` map is per-generation; there is no path-liveness
  re-check, no takeover notice, no fencing of stale registrations.
- **F4 (silent drop across islands):** broker routing has no such peer →
  silent drop; the sender's 5s timeout is indistinguishable from
  peer-offline.

Mass sweeps amplify F1/F2: staggered starts × jittered election retries ×
concurrent stale-unlink produce several rebinds within seconds (three
generations in ~40s tonight; a fourth during remediation).

Same primitive, lower stakes: `cwd_lock.ts` reuses
`tryConnect`/`tryBind`/`removeStaleSock` for the per-folder lock — the
F1/F2 race exists there too, though contention is per-folder rather than
fleet-wide.

## Fix directions (design input, not yet chosen)

- **D1 — Generation fencing at the path target (server-side):** the broker
  carries a generation id (bind epoch: monotonic counter or launch UUID)
  stamped into register acks, `list_peers` replies, and `peer_joined`
  broadcasts. A rebinding broker refuses/ages-out registrations older than
  its own bind epoch; clients learning of a newer generation re-resolve the
  path and re-register.
- **D2 — Client-side divergence detection + re-resolve:** on send-timeout
  (the silent-drop signature) or a periodic roster probe, the client
  re-runs `joinOrLead` (fresh connect/register) instead of trusting the
  established connection; a generation-id mismatch in any reply triggers
  the same. Turns "is my broker still the broker?" into a cheap invariant
  rather than an incident.
- **D3 — Make stale-unlink honest (fix F1/F2 at the root):** before
  unlinking, require positive evidence the listener is dead — longer/confirmed
  probe, or a bind-claim sidecar (owner pid + boot id) checked against
  `/proc` liveness, so a live broker's path is never unlinked. Applies to
  `cwd_lock` as well via the shared primitive.
- **D4 — Observability:** broker lifecycle events (bind epoch, register /
  deregister, generation supersede) into the existing audit chain.
  Tonight's diagnosis needed `/proc` + `ss` forensics precisely because
  register lifecycle is logged nowhere.

D1+D2 are complementary (server fences, client re-resolves); D3 shrinks the
race window; D4 makes the next incident legible. D2 alone converges the
fleet even if a split still forms; D1 alone heals it on next contact.

## Repro (characterized)

1. ≥3 pi sessions in distinct cwds (or a scripted `joinOrLead` trio).
2. TERM the current broker host while restarting the others staggered
   (200ms–1s apart) — or freeze it (SIGSTOP) so probes time out while it
   stays alive, then start a new session.
3. Observe: `ss -xn` shows two accepted-socket owners for
   `sessions/local/broker.sock`; the unregistered `outpost-pi peers`
   (read-only probe) returns one generation's roster; a cross-pair send
   times out at 5s.

Convergence assertion for the acceptance lane: after a full-sweep restart,
exactly one broker generation holds live clients, every session's roster
shows the full fleet, and cross-pair delivery ACKs — bounded by a settle
constant (order: election backoff tail, seconds).

## Scope / acceptance (to finalize in design)

- [ ] Full-sweep restart (all fleet sessions incl. broker host) converges
      to one generation + full roster within the settle bound
- [ ] Superseded-generation client detects divergence and re-registers
      (send-timeout path and/or probe path) without operator action
- [ ] A live broker's path is never unlinked (claim/liveness check before
      stale-removal); cwd-lock primitive inherits the fix
- [ ] Broker register/supersede lifecycle lands in the audit chain
- [ ] Mixed-version fleet (v0.13.x peers + trunk) degrades safely during
      rollout — older clients must not wedge, per the re-UUID story's
      paired-deployal lesson

## Postscript: second + third live manifestations (2026-10-09 20:33–20:35Z)

The parked story predicted recurrence on every fleet-wide sweep; it recurred
twice more within the hour, with one mechanism-sharpening surprise:

- At the old nextup broker host's death (scheduled fresh bounce, 20:33Z),
  its 7 island clients re-ran `joinOrLead` concurrently; the first finisher
  (proving-grounds) false-deathed the then-path broker (voxel's, LIVE and
  idle) and rebound → two generations again.
- A race-free sequential remediation (single-client marker hot-reloads,
  one connector at a time) ALSO lost the first coin flip: ARD's fresh
  process alone false-deathed the healthy idle path broker (proving-
  grounds') and bound its own generation → three generations (ARD:1 owning
  the path; proving-grounds:8+nxuC; voxel:7).

**F1 is therefore not load-dependent**: even a single freshly-started
connector can false-death an idle healthy broker. Plausible micro-mechanism
for the design pass to verify: in `_tryConnect` the 500ms settle timer can
fire before the queued `connect` success callback when the fresh process's
event loop is still busy initializing — a timer-vs-callback race in which
the kernel-level connect may have SUCCEEDED yet still be treated as death,
followed by unlink (F2) of a listener that just accepted that very probe.
Empirical cluster pattern tonight: in every rejoin cluster, the FIRST
`joinOrLead` finisher rebound over a live broker; later finishers followed
the new path successfully. Consequence: bounce-based reunification is a
per-restart coin flip — convergence should ride the story fix (D1–D4),
then one final sweep.

Fleet state at park time: all sessions on the fixed dist; roster split
three ways (islands internally healthy, cross-island sends silently drop);
active coordination quad (fleet-root, outpost_pi, nextup, nxuC) shares one
island.

## Provenance

Fleet incident 2026-10-09 19:15Z (13-session sweep) → 19:26Z fleet-root
reboot + delegated roster check; live diagnosis by the outpost_pi resident
(UDS inode pairing, broker read-only probes, restart-loop logs); remediation
executed 19:33Z (orphan broker hosts hot-reloaded); unification via nextup
fresh bounce followed. Fleet-root direction to park as a story with fix
directions: msg id 01a12229-986b-7116-9164-650b7fabefc7 (2026-10-09).
