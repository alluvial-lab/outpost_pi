---
id: release-app-v0.3.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: app-v0.3.0
gate_origin: null
created: 2026-07-25
updated: 2026-07-25
---

# Release app-v0.3.0

Component release for the Flutter mobile app (tag prefix `app-v`). Companion
to repo release v0.3.0 (shipped 2026-07-25), which carried the paired
cross-component arc (owner-channel E2E, owner-identity transition, secure
channel, CI matrix). This release binds the app-only-attributed items from
that arc.

## Bound items

Active done items (3), bound 2026-07-25:

- gate-security-mobile-failure-detail-logged (child of
  feature-diagnostic-privacy-hardening, v0.3.0)
- gate-security-owner-reset-retains-transcripts (child of
  feature-owner-identity-transition, v0.3.0)
- app-owner-key-version-rollback-hardening (child of
  feature-owner-identity-transition, v0.3.0)

Archived-stub gather (2026-07-25): 2 unbound stubs swept, both
extension-attributed — `gate-security-pair-code-file-preexisting-perms-window`
(operator-confirmed for cockpit-v0.3.0 instead: implemented in the cockpit
pair-code fix commit series) and
`gate-tests-fakesession-buildcontext-duplicate-projection` (deselected;
extension test hygiene already shipped in the v0.3.0 tag;
extension-0.3.0 stays skipped).

### Binding-consistency warnings

BINDING CONSISTENCY — release app-v0.3.0 (binding_guard: warn, epic_cohesion:
phased) — 7 informational findings, all the project's deliberate phased
split: parents shipped in repo release v0.3.0, app/cockpit-attributed
children ledger to their component releases. Children bound to app-v0.3.0
with parents bound to v0.3.0: gate-security-mobile-failure-detail-logged,
gate-security-owner-reset-retains-transcripts,
app-owner-key-version-rollback-hardening (expected). Unbound children
awaiting cockpit-v0.3.0: gate-security-cockpit-temp-workspace-trace,
gate-security-formatter-reload-diagnostics-path-disclosure,
gate-security-lsp-stderr-logged,
gate-security-rpcunknown-retains-wire-discriminator (expected).
