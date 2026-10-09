---
id: bug-pair-delivery-nextup-nxuc
created: 2026-10-09
updated: 2026-10-09
tags: [pi-extension, mcp, relay, bug, claude-lane]
---

# Pair-only delivery failure: nextup resident ↔ nxuC (Claude lane) — both directions time out

Defect report from fleet-root (projects#2, msg id 01a121db-2c2d-763a-be8c-dec32bd7153f,
2026-10-09). Repro data below verbatim-ish; live operational impact — both nextup
lanes had routing decisions blocked on it.

**Symptom.** Peer-to-peer delivery between exactly two registrations fails
BIDIRECTIONALLY (agent_send → send-timeout / no ACK), while each delivers to
and receives from a third peer (fleet-root) normally:

- `/home/agent/projects/nextup@nextup` — pi resident, main checkout, herdr
  pane `wJ:p1`, fresh 1.0.4 process, idle + relay-green at test time.
- `/home/agent/projects/nextup/.claude/worktrees/mesh@nxuC` — Claude lane,
  registered via the `OUTPOST_PI_MCP_CWD` worktree workaround.

- nextup → nxuC: 6+ timeouts across two threads starting ~17:12Z Oct 9
  (before and after the lane's recovery from the dead-mesh-child wedge —
  the wedge was real but separate, fixed by a fleet-root lane reboot; the
  pair failure persisted after it).
- nxuC → nextup: two timeouts ~a minute apart (~12:07–12:08 local), resident
  verifiably idle/done with green relay.
- Control: fleet-root ↔ each of them: Delivered, multiple times, including
  immediately around the failing window.

**Suspect surface (per fleet-root):** v0.13.0 cross-room routing between a
main-checkout room and a CWD-workaround worktree registration — same family
as the name-scoped `acquireCwdLock` work. Alternative candidate: stale
per-peer sibling/membership cache on the nextup side pointing at a dead
nxuC registration (the wedge-era child), while fleet-root's cache is fresh.

**Control datapoint (outpost):** outpost ↔ nxuC full round trip WORKED at
2026-10-07T04:59Z under the then-live mesh child (pre-wedge), so the
defect is pair-specific, not nxuc-global.

**Repro:** agent_send nextup-resident → nxuC and reverse while both idle,
fleet-root (or outpost) as control. Timing details from fleet-root or the
nextup transcripts.

## Repro results (2026-10-09, commissioned via mesh)

Complete delivery matrix at test time (~18:1x–18:26Z):

| edge | result |
|---|---|
| outpost → nxuC | Delivered (+ round trip Oct 7 04:59Z pre-wedge) |
| nxuC → outpost | Delivered (ACK) |
| fleet-root → each | Delivered (incl. from its NEW unsuffixed registration) |
| each → fleet-root | Delivered |
| nextup → nxuC | **timed out ×6+ 17:05–18:15Z**, then **Delivered 18:14:58Z (inbound reached nxuC) and 18:26:14Z (repro ACK)** |
| nxuC → nextup | **timed out 18:08–18:12Z ×3**, then reply ACKed immediately at 18:14:58Z |

The pair healed at ~18:14:58Z — within ~2 min of the fleet-root pi being
TERMed (18:12:55Z, the 0.87.1 process) and relaunched on 1.0.4. Both
lanes were also freshly idle at that moment (both had just replied to
control pings).

**Hypotheses (open):**

- **H1 stale 0.87.1 peer poisoning** — the pre-update root pi sat in the
  broker since Oct 7 03:22Z; its v0.87.1-era registration/forwarding may
  have poisoned sibling/membership state for the nextup↔nxuC route until
  the peer left. NOTE: the simple variant (stale LEADER) is ruled out —
  broker leader pid 837253 (1.0.4-era resident) held broker.sock
  continuously since Oct 7 04:35Z, across both failing and healed windows.
- **H2 mid-turn/busy drops** — both lanes were mutually deep in long
  adjudication turns all afternoon (working the same blocked routing
  decisions); the only failing pair was the only mutually-mid-turn pair.
  Bounded MCP inbox (v0.13.0) refusing while claude isn't draining, or
  sender-side busy handling, would produce exactly this signature.
- **H3 MCP-child age** — resident's suggestion: defect reproduces only
  after the child has been alive a while. Weaker: current child (924883,
  up since ~17:0xZ) delivered fine at 18:26Z.

**Discriminating experiment (offered by the resident):** timed 2×2 probe —
sender idle vs mid-turn × receiver idle vs mid-turn — triggered by nxuC
starting a long adjudication turn, with outpost/fleet-root controls. Not
yet commissioned (operator decision); fleet-root relays pair traffic as
workaround in the meantime.

## Refinement (18:26–18:28Z): size × turn-state interaction

Resident's follow-up: at ~18:26Z a ~80-byte agent_send to nxuC DELIVERED;
~90 s later a ~1.8 KB send to the same address TIMED OUT, with no inbound
from nxuC in between. Sequencing matters: the first (small) delivery would
itself WAKE nxuC into a turn — so the large follow-up landed while the
receiver was mid-turn and not draining.

**Refined H2 (leading): bounded-inbox budget exhaustion during non-draining
turns, size-gated.** The MCP's `BoundedInbox` has a byte budget; `get_messages`
drains only at turn start. While claude is mid-turn the inbox doesn't drain,
and messages that don't fit the remaining budget are refused → agent_send
timeout. Small messages pass until the budget is nearly gone; large ones
fail first. This unifies: (a) the all-afternoon failure window (nxuC deep
in long turns → budget exhausted → even modest sends time out), (b) the
healing moment (freshly idle → drained inbox), (c) the 80B-passes/1.8KB-fails
pair 90 s apart, and (d) why sparse control sends from fleet-root/outpost
succeeded around failing windows (landed near turn boundaries / fit residual
budget). The "pair-specific" topology would then be a traffic-pattern
artifact — that pair was the only message-heavy mutually-mid-turn pair.

**Sharpest discriminator now (resident offered):** same-moment small-vs-large
sends during a known mid-turn window. Small delivers + large times out at
the same instant → size gate confirmed (H2-refined). Both fail → full
exhaustion. Both deliver → size irrelevant, revisit H1/H3. Cheaper and more
decisive than the original 2×2; still operator-gated.

## Peer input (fleet-root, 2026-10-09)

- **Keep the version-mix axis alive (H1′):** the 0.87.1 root was the one
  genuinely odd broker client until 18:12:55Z; if its registration
  participated in either room's routing table, pair-specific corruption is
  not impossible. H2′ explains the pair-specificity more naturally, but the
  busy-state probe does NOT discriminate version mix. Opportunistic watch:
  if any 0.87.x client ever rejoins the broker, does the pair degrade
  again? (No 0.87 clients should exist anymore — any reappearance is itself
  an incident.)
- **Fix-scope implication:** if busy-drops are confirmed as the mechanism,
  senders need retry policy (agent_send timeouts on a healthy route are a
  caller-visible contract change). Scope any fix story accordingly.
- Fleet-root supports commissioning the probe (defect pinned two lanes for
  an afternoon; mechanism determines whether retry policy is needed).
