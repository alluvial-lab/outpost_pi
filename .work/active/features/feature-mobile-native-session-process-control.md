---
id: feature-mobile-native-session-process-control
kind: feature
stage: drafting
tags: [app, pi-extension, daemon, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-16
---

# Mobile: native Pi session and process control

## Brief

Two backlog items describe the mobile operator's inability to drive Pi
session/process lifecycle from the phone — the TUI's slash-command surface is
unusable from mobile, and there is no affordance to fully restart the Pi
process (required to pick up a rebuilt `dist/index.js`, since `/reload` does
NOT re-import the module). The mechanism already exists internally
(`EXIT_DAEMON_FRESH_SESSION` exit 42 → supervisor respawn) but isn't exposed as
a mobile action:

- `idea-mobile-session-control` — mobile app: session control and command surface gaps (`/reload`, `/new`, spawn new pi sessions from mobile)
- `idea-mobile-restart-pi-session-affordance` — mobile: no way to fully restart the Pi process (fresh session + relay) from the phone

## Simplification opportunity

Expose the existing `EXIT_DAEMON_FRESH_SESSION` RPC + `session_new` action
through a mobile-facing control surface; don't re-implement process management.
Depends on `feature-remote-pi-fork-vendor-and-mobile-surface` (drafting) for
the mobile-surface scope it shares.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor`. 2 `idea-mobile-*` items. Related to
the drafting `feature-remote-pi-fork-vendor-and-mobile-surface`.
