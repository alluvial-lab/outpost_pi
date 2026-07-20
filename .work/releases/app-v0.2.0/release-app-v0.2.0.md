---
id: release-app-v0.2.0
kind: release
stage: released
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

### gate-security (2026-07-20) — 2 Medium

Inline scan, reduced isolation. No release blockers. Both unbound to backlog:
`gate-security-owner-reset-retains-transcripts`,
`gate-security-unindexed-plaintext-transcripts-retained`.

### gate-tests (2026-07-20) — 1 Critical, 1 High, 2 Medium

Release-blocking:
- `gate-tests-resume-offline-recovery-branches` (High)

Non-blocking (unbound backlog):
- `gate-tests-remove-placeholder-widget-test` (Critical, testing-only → repo)
- `gate-tests-production-transcript-key-bootstrap` (Medium)
- `gate-tests-chat-status-indicator-widget-contract` (Medium)

### gate-cruft (2026-07-20) — 1 Low

No release blockers. Unbound backlog:
`gate-cruft-unused-settings-relay-url-compatibility`.

### gate-docs (2026-07-20) — 1 High

Release-blocking:
- `gate-docs-app-v0-2-0-changelog-missing` (High — the changelog gap; the
  release's own CHANGELOG entry satisfies this once drafted in Phase 5.5).

### gate-patterns (2026-07-20) — 1 pattern draft

No findings. Emitted pattern draft `generation-fenced-async-ownership` as
`gate-patterns-app-v0.2.0` at `stage: done`; updated pattern index + digest.

### gate-refactor (2026-07-20) — 2 High, 4 Medium

No release blockers. Scan-rule libraries require `tags: []`, making all
findings repo-attributed → unbound backlog:
`gate-refactor-lifecycle-legacy-migration-source-boxes`,
`gate-refactor-protocol-contract-sync-agent-message-literal`,
`gate-refactor-lifecycle-mesh-poll-floating`,
`gate-refactor-lifecycle-resume-mesh-pull-floating`,
`gate-refactor-lifecycle-resume-reconcile-floating`,
`gate-refactor-lifecycle-settings-fallback-boot-floating`.

### Totals

**2 release-blocking findings** (1 docs High + 1 tests High) must reach `done`
before ship; **12 non-blocking** findings are unbound backlog.

(pending — gates run next)

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator runs the app↔Pi smoke runbook in
[`docs/release-uat.md`](../../docs/release-uat.md) and records an ack. For an
app release the smoke exercises the pairing → session-hydrate lifecycle end
to end: relay up + `authenticated`, `/remote-pi pair` renders the QR, app
scans → `pair_ok`, session transcript hydrates both directions.
