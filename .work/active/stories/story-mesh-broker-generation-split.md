---
id: story-mesh-broker-generation-split
kind: story
stage: implementing
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

## Design v2 (post cross-model advisory, 2026-10-10 — supersedes v1 G3/G4 rendezvous mechanics)

An `openai-codex/gpt-6-astra` fresh-context review (xhigh) adjudicated v1
with 12 findings; blocker + majors adopted, verdict "right direction, not
sound as specified". The v1 goals, G1/G2/G5/G6, compat posture, and
client-side semantics stand; the rendezvous mechanics change:

**R1 — Symlink rendezvous over generation-unique bind targets (replaces
blind unlink entirely).** A new-code leader binds a unique sibling
`broker-<gen>.sock` next to the rendezvous and ATOMICALLY publishes
`broker.sock → broker-<gen>.sock` via tmpsymlink + `rename()` (rename
atomically replaces legacy socket files, dead files, and rival symlinks —
there is no unlink window and no unlinked-live-listener state, ever).
Adopted because the review REPRODUCED on this host (Node 24.21) that
libuv `server.close()` implicitly unlinks the bind path even when a
successor has since rebound it — v1's demote-close would have deleted the
successor's path (blocker finding 1). With unique targets, closing a
superseded broker can only ever unlink its OWN file. Post-publish VERIFY:
readlink(rendezvous) must equal our target; if a racer renamed over us we
demote ourselves (destroy our server — unlinks only our file — and follow
the winner). Racer collision becomes benign last-writer-wins + demote,
which IS the fencing operation (finding 2: delayed ECONNENT/REFUSED
handlers can no longer unlink a live owner — there is no shared-file
unlink path at all; a racer replacing the rendezvous is a supersession
the old owner detects, not a corruption).

