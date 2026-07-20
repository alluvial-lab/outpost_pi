---
id: release-cockpit-v0.2.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: cockpit-v0.2.0
gate_origin: null
created: 2026-07-20
updated: 2026-07-20
---

# Release cockpit-v0.2.0

First post-rebrand cockpit release. Binds the cockpit-attributed done work
since the `cockpit-v0.1.0` rebrand reset: async action ownership, settings
control tests, typed RPC boundaries, and a cruft bug fix.

This release is paired with cross-component protocol changes bound to repo
`v0.2.0` (`feature-finish-generated-protocol-adoption`,
`feature-cockpit-typed-rpc-boundaries`). The cockpit control channel
(`\x00outpost-pi-ctrl:` / `outpost_pi_control`) is hard-cutover paired with
the extension — old cockpit + new extension break the control channel.
At the UAT checkpoint this release deploys as part of a coordinated cut.

## Bound items

### Active done items (4)

| id | title | kind | tags |
|----|-------|------|------|
| feature-cockpit-async-action-ownership | Async action ownership | feature | cockpit, refactor, lifecycle |
| feature-cockpit-settings-control-tests | Settings control tests | feature | cockpit, testing |
| feature-cockpit-typed-rpc-boundaries | Typed RPC boundaries | feature | cockpit, refactor, protocol |
| gate-cruft-empty-catch-formatter-reload | Empty catch formatter reload | story | cockpit, bug |

## Gate runs

### Binding-consistency warnings

Guard run 2026-07-20 (`binding_guard: warn`, `epic_cohesion: phased`).
No CONFLICTs. 12 INCOMPLETEs (informational under `phased`) — unbound
children of bound cockpit features. All are non-cockpit-tagged →
repo-attributed (untagged `gate-refactor-*` or `[testing]`-only). They
bind to repo `v0.2.0`. No cockpit-attributed child is left behind.

### gate-security (2026-07-20) — 1 Low

No release blockers. Unbound backlog:
`gate-security-formatter-reload-diagnostics-path-disclosure`.

### gate-tests (2026-07-20) — 0 findings

No findings. 258 tests pass; flutter analyze clean (2 pre-existing info
diagnostics, one in the bundle's `file_viewer.dart` — the cruft gate
caught the actionable one).

### gate-cruft (2026-07-20) — 1 High, 1 Medium

Release-blocking:
- `gate-cruft-file-viewer-unnecessary-foundation-import` (High — unnecessary
  import in `file_viewer.dart`)

Non-blocking (unbound backlog):
- `gate-cruft-file-watcher-errors-swallowed` (Medium)

### gate-docs (2026-07-20) — 1 High, 1 Medium

Release-blocking:
- `gate-docs-cockpit-v020-changelog-gap` (High — satisfied by drafting the
  cockpit-v0.2.0 CHANGELOG entry in Phase 5.5)

Non-blocking (unbound backlog):
- `gate-docs-cockpit-guidance-local-only-contradiction` (Medium)

### gate-patterns (2026-07-20) — 1 pattern draft

No findings. Emitted pattern draft `awaited-pane-teardown-contract` as
`gate-patterns-cockpit-v0.2.0` at `stage: done`; updated pattern index.

### gate-refactor (2026-07-20) — 2 Medium

No release blockers. Both unbound backlog (untagged → repo):
`gate-refactor-lifecycle-file-viewer-lsp-debounce-floating`,
`gate-refactor-lifecycle-workspace-file-watch-debounce-floating`.

### Totals

**2 release-blocking findings** (1 cruft High + 1 docs High) must reach
`done` before ship; **5 non-blocking** findings are unbound backlog.

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator runs the cockpit smoke (launch the desktop
build, connect to a running pi session, exercise the control surface:
settings create/rename, control commands) per
[`docs/release-uat.md`](../../docs/release-uat.md) and records an ack.
