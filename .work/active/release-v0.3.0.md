---
id: release-v0.3.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: null
created: 2026-07-24
updated: 2026-07-24
---

# Release v0.3.0

Repo-level release (tag prefix `v`). The owner-channel security arc:
owner-message E2E authentication, diagnostic privacy hardening, owner
identity transition, replacement-session wake confirmation, CI verification
matrix, plus late-bound archived stubs claimed per the attribution rule
(multi-component-tag / no-tag / docs items).

Operator-confirmed bind set (2026-07-24), reconciled against the attribution
rule from the 2026-07-23 handoff plan: `story-document-deferred-relay-volume-cutover`
assigned to relay-0.3.0 (not repo); `gate-cruft-unused-settings-relay-url-compatibility`
assigned to app-v0.3.0; `backlog-piext-extension-test-19-failures` stays
unbound (extension-0.3.0 skipped).

## Bound items

### Active done items (17)

- feature-owner-message-e2e-authentication
- feature-owner-message-e2e-authentication-schema-handshake-frames
- feature-owner-message-e2e-authentication-extension-secure-channel
- feature-owner-message-e2e-authentication-app-secure-channel
- feature-owner-message-e2e-authentication-e2e-protected-channel
- feature-owner-message-e2e-authentication-docs-deploy-rollforward
- feature-diagnostic-privacy-hardening
- feature-owner-identity-transition
- feature-replacement-session-wake-confirmation
- feature-ci-verification-matrix
- feature-ci-verification-matrix-ci-lanes
- feature-ci-verification-matrix-dependabot-audit
- story-e2e-session-replacement-case
- story-mobile-stuck-message-after-new-session-replacement
- gate-refactor-lifecycle-legacy-migration-source-boxes
- gate-refactor-protocol-contract-sync-agent-message-literal
- gate-tests-remove-placeholder-widget-test

### Late-bound archived stubs (23)

- gate-docs-formal-rigor-relay-backpressure
- gate-docs-changelog-missing
- gate-docs-control-transport-nul-prefix-contradiction
- gate-docs-phase8-residual-foundation-drift
- gate-docs-auto-retry-event-drift
- gate-refactor-protocol-relay-client-control-dtos
- gate-refactor-lifecycle-queued-delivery-fire-and-forget
- gate-refactor-lifecycle-settings-fallback-boot-floating
- gate-refactor-lifecycle-resume-mesh-pull-floating
- gate-refactor-lifecycle-resume-reconcile-floating
- gate-refactor-lifecycle-file-viewer-lsp-debounce-floating
- gate-refactor-lifecycle-workspace-file-watch-debounce-floating
- gate-refactor-lifecycle-mesh-poll-floating
- gate-refactor-boundaries-mesh-blob-adhoc-parse
- gate-cruft-presencetransitions-single-impl-trait
- gate-cruft-legacy-sync-turn-compat-shims
- gate-cruft-unused-actordispatch-close
- gate-security-extension-relay-auth-signing-oracle
- rebrand-branding-assets-redraw
- idea-extension-stale-ctx-incoming-message-rejected (superseded by feature-session-stable-message-delivery)
- idea-extension-pumps-into-dead-app-peer (superseded by story-extension-suspend-fanout-on-peer-offline)
- idea-mobile-user-message-not-delivered-timeout (superseded by story-fix-resumed-session-echo-gate-rejection)
- idea-cross-side-logging-for-debug (superseded by feature-cross-side-observability)

## Gate runs

<pending>
