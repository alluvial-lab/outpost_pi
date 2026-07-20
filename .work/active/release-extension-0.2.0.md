---
id: release-extension-0.2.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: null
created: 2026-07-20
updated: 2026-07-20
---

# Release extension-0.2.0

First post-rebrand pi-extension release. Binds the pi-extension-attributed
done work since the `extension-0.1.0` rebrand reset: outbound buffer on
peer offline, lifecycle delivery-promise policy, retire legacy composition
seams, and several bug fixes.

This release is paired with cross-component protocol changes bound to repo
`v0.2.0` (`feature-typed-bounded-relay-decoding`,
`feature-finish-generated-protocol-adoption`,
`feature-mobile-native-session-process-control`). The extension is not
independently deployable. At the UAT checkpoint this release deploys as part
of a coordinated cut (relay → full pi restart → sideload app → upgrade
cockpit). A source edit requires `corepack pnpm build` before it's live, and
a full pi process restart (not `/reload`) to load the new `dist/`.

## Bound items

### Active done items (11)

| id | title | kind | tags |
|----|-------|------|------|
| feature-outbound-buffer-on-peer-offline | Outbound buffer on peer offline | feature | pi-extension, bug, lifecycle |
| feature-piext-lifecycle-delivery-promise-policy | Lifecycle delivery-promise policy | feature | pi-extension, refactor, lifecycle |
| feature-retire-legacy-piext-composition-seams | Retire legacy composition seams | feature | pi-extension, refactor, cleanup |
| feature-outbound-buffer-on-peer-offline-bounded-turn-buffer | Bounded turn buffer | story | pi-extension, lifecycle |
| feature-outbound-buffer-on-peer-offline-ordering-regressions | Ordering regressions | story | pi-extension, lifecycle |
| feature-outbound-buffer-on-peer-offline-presence-lifecycle | Presence lifecycle | story | pi-extension, lifecycle |
| feature-outbound-buffer-on-peer-offline-turn-boundary-wiring | Turn boundary wiring | story | pi-extension, lifecycle |
| gate-refactor-lifecycle-queued-delivery-promise | Queued delivery promise | story | pi-extension |
| gate-refactor-protocol-contract-relay-client-island | Relay client island | story | pi-extension, protocol |
| story-stale-action-boundary-regression-tests | Stale action boundary regression tests | story | pi-extension, bug |
| story-stale-command-ui-notify-guard | Stale command UI notify guard | story | pi-extension, bug |

## Gate runs

### Binding-consistency warnings

Guard run 2026-07-20 (`binding_guard: warn`, `epic_cohesion: phased`).
All findings are legitimate cross-component phased delivery, not true drift:

- **CONFLICT ×5** — done+unbound parents of bound pi-extension items. All
  multi-component → repo-attributed: `epic-remote-session-resilience-refactor`
  `[pi-extension, app, relay, workflow]` (parent of 4 bound stories),
  `feature-finish-generated-protocol-adoption` `[pi-extension, relay, cockpit,
  refactor, protocol]` (parent of `gate-refactor-protocol-contract-relay-client-island`).
- **INCOMPLETE ×6** (informational under `phased`) — unbound children of bound
  pi-extension features. All non-pi-extension-tagged → repo-attributed
  (`[cleanup]` or untagged `gate-refactor-*`). They bind to repo `v0.2.0`.
  No pi-extension-attributed child is left behind.

(pending — gates run next)

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator runs the app↔Pi smoke runbook in
[`docs/release-uat.md`](../../docs/release-uat.md) and records an ack.
Build with `corepack pnpm build` from `pi-extension/`, then full pi process
restart (not `/reload`) to load the new `dist/`.
