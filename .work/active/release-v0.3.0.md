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

- gate-docs-control-transport-nul-prefix-contradiction (done)
- gate-docs-phase8-residual-foundation-drift (done)
- idea-extension-stale-ctx-incoming-message-rejected (done; superseded by feature-session-stable-message-delivery)
- idea-extension-pumps-into-dead-app-peer (done; superseded by story-extension-suspend-fanout-on-peer-offline)
- idea-mobile-user-message-not-delivered-timeout (done; superseded by story-fix-resumed-session-echo-gate-rejection)
- idea-cross-side-logging-for-debug (done; superseded by feature-cross-side-observability)
- rebrand-branding-assets-redraw (done; superseded by story-epic-rebrand-external-surfaces-hostname-migration-branding-svg-redraw)

~~Late-bound archived stubs (23)~~ — 16 unbound 2026-07-24 (see "Release paused" above): the merge-absorbed, duplicate, and superseded/resolved husks listed there.

### Binding-consistency warnings

BINDING CONSISTENCY — release v0.3.0 (epic_cohesion: phased) — 0 CONFLICTs; 7 informational INCOMPLETEs, all expected phased splits (children held for app-v0.3.0 / cockpit-v0.3.0):
- gate-security-lsp-stderr-logged, gate-security-rpcunknown-retains-wire-discriminator, gate-security-formatter-reload-diagnostics-path-disclosure, gate-security-cockpit-temp-workspace-trace (children of feature-diagnostic-privacy-hardening → cockpit-v0.3.0)
- gate-security-mobile-failure-detail-logged (child of feature-diagnostic-privacy-hardening → app-v0.3.0)
- gate-security-owner-reset-retains-transcripts, app-owner-key-version-rollback-hardening (children of feature-owner-identity-transition → app-v0.3.0)

## Release paused (2026-07-24)

Operator halted the release cycle after the gate phase to drain the board
first. The release stays at `stage: quality-gate`; resume later with
`/agile-workflow:release-deploy v0.3.0` (idempotent — picks up at readiness).

**Unbound 2026-07-24 (16 archived stubs, removed from this release):** the
late-binding gather had swept retired-but-unfinished archive husks. On
inspection none contained genuine uncompleted work: 9 merge-absorbed by the
2026-07-22 groom (stamped `status: superseded` + `superseded_by` →
backlog-cruft-removal-batch / backlog-cockpit-file-watch-reliability /
backlog-app-lifecycle-owned-operations), 3 already-stamped duplicates (two of
whose fold targets shipped in extension-0.2.0), 4 superseded/resolved
(signing-oracle code-verified; changelog-missing + auto-retry-event-drift
resolved cockpit-v1.6.0 era; formal-rigor-relay-backpressure
resolved-in-substance). All 16 now `release_binding: null` and carry status
stamps so future gathers skip them (gather patched 2026-07-24 to skip
status-stamped and non-done archive files).

**Bound set after unbind:** 17 active done items + 7 done archived stubs +
28 gate-produced items (27 blocking at implementing + gate-patterns-v0.3.0
done).

**Operator decisions 2026-07-24 (pre-drain):** the two parked gate-security
mediums (`gate-security-owner-transition-committed-before-durable-cleanup`,
`gate-security-identity-store-fatal-read-rotates-owner-key`) were **promoted
to release-blocking** and bound at implementing — both defeat the v0.3
owner-transition boundary on partial-failure paths. And
`gate-patterns-inconsistency-pairing-viewmodel-generation-fence` was merged
into `gate-refactor-lifecycle-pairing-viewmodel-no-dispose` (stamped
superseded in archive; combined acceptance on the bound item).
Readiness now blocks on the **29** gate findings below.

## Gate runs

