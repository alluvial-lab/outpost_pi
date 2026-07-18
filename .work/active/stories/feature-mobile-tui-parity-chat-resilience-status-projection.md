---
id: feature-mobile-tui-parity-chat-resilience-status-projection
kind: story
stage: drafting
tags: [app, lifecycle]
parent: feature-mobile-tui-parity-chat-resilience
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
---

# Compose transport, agent-turn, and steering status projections

## Design

This is Unit 1 and the structural foundation for the feature. Replace the
flattened `ChatReady.isWorking`/offline facts and AppBar priority chain with the
composed `ChatStatusProjection` designed in the parent feature:

- transport: typed online/retrying/offline projection derived exhaustively from
  `ConnectionStatus` plus active-room reachability;
- turn: the existing `AppTurnProjection`/`AppTurnStatus` authority, not a new
  phase enum;
- steering: typed none/pending projection independent of the active turn.

The AppBar renders transport and agent phase independently. Stop derives from
the broad active-turn projection, including `awaitingTool`; pending steering
gets its own indicator without replacing the active turn. Delete the old
`working > reconnecting > online > offline` priority mapper and duplicated
status booleans when all consumers move.

No production pi-extension or wire change is expected. Targeted extension tests
must pin the existing tool and steer/pickup signals on which the app projection
depends. If those tests show there is no stable pickup signal, stop for protocol
redesign rather than infer pickup from time.

## Acceptance evidence

- Table-driven app tests represent transport and turn combinations independently.
- Awaiting-tool remains cancellable and displays `waiting`; idle/error/stale are
  not cancellable.
- Steering pending coexists with the active turn and transport state.
- Existing terminal/reconnect/session-replacement convergence tests remain green.
- Extension contract tests prove the required existing signals without a new
  required field.

## Provenance closures

When this evidence is green, close these children as structurally subsumed:

- `idea-mobile-conflates-transport-and-agent-state`
- `idea-mobile-no-stop-button-while-awaiting-tool`
- `idea-mobile-no-steering-indicator-when-queued`
