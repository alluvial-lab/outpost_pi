---
id: feature-mobile-tui-parity-chat-resilience
kind: feature
stage: drafting
tags: [app, pi-extension, workflow, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-16
---

# Mobile/TUI parity and lifecycle-resilient chat behavior

## Brief

Ten backlog items (one roadmap + nine ideas) describe the mobile chat
experience falling short of the pi TUI across status accuracy, message
ordering, and recovery. The structural parent finding
(`idea-mobile-conflates-transport-and-agent-state`) is that the mobile status
pill conflates transport/connection state with agent/turn state — fixing that
properly subsumes several of the status/steering symptoms. The cluster is the
mobile-UX half of `epic-remote-session-resilience-refactor`'s "make mobile UI
state robust" scope:

- `roadmap-mobile-parity-with-pi-tui` — roadmap: bring mobile to parity with the pi TUI
- `idea-mobile-conflates-transport-and-agent-state` — status pill conflates transport with agent/turn state (parent structural finding)
- `idea-mobile-no-stop-button-while-awaiting-tool` — agent doesn't show "working" / no Stop button while awaiting a tool result
- `idea-mobile-no-steering-indicator-when-queued` — no "steering/queued" indicator when sending while agent is working
- `idea-mobile-queued-message-does-not-reorder` — steered message threads in place; doesn't reorder to bottom when picked up
- `idea-mobile-chat-reorder-on-return` — returning to chat sometimes reorders the latest user message below the assistant response
- `idea-mobile-chat-blank-on-tab-return` — chat renders blank on tab return; needs back-out + re-enter to rehydrate
- `idea-mobile-drop-slow-recovery` — network drop: slow end-to-end recovery (~5 min)
- `idea-mobile-outgoing-message-swallowed` — outgoing message not delivered and not surfaced
- `idea-mobile-message-duplication-send-timeout` — message duplication + send_timeout confirmation bug

## Simplification opportunity

Resolve the transport-vs-agent-state conflation as the structural fix (subsumes
the status/steering symptoms); the ordering/blank/swallowed items reduce to
distinct reproducible bugs once observability (`feature-cross-side-observability`,
shipped v0.1.0) catches them. Several may fold into existing drafting stories
(`story-mobile-double-messages-on-session-history-replay`,
`story-mobile-send-timeout-relay-room-main-mismatch`).

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor`. 10 `roadmap-mobile-*` / `idea-mobile-*`
items captured during the 2026-07 mobile testing window.
