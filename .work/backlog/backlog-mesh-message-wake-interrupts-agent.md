---
id: backlog-mesh-message-wake-interrupts-agent
created: 2026-08-03
updated: 2026-08-03
tags: [pi-extension, workflow]
---

# Inbound mesh messages wake/interrupt the agent — needs proper characterization

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