- **gate-cruft** (2026-07-24) — 3 findings (1 high, 2 medium, 0 low). High → `gate-cruft-generated-validator-unused-number-helper` (implementing, bound). Medium ×2 parked to backlog per gate_finding_routing (`gate-cruft-plain-peer-channel-unused-disconnect-callback`, `gate-cruft-qr-terminal-rotation-dead-path`).
- **gate-docs** (2026-07-24) — 14 findings (all high-confidence, all release-relevant): 5 foundation-doc assertions (VISION/DECISIONS/AGENTS pre-E2E trust model + overstated same-Owner multi-device + env_id_tail correlation), 4 README staleness (root/relay/pi-extension/site), 1 repo-skill (rust-relay), 4 pattern-skill anchor drift (typed-wire-decoders, generation-fenced, subscription-contract, stale-capability). All 14 bound at stage: implementing — the E2E ship invalidated the pre-E2E trust-model prose repo-wide.
- **gate-tests** (2026-07-24) — 6 findings (2 critical, 4 high). 5 release-relevant bound at implementing: `gate-tests-ci-lane-runs-env-dependent-e2e` (critical), `gate-tests-lost-pair-ok-repair-recovery-e2e`, `gate-tests-five-failure-detach-reattach-e2e`, `gate-tests-orphan-message-projection-wipe`, `gate-tests-session-replacement-real-rotation-e2e` (high). 1 ambient critical (pre-bundle tautological debug-log assertions) parked to backlog unbound: `gate-tests-debug-log-literal-success-assertions`.
- **gate-security** (2026-07-24) — 7 findings (0 critical, 2 high, 3 medium, 2 low), all release-relevant. Highs bound at implementing: `gate-security-pairing-token-in-model-context` (QR bearer token reaches LLM context via pi.sendMessage), `gate-security-high-severity-dependency-audit-failures` (next/sharp/brace-expansion/fast-uri advisories; deps-audit lane red). Mediums: identity-store-fatal-read-rotates-owner-key, owner-transition-committed-before-durable-cleanup **promoted to release-blocking + bound at implementing 2026-07-24 (operator decision)**; ci-mutable-action-refs parked. Lows parked: debug-log-fallback-raw-exceptions, plaintext-pair-error-internal-details.
- **gate-patterns** (2026-07-24) — 5 new patterns codified (`content-free-diagnostic-categories`, `frame-byte-bounded-admission`, `identity-scoped-monotonic-high-watermarks`, `recoverable-secure-channel-circuit-breakers`, `cross-language-known-answer-fixture-triangulation`); index + rules digest regenerated (16 patterns). 3 inconsistencies flagged → unbound [refactor] drafting stories for a subsequent release; `gate-patterns-inconsistency-pairing-viewmodel-generation-fence` was later merged into `gate-refactor-lifecycle-pairing-viewmodel-no-dispose` (2026-07-24), leaving `-pairing-coordinator-stale-capability` and `-pair-request-flow-typed-decoder` parked. Tracking item `gate-patterns-v0.3.0` done.
- **gate-refactor** (2026-07-24) — 14 findings (11 high, 3 medium) from 4 libraries: protocol-contract (7), lifecycle (4), documentation (3), boundaries (0). Note: `scan-documentation` was discovered as a 4th library (declares findings-route: refactor) — CONVENTIONS prose mentions only 3; update at next conventions touch. 5 release-relevant highs bound at implementing (`gate-refactor-lifecycle-pairing-viewmodel-no-dispose`, `gate-refactor-protocol-contract-session-replay-handwritten-discriminators`, `gate-refactor-protocol-contract-owner-multiplexer-handwritten-types`, `gate-refactor-documentation-dart-secure-channel-throws`, `gate-refactor-documentation-ts-secure-channel-throws`). 6 ambient highs + 3 mediums parked to backlog unbound.

### Gate re-runs (2026-07-24, drain-delta re-scan — operator-directed after the 29-item drain landed new code post-gate)

- **gate-security** — 3 findings (2 high, 1 low) + 7 verified-clean. Bound at implementing: `gate-security-stopped-app-owner-replacement-undetected` (boot activates a replaced Owner without cleanup when the replacement happened while stopped; fingerprint fix), `gate-security-brace-expansion-advisory-refresh` (5.0.7 now inside GHSA-mh99-v99m-4gvg; bump to 5.0.8 — orchestrator-verified red prod audit). Low parked: `gate-security-pair-code-file-preexisting-perms-window`.
- **gate-tests** — 7 findings (3 high, 3 medium, 1 low). Bound at implementing: `gate-tests-pairing-token-context-regression-representation-blind`, `gate-tests-owner-transition-failure-paths-real-marker`, `gate-tests-stale-completion-during-peer-persistence`. Parked: fakesession-buildcontext-duplicate-projection (low; sanctioned to close with the bound token item), pairing-qr-rpc-mode-no-seam-untested, codegen-number-only-partition, sync-service-noecho-wallclock-timing (likely CI flake root cause).
- **gate-cruft** — 2 findings (both high confidence). `gate-cruft-cockpit-pair-code-consumer-dead` bound to **cockpit-v0.3.0** (cockpit pairing waits for the removed pair-code custom message — feature break in the paired component, not the repo tag; operator may re-route). `gate-cruft-client-message-discriminators-unused` bound at implementing.
- **gate-docs** — 4 findings → 3 bound items (`gate-docs-pi-extension-readme-tui-only-pair`, `gate-docs-flutter-test-excludes-e2e-tag` (merges 2 findings across 5 doc locations), `gate-docs-next-site-skill-version-bump`).
- **gate-refactor** — 1 finding (lifecycle/resource-no-dispose, high): stale pairing continuation closes mutable global transient fields. Merged into bound `gate-tests-stale-completion-during-peer-persistence` (same defect, sharper diagnosis). No separate item.
- **gate-patterns** — 2 patterns codified (`durable-transition-latches`, `explicit-async-interleaving-tests`; index now 18 patterns + digest regenerated); 1 inconsistency already absorbed by the bound stale-completion item. Tracking item `gate-patterns-v0.3.0-drain-rescan` done.

**Bound blocking after re-scan: 9 items at implementing** (2 security, 3 tests, 1 cruft, 3 docs) — fix wave dispatched 2026-07-24.

<pending>
