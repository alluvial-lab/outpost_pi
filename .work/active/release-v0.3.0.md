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

### Binding-consistency warnings

BINDING CONSISTENCY — release v0.3.0 (epic_cohesion: phased) — 0 CONFLICTs; 7 informational INCOMPLETEs, all expected phased splits (children held for app-v0.3.0 / cockpit-v0.3.0):
- gate-security-lsp-stderr-logged, gate-security-rpcunknown-retains-wire-discriminator, gate-security-formatter-reload-diagnostics-path-disclosure, gate-security-cockpit-temp-workspace-trace (children of feature-diagnostic-privacy-hardening → cockpit-v0.3.0)
- gate-security-mobile-failure-detail-logged (child of feature-diagnostic-privacy-hardening → app-v0.3.0)
- gate-security-owner-reset-retains-transcripts, app-owner-key-version-rollback-hardening (children of feature-owner-identity-transition → app-v0.3.0)

## Gate runs

- **gate-cruft** (2026-07-24) — 3 findings (1 high, 2 medium, 0 low). High → `gate-cruft-generated-validator-unused-number-helper` (implementing, bound). Medium ×2 parked to backlog per gate_finding_routing (`gate-cruft-plain-peer-channel-unused-disconnect-callback`, `gate-cruft-qr-terminal-rotation-dead-path`).
- **gate-docs** (2026-07-24) — 14 findings (all high-confidence, all release-relevant): 5 foundation-doc assertions (VISION/DECISIONS/AGENTS pre-E2E trust model + overstated same-Owner multi-device + env_id_tail correlation), 4 README staleness (root/relay/pi-extension/site), 1 repo-skill (rust-relay), 4 pattern-skill anchor drift (typed-wire-decoders, generation-fenced, subscription-contract, stale-capability). All 14 bound at stage: implementing — the E2E ship invalidated the pre-E2E trust-model prose repo-wide.
- **gate-tests** (2026-07-24) — 6 findings (2 critical, 4 high). 5 release-relevant bound at implementing: `gate-tests-ci-lane-runs-env-dependent-e2e` (critical), `gate-tests-lost-pair-ok-repair-recovery-e2e`, `gate-tests-five-failure-detach-reattach-e2e`, `gate-tests-orphan-message-projection-wipe`, `gate-tests-session-replacement-real-rotation-e2e` (high). 1 ambient critical (pre-bundle tautological debug-log assertions) parked to backlog unbound: `gate-tests-debug-log-literal-success-assertions`.
- **gate-security** (2026-07-24) — 7 findings (0 critical, 2 high, 3 medium, 2 low), all release-relevant. Highs bound at implementing: `gate-security-pairing-token-in-model-context` (QR bearer token reaches LLM context via pi.sendMessage), `gate-security-high-severity-dependency-audit-failures` (next/sharp/brace-expansion/fast-uri advisories; deps-audit lane red). Mediums parked: identity-store-fatal-read-rotates-owner-key, owner-transition-committed-before-durable-cleanup (**operator may want to promote these two — they touch the v0.3 owner-transition boundary**), ci-mutable-action-refs. Lows parked: debug-log-fallback-raw-exceptions, plaintext-pair-error-internal-details.
- **gate-patterns** (2026-07-24) — 5 new patterns codified (`content-free-diagnostic-categories`, `frame-byte-bounded-admission`, `identity-scoped-monotonic-high-watermarks`, `recoverable-secure-channel-circuit-breakers`, `cross-language-known-answer-fixture-triangulation`); index + rules digest regenerated (16 patterns). 3 inconsistencies flagged → unbound [refactor] drafting stories for a subsequent release (`gate-patterns-inconsistency-pairing-viewmodel-generation-fence`, `-pairing-coordinator-stale-capability`, `-pair-request-flow-typed-decoder`). Tracking item `gate-patterns-v0.3.0` done.

<pending>
