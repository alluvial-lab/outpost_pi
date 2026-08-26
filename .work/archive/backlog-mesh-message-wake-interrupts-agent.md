---
id: backlog-mesh-message-wake-interrupts-agent
created: 2026-08-03
updated: 2026-08-26
tags: [pi-extension, workflow]
status: superseded
superseded_by: operator discard 2026-08-26 (groom) — see body note
---

# Inbound mesh messages wake/interrupt the agent — needs proper characterization

## Retired (operator discard, 2026-08-26)

Groom spike confirmed presence events (`peer_joined`/`peer_left`) never reach
the agent-turn path — they only refresh roster counts/footer
(`local_mesh_commands.ts:300`). The only inbound wake is real peer→agent
messages (`_deliverMeshMessageToAgent`, `index.ts:2235`), which now batch
while busy and flush once at `agent_settled` — landed after this 2026-08-03
capture. Operator could not recall the disruption and suspects legacy
behavior; discarded rather than kept open on an uncharacterized memory.
Re-capture with specifics if it recurs.

## Reminder (sparse by design — not yet fully described)

Inbound agent-network (mesh) peer→agent messages are delivered via
`_deliverMeshMessageToAgent` (`pi-extension/src/index.ts`), which injects the
message and **triggers the agent's turn**. Operator sense (2026-08-03): these
mesh-driven wake-ups can feel disruptive / distracting (e.g. peers coming
online and the agent getting pulled into turns) — but the exact problem isn't
characterized yet.

**Needs investigation before scoping:** confirm what's actually bothersome —
is it (a) the turn being triggered at all on inbound mesh messages, (b) the
timing/frequency (no batching/coalescing), (c) the TUI getting interrupted
mid-task, (d) something about presence vs message delivery being conflated, or
(e) a different surface entirely? Until that's pinned down, this is a reminder,
not a spec.

## Distinct from

The transcript-rendering question for these same messages (Q2 of
`feature-canonical-transcript-timestamp-ownership`, decided **authoritative** —
how the app *displays* them) is separate from this wake/interruption *behavior*.
Don't conflate the two.