**R2 — Pointer-based supersession (fixes baseline-acquisition race).**
The broker's identity is its own unique file, established at ITS bind;
supersession = readlink/lstat(rendezvous) no longer resolving to it
(symlink elsewhere, plain socket file = legacy rebound, or missing). No
stat-at-construction baseline (finding 3). Missing rendezvous after
ownership = orphaned, still demotes ("orphaning, not proof a successor
exists" — adopted wording).

**R3 — Staged make-before-break (fixes identity churn + shared-buffer
races).** Re-resolve candidates get their OWN socket + buffer + ack
listener (staged), promoted atomically after register_ack. The path's
generation is learned from the observer probe BEFORE registering: same
generation as current + connection alive → RETAIN current connection
(no `#N` churn — finding 4); different → register new, then destroy old.
Late callbacks fenced against connection revision + disposal (finding 4).

**R4 — Recovery instead of throw.** Exhausted-inconclusive elections no
longer permanently wedge the session mesh-less (finding 7): bounded,
jittered background retry (cap 30s) preserves today's connection until a
replacement registers. A frozen broker may accept kernel connects yet
never answer registration — connect success is not application health,
so no recovery path unlinks or republishes on timeout evidence alone.

**R5 — Claims narrowed (findings 5, 9, 10, 12).** Mixed-version: new-code
islands always self-dissolve; LEGACY-broker islands persist until that
broker restarts (rollout's final sweep covers it) — fleet convergence
needs the sweep, not just the fix. "≤20s" is an operating target under
stated assumptions, not a bound. `unknown_peer` means "not routed by this
broker at this instant"; MCP wrapper gets the formatting case; `request()`
still swallows broker ACKs by design. Audit chain is broker-local during
splits — diagnostic evidence, not a globally ordered ledger; lifecycle
lines carry generation + pid; audit never gates demotion. G1's uuidv7 is
an OPAQUE equality token — ordering is never load-bearing (finding 11).

**R6 — Delivery-loss window accepted (finding 8).** Supersession teardown
may drop in-flight intra-island envelopes; `received` retains its existing
meaning (broker wrote to the peer socket), not end-to-end processing. All
accepted sockets — observers included — are tracked and destroyed; the
broker is marked retiring and host/bridge ownership revoked before async
teardown; close is idempotent and cannot clear a successor.

**Orphan GC.** At bind, sibling `broker-*.sock` targets not referenced by
the rendezvous and older than 1h are unlinked (crashed brokers' files). A
frozen broker losing its file is unaffected operationally (its check
reads the rendezvous, not its own file; only its close-time unlink no-ops).

**Named pipes (Windows):** indirection disabled; direct-bind path keeps
v1's honest-probe rules that still apply. The fleet is Linux.

Legacy `tryConnect` keeps its null-means-no-answer contract (escalated
3.5s worst case); cwd_lock's destructive consumption of it remains the
documented follow-up (finding 6 adopted as scope boundary).

## Design (chosen 2026-10-10 design pass; supersedes "fix directions" above — D1→G1/G4, D2→G2, D3→G3, D4→G6)

Goal: no persistent broker-generation split can survive longer than a small
converge bound, and the election never *creates* a split through a blind
unlink. All wire changes are additive envelope-body fields (no envelope
format change), safe across mixed v0.13.x/trunk fleets.

**G1 — Generation identity.** Broker mints `generation = uuidv7()` at
construction and includes it additively in `register_ack`, both
`list_peers_reply` surfaces (registered + observer probe), and
`peer_joined`/`peer_left` broadcasts. `SessionPeer` records the generation
it registered under (undefined against a legacy broker → detection off).

**G2 — Client divergence watcher.** `SessionPeer` probes `sockPath` every
10s (injectable) with the existing unregistered `list_peers` observer
probe (zero mesh perturbation — that surface already exists for the CLI):

- reply generation ≠ mine → I'm on a stale island → guarded re-resolve
  (`_joinOrLead` under a `_rejoining` latch; old socket destroyed after
  re-register; `onReconnect` fires so MeshNode re-attaches the bridge and
  the roster cache refreshes).
- probe cannot connect after 2 consecutive ticks → path has no listener
  → same re-resolve (orphaned islands dissolve; the normal failover path
  already covers "my own broker died").
- reply lacks generation (legacy broker) → passive (no detection, no harm).
- an `unknown_peer` NACK (G5) triggers one immediate probe (fast-path).

**G3 — Honest election primitives** (`leader_election.ts`). New tri-state
`probePeer(path, budgets)`: `alive` (connected), `dead` (definitive
ECONNREFUSED/ENOENT — error event, not a timeout), `inconclusive` (no
event after escalating budgets 500ms → 3s; the timer-vs-callback race
cannot prove death). `joinOrLead` becomes: alive → follower; dead →
unlink+bind (the only unlink path); inconclusive → backoff+retry, and on
exhaustion **throw** — never unlink or bind on an unproven death.
`tryConnect` (consumed by `cwd_lock` and the daemon supervisor probe)
keeps its signature/semantics but internally escalates 500ms → 3s on the
timer path, narrowing its blind-unlink consumers' race window for free.
`cwd_lock`'s own lock-steal-on-false-death semantics are deferred to a
follow-up note (a false refusal is as bad as a stolen lock there; the
tri-state primitive is available to it after this story).

**G4 — Broker supersession self-check.** Broker constructed with
`sockPath` records `stat()` dev+ino of its bound path and re-checks every
5s (injectable). Path gone or inode changed → superseded: audit
`{event:"superseded"}`, broadcast `{type:"generation_superseded",
generation}` to island peers, destroy all peer sockets (every client —
new and legacy — re-runs its failover `joinOrLead` and lands on the live
path owner), close the server, notify the hosting `SessionPeer` (clears
broker/role so its loopback-close failover rejoins as a follower — the
leader demotes itself). Disabled on named-pipe platforms. This makes
splits caused by legacy blind-unlink racers **transient** (~5s) during
rollout, converging onto whichever broker owns the path regardless of
its code version.

**G5 — `unknown_peer` NACK (F4).** Unicast to an unregistered address:
NACK `{status:"unknown_peer", target}` + audit line instead of silent
drop; `_formatAck` case tells the sender the peer isn't on this broker
(roster may be split or peer offline → check `list_peers`). Broadcast /
multicast unchanged. Legacy senders degrade through the string-typed ACK
default case (same pattern the re-UUID story qualified).

**G6 — Lifecycle audit.** `{event:"bind"|"superseded"|"close", generation}`
and `{event:"register"|"unregister", address}` lines through the existing
chained audit writer — tonight's diagnosis needed `/proc`+`ss` forensics
because none of this was recorded.

**Convergence bound.** split detection ≤ max(watcher 10s, supersede poll
5s) + election retry tail (~2.6s) + probe cost ≈ **≤ 20s steady-state**;
rollout worst case adds one 5s supersede cycle per legacy-racer event.

**Compatibility matrix.** new client + legacy broker: no generation →
watcher passive, behavior as today. Legacy client + new broker: extra
body fields ignored; supersession close → legacy failover rejoins the
path owner. Legacy racer rebinds over a new broker → detected in ≤5s,
island dissolves onto the racer's broker (unified, whatever its version).
New clients never unlink without definitive death. No paired deploy
required.

**Test plan (deterministic via injected intervals/budgets):** election
honesty (tiny budgets → throw-without-unlink; definitive-death → unlink+
lead; live leader + exhausted-inconclusive → path untouched); generation
fields on all three surfaces; supersession (rebind racer → broadcast +
close + demote + audit); watcher heal (stale island rejoins path owner;
orphan path → re-resolve; legacy broker → passive); convergence sweep
(kill leader, staggered restarts → one broker, full roster within bound);
`unknown_peer` NACK + formatting; existing suites stay green
(`typecheck`/`test`/`build`).

## Scope / acceptance (to finalize in design)

- [ ] Full-sweep restart (all fleet sessions incl. broker host) converges
      to one generation + full roster within the settle bound (≤20s
      steady-state at production intervals; proportionally faster at
      injected test intervals)
- [ ] Superseded-generation client detects divergence and re-registers
      (watcher path and unknown_peer fast-path) without operator action
- [ ] Election never unlinks without definitive proof of death
      (inconclusive probes abort, never unlink/bind); `tryConnect`
      consumers (cwd_lock, supervisor probe) keep semantics with a
      narrowed race window; cwd_lock's own steal-on-false-death semantics
      deferred with a follow-up note
- [ ] Broker supersession self-check dissolves stale islands (broadcast
      + close + leader self-demotion) within one poll cycle
- [ ] Broker register/supersede/bind/close lifecycle lands in the audit
      chain; unicast to unknown peers NACKs `unknown_peer` (audited)
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
