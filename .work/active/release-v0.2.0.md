---
id: release-v0.2.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-07-20
updated: 2026-07-20
---

# Release v0.2.0

First post-rebrand repo-level release. Binds all cross-component,
docs/research, and unattributed gate-finding work since the `v0.1.0` rebrand
reset: 88 items (2 epics, 9 features, 77 stories). These are items that
touch multiple components (no single-component attribution) or are
docs/research/testing-only — they don't belong to any one component release.

This release is the cross-cutting companion to the four component releases
(relay-0.2.0, app-v0.2.0, extension-0.2.0, cockpit-v0.2.0). The paired
wire changes (`feature-finish-generated-protocol-adoption`,
`feature-typed-bounded-relay-decoding`,
`feature-mobile-native-session-process-control`) make the components
version-paired — they deploy together as a coordinated cut.

## Bound items

88 items (2 epics, 9 features, 77 stories). Full list in the shipped-items
table at release time. Notable cross-component features:

- `epic-rebrand-to-outpost-pi` — the rebrand epic (multi-component)
- `epic-remote-session-resilience-refactor` — session resilience (multi-component)
- `feature-typed-bounded-relay-decoding` — typed wire decoding (app + extension + relay)
- `feature-finish-generated-protocol-adoption` — generated protocol (extension + relay + cockpit)
- `feature-mobile-native-session-process-control` — mobile session control (app + extension)
- `feature-contract-gap-audit` — contract gaps (extension + app + relay + docs)
- `feature-redact-secrets-from-diagnostic-surfaces` — secret redaction (app + extension + cockpit)
- `feature-repair-current-state-docs` — doc drift repair (multi-component docs)

Plus 6 archived stubs (late-bound) and 77 gate-finding stories across all
gates (security, tests, cruft, docs, refactor).

## Gate runs

### Binding-consistency warnings

Guard run 2026-07-20 (`binding_guard: warn`, `epic_cohesion: phased`).
Zero CONFLICTs. INCOMPLETEs (unbound children of bound parents) are
informational under `phased` — all are cross-component children that
belong to one of the four component releases, not here. No repo-attributed
child is left behind.

(pending — gates run next)

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator confirms the release. For a repo-level release
the smoke is the union of the component smokes: the app↔Pi pairing lifecycle
(covered by app/extension UAT) + relay health (covered by relay UAT) + the
cross-component protocol path. The component releases' UATs already
exercised the live wire path end to end.
