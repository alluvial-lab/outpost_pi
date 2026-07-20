---
id: release-app-v0.2.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: app-v0.2.0
gate_origin: null
created: 2026-07-20
updated: 2026-07-20
---

# Release app-v0.2.0

First post-rebrand app release. Binds the app-attributed done work since the
`app-v0.1.0` rebrand reset: async lifecycle ownership, secure transcript
storage, mobile TUI parity chat resilience, and several mobile bug fixes.

This release is paired with cross-component protocol changes bound to repo
`v0.2.0` (`feature-typed-bounded-relay-decoding`,
`feature-mobile-native-session-process-control`) — the app↔Pi wire path is
not independently deployable. At the UAT checkpoint this release deploys as
part of a coordinated cut (relay → full pi restart → sideload app → upgrade
cockpit), not in isolation.

## Bound items

### Active done items (11)

| id | title | kind | tags |
|----|-------|------|------|
| feature-app-async-lifecycle-ownership | App async lifecycle ownership | feature | app, lifecycle |
| feature-secure-transcript-storage | Secure transcript storage | feature | app, security |
| feature-app-async-lifecycle-ownership-connection-persistence | Connection persistence | story | app, lifecycle |
| feature-app-async-lifecycle-ownership-mesh-publication | Mesh publication | story | app, lifecycle |
| feature-app-async-lifecycle-ownership-startup-ownership | Startup ownership | story | app, lifecycle |
| feature-app-async-lifecycle-ownership-sync-failure-semantics | Sync failure semantics | story | app, lifecycle |
| feature-mobile-tui-parity-chat-resilience-status-projection | Chat resilience status projection | story | app, lifecycle |
| feature-secure-transcript-storage-migrate-legacy-transcripts | Migrate legacy transcripts | story | app, security |
| idea-mobile-chat-blank-on-tab-return | Chat blank on tab return | story | app, bug, lifecycle |
| idea-mobile-chat-reorder-on-return | Chat reorder on return | story | app, bug, lifecycle |
| roadmap-mobile-parity-with-pi-tui | Mobile parity with Pi TUI | story | app, ux, roadmap, parity |

## Gate runs

### Binding-consistency warnings

Guard run 2026-07-20 (`binding_guard: warn`, `epic_cohesion: phased`).
All findings are legitimate cross-component phased delivery, not true drift:

- **CONFLICT ×5** — done+unbound parents of bound app items. All are
  multi-component → repo-attributed (bind to repo `v0.2.0`, not here):
  `epic-remote-session-resilience-refactor` `[pi-extension, app, relay, workflow]`,
  `feature-mobile-tui-parity-chat-resilience` `[app, pi-extension, workflow, lifecycle]`
  (parent of 4 bound stories).
- **INCOMPLETE ×12** (informational under `phased`) — unbound children of bound
  app features. All are non-app-tagged → repo-attributed (`[cleanup]`, untagged
  `gate-refactor-*`, or `[security]`-only). They bind to repo `v0.2.0`.
  No app-attributed child is left behind.

(pending — gates run next)

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator runs the app↔Pi smoke runbook in
[`docs/release-uat.md`](../../docs/release-uat.md) and records an ack. For an
app release the smoke exercises the pairing → session-hydrate lifecycle end
to end: relay up + `authenticated`, `/remote-pi pair` renders the QR, app
scans → `pair_ok`, session transcript hydrates both directions.
