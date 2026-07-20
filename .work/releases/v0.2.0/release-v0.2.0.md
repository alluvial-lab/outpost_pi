---
id: release-v0.2.0
kind: release
stage: released
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

### gate-security (2026-07-20) — 2 Medium, 3 Low

No release blockers. All unbound backlog:
`gate-security-local-ipc-permissions`, `gate-security-broker-audit-log-unbounded`,
`gate-security-cockpit-temp-workspace-trace`, `gate-security-lsp-stderr-logged`,
`gate-security-mobile-failure-detail-logged`.
(12 existing security findings + 2 umbrella features skipped.)

### gate-tests (2026-07-20) — 1 Critical, 1 High

Release-blocking:
- `gate-tests-wake-outcome-call-site-canary` (Critical)
- `gate-tests-app-relay-ingress-boundaries` (High)

### gate-cruft (2026-07-20) — 3 High

Release-blocking:
- `gate-cruft-local-mesh-unused-context-cache`
- `gate-cruft-remote-session-unused-context-type`
- `gate-cruft-codegen-unused-validator-helpers`

### gate-docs (2026-07-20) — 9 High

Release-blocking (all 9 bound to v0.2.0):
`gate-docs-spec-session-identity-current-truth`,
`gate-docs-vision-session-contamination-current-state`,
`gate-docs-protocol-agent-request-availability`,
`gate-docs-root-readme-local-extension-install`,
`gate-docs-relay-claudemd-plaintext-persistence`,
`gate-docs-release-uat-outpost-command`,
`gate-docs-piext-skill-outpost-command`,
`gate-docs-cockpit-rpc-guide-current-path`,
`gate-docs-cockpit-changelog-distribution`.

### gate-patterns (2026-07-20) — 1 pattern draft

No findings. Emitted pattern draft `fresh-operation-gateway-factories` as
`gate-patterns-v0.2.0` at `stage: done`; updated pattern index.

### gate-refactor (2026-07-20) — 1 High, 1 Medium

Release-blocking:
- `gate-refactor-lifecycle-attachment-messenger-after-await` (High)

Non-blocking (unbound backlog):
- `gate-refactor-boundaries-lsp-diagnostic-wire-map` (Medium)
(27 already-tracked gate-refactor artifacts skipped.)

### Totals

**15 release-blocking findings** (3 cruft + 9 docs + 1 refactor + 2 tests)
must reach `done` before ship; **9 non-blocking** findings are unbound backlog.

Note: 6 pre-existing incomplete archived stubs (from 2026-07-01/15, never
finished) were unbound from v0.2.0 — they are stale gate findings from prior
release cycles, not part of this release's intent.

## UAT checkpoint

Per `release_uat: manual-checkpoint` in `.work/CONVENTIONS.md`, the tag is
**not** cut until an operator confirms the release. For a repo-level release
the smoke is the union of the component smokes: the app↔Pi pairing lifecycle
(covered by app/extension UAT) + relay health (covered by relay UAT) + the
cross-component protocol path. The component releases' UATs already
exercised the live wire path end to end.
