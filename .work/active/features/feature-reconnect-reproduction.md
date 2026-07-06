---
id: feature-reconnect-reproduction
kind: feature
stage: drafting
tags: [app, pi-extension, relay, bug, observability]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
---

# Reconnect reproduction & attribution (observation workstream)

## Brief

The 2026-07-02 live drop-test bug cluster is a set of **observation gaps, not
design gaps** — most bugs are explicitly unreproduced or have unconfirmed
contributors. The original epic framed these as "blocked on a reconnect
state-machine contract"; the reframed thesis is that they should **feed** the
contract from evidence, not be blocked-on or unblocked-by it. The
mobile-remote-coding skill lists the target states
(`connected idle / working / reconnecting / offline / stale-unknown`), but
those are the *target*; the contract should be updated **after** the trace
tells which state machine is actually wrong.

## Scope

For each item: reproduce with the cross-side instrumentation from
`feature-cross-side-observability` (phone ring log + relay logging +
correlation key), attribute the failure to a specific surface, then decide
whether it's app backoff / relay duplicate-connection cleanup / extension
peer-offline consumption / send queue / UI projection — or a genuine
contract gap.

### Code-actionable items (scoped as stories, no live repro needed)

- `idea-extension-pumps-into-dead-app-peer` → `story-extension-suspend-
  fanout-on-peer-offline` (CONFIRMED gap: the relay emits `peer_offline` but
  the extension doesn't consume it; `OwnerMultiplexer.broadcast` pumps into
  the void until turn end). Implementing now.
- `idea-mobile-user-message-not-delivered-timeout` → `story-verify-resumed-
  session-echo-gate-rejection` (verify-then-decide: static-trace whether the
  resumed-session SessionGate race is structurally possible, then fix or
  re-scope). Static trace in flight.

### Live-repro-only items (instrumentation in place; attribute on next drop test)

These require a physical phone + real wifi↔cellular network drops and cannot
be reproduced in the dev environment. The cross-side instrumentation
(`story-app-capture-routing` ring log + `story-relay-duplicate-auth-
supersession-log` + correlation key) is now in place to attribute them
deterministically on the next live drop test:

- `idea-mobile-drop-slow-recovery` — ~5 min end-to-end recovery on wifi→5g.
  The relay supersession log (`story-relay-duplicate-auth-supersession-log`,
  done) directly addresses this: it confirmed the relay does NOT eagerly
  close the old duplicate conn, so the supersession→close gap is measurable
  and the ~5min window is likely relay detection speed, not app backoff.
  The app ring log's `conn-status` (retrying/delayMs) + `conn-channel-lost`
  (stale) will confirm on the next repro.
- `idea-mobile-drop-half-open-tcp` — no clean FIN on network switch;
  duplicate-connection takeover by ping timeout vs eager supersession.
  ANSWERED by `story-relay-duplicate-auth-supersession-log`: the relay does
  NOT eagerly supersede — it waits for ping timeout. Behavior change (eager
  close) deferred to a follow-up, now that the observation is in place.
- `idea-mobile-outgoing-message-swallowed` — outgoing user message not
  delivered, not surfaced. NOT reproduced server-side. The ring log's
  `msg-send` (with the message id) + the extension's `app user_message id`
  + the relay's `env_id_tail` will locate the drop on the next repro.

- `idea-mobile-drop-slow-recovery` — ~5 min end-to-end recovery on wifi→5g.
  Unconfirmed contributors (app backoff, wireguard bring-up, app state
  machine). Needs phone-side timing to attribute.
- `idea-mobile-drop-half-open-tcp` — no clean FIN on network switch;
  duplicate-connection takeover by ping timeout vs eager supersession
  unconfirmed.
- `idea-extension-pumps-into-dead-app-peer` — extension streams into a gone
  app peer for ~2 min after disconnect. `peer_offline` emission/consumption
  unconfirmed (the type exists in the generated protocol; no consumer
  located on the extension side).
- `idea-mobile-outgoing-message-swallowed` — outgoing user message not
  delivered, not surfaced. NOT reproduced server-side.
- `idea-mobile-user-message-not-delivered-timeout` — "not delivered" badge
  (20s no-echo timeout). Hypothesis: resumed-session `SessionGate` rejection
  silently drops the echo. UNCONFIRMED.

## Why this is a feature, not a story

Each item needs its own reproduction pass and may surface a distinct root
cause (or confirm a shared one). The attribution is the work; the contract
follows. Grouping them keeps the workstream coherent and ensures the
observability dependency is explicit rather than re-derived per bug.

## Unblocks

- The reconnect portion of the contract gap audit
  (`feature-contract-gap-audit`) — once attributed, genuine invariant gaps
  get pinned; non-gaps get closed as code fixes via the design family.

## Out of scope

- The contract prose itself (`feature-contract-gap-audit`).
- The observability infrastructure (`feature-cross-side-observability`) —
  this feature consumes it.
- `idea-mobile-conflates-transport-and-agent-state` — misfiled under the old
  reconnect contract; its own analysis shows it's a UI-projection/turn-phase
  question, not a reconnect state machine. Routes under turn-state/UI
  projection work (consumes released `epic-bold-turn-state-machine`).

## Open decisions (per item, after reproduction)

- Is the failure app-side (backoff, send queue, session gate), relay-side
  (duplicate-connection cleanup, ping timeout), or extension-side
  (peer-offline consumption, dead-peer pumping)?
- Does the failure reveal a genuine state-machine contract gap, or a concrete
  code defect that a contract won't help?
- For `idea-extension-pumps-into-dead-app-peer`: confirm whether the relay
  emits `peer_offline` to the extension on app socket close, and whether the
  extension handles it. If not, the fix is to surface app-peer-gone so the
  extension suspends outbound fan-out for that owner.
