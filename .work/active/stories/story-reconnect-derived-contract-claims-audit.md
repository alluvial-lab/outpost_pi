---
id: story-reconnect-derived-contract-claims-audit
kind: story
stage: drafting
tags: [app, pi-extension, relay, docs, observability]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on:
  - idea-mobile-drop-slow-recovery
  - idea-mobile-outgoing-message-swallowed
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-19
split_from: feature-contract-gap-audit
---

# Audit reconnect-derived contract claims after the physical drop trace

## Brief

This is the genuinely reproduction-dependent residue split from
`feature-contract-gap-audit`. After the physical-phone wifi↔cellular/WireGuard
drop run has joined the app, relay, and extension traces, audit only the
attributed reconnect findings for durable contract impact.

The child checkpoints in `depends_on` own the live evidence. If they identify a
local code defect or external network delay, record that disposition and make no
protocol claim. Amend `PROTOCOL.md` or `docs/ARCHITECTURE.md` only when the trace
proves a current invariant or exposes a genuine contract gap.

## Acceptance criteria

- [ ] Every reconnect claim cites the joined live trace or the terminal item
      that contains it.
- [ ] Inconclusive observations and target-state aspirations are not written as
      current behavior.
- [ ] Local app/relay/extension bugs route to focused implementation work rather
      than expanding this prose audit.
- [ ] Any durable edit rewrites current-state prose in place.
