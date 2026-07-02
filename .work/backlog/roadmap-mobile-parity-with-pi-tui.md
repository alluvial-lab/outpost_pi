---
id: roadmap-mobile-parity-with-pi-tui
created: 2026-07-02
updated: 2026-07-02
tags: [app, ux, roadmap, parity]
---

# Roadmap: bring the mobile experience up to parity with the pi TUI

## Captured context (operator 2026-07-02)

Live user testing surfaced a cluster of mobile UX gaps that, taken together,
indicate the mobile chat experience has drifted below the pi TUI's interaction
model in several places. The operator's framing: "we just have a lot of work
bringing the mobile experience up to parity with the pi TUI."

This is a **roadmap-level capture**, not a single story. It groups the
session's findings into a parity arc for later scope/design. No kind, stage,
parent, or decomposition is decided here.

## The parity gaps found this session

### Working / state projection (parent: state conflation)

The mobile status pill conflates transport/connection state with agent/turn
state into one flattened enum (`working > reconnecting > online > offline`),
losing agent granularity. The pi TUI keeps these separate and shows distinct
indicators.

- `idea-mobile-conflates-transport-and-agent-state` — **parent structural
  finding.** Fixing this properly subsumes the two symptoms below.
- `idea-mobile-no-stop-button-while-awaiting-tool` — no "waiting" status and
  no Stop button during bash/background tool execution (app shows "online").
  Operator's ask: a distinct "waiting" status.
- `idea-mobile-no-steering-indicator-when-queued` — no "steering/queued"
  indicator when messaging during a working turn (pi TUI shows a gray
  steering indicator).
- `idea-mobile-queued-message-does-not-reorder` — steered message stays in
  insertion order instead of reordering to the bottom when picked up (pi TUI
  reorders).

### Lifecycle / hydration

- `idea-mobile-chat-blank-on-tab-return` — chat renders blank after app
  switch + tab-back-in; needs back-out + re-enter to rehydrate. Flutter
  lifecycle/view gap, no network change involved.

### Network resilience (drop test)

- `idea-mobile-drop-slow-recovery` — ~5 min end-to-end recovery on
  wifi→5g/wireguard switch.
- `idea-mobile-drop-half-open-tcp` — no clean disconnect on network switch;
  duplicate-connection window, detection gated by 25s ping timeout.
- `idea-extension-pumps-into-dead-app-peer` — extension keeps streaming at a
  dead app peer for ~2 min after disconnect.
- `idea-mobile-outgoing-message-swallowed` — an outgoing message vanished
  with no error surfaced during the drop.

## What "parity with the pi TUI" means here (working definition, for design time)

The pi TUI is the reference interaction model. Parity does NOT mean pixel
equivalence — it means the mobile user gets the same **observability and
control** over agent state: they can see what the agent is doing (working /
waiting / streaming / queued), interrupt it (Stop) at any active point,
steer it with a visible queue indicator, and see messages in logical
prompt/response order. The transport health (connected/reconnecting/offline)
is a separate concern that should compose with, not collapse into, the agent
state.

### Guiding principle: the pi TUI is the reference implementation

When in doubt about what the mobile app should do, **port the affordance from
the pi TUI** rather than designing mobile UX from scratch. The TUI already
encodes the canonical interaction model (steering indicator, Stop semantics,
message reorder-on-pickup, working/waiting distinction, tool-execution
visibility). A user will expect the app to behave similarly to the TUI they
already know, so the TUI is the source of truth for interaction semantics;
the mobile work is adaptation (touch affordances, lifecycle resilience,
compact status presentation), not reinvention. Audit the TUI's affordances
systematically when scoping each parity gap — the answer to "what should the
app do here?" is usually "whatever the TUI does."

## Not yet scoped

This capture deliberately does not:

- choose an epic vs feature vs multi-story decomposition;
- assign `depends_on` chains;
- prioritize the gaps relative to each other or to non-parity work;
- decide whether the state-conflation parent is a prerequisite for the
  symptom fixes (design time call).

That's `/agile-workflow:scope` territory when the operator is ready to turn
this into tracked work.

## Relationship to existing backlog

- `idea-same-pc-peer-presence-ux` — same-PC cross-cwd peer presence UX
  (different surface, but another "how should this flow" design item).
- `idea-mobile-message-duplication-send-timeout` — pre-existing mobile
  send-confirmation bug; belongs in the same parity audit.
- `idea-cross-side-logging-for-debug` — would help reproduce several of the
  above (swallowed message, slow recovery attribution).
