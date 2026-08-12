---
id: release-v0.4.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-11
updated: 2026-08-11
---

# Release v0.4.0

First release under unified product versioning (CONVENTIONS change 2026-08-11).
Formally binds the accumulated done work that was never release-bound — the
post-v0.3.0 backlog of completed gate findings plus the real feature/fix arcs.

## Scope note

- **13** features/fixes that passed review but had not been release-gated
  (hot-reload-via-process-restart, new-session-restart, canonical-transcript
  ordering, working-flag/onConnected fixes, mesh-reconciliation).
- **47** prior gate outputs (security/tests/cruft/docs/patterns/refactor
  hardening) completed since v0.3.0.
- **Excluded:** the in-flight `canonical-transcript-timestamp-ownership` arc
  (feature + 4 stories, `implementing`) and 6 `drafting` items — incomplete work
  is not bound.

## Bound items (66)

> 60 items from the initial bind + 4 autopilot-drain blockers + 2 Phase 8 completion fixes (see Gate runs).

### Features & fixes (13)
- feature-canonical-transcript-ordering
- story-canonical-transcript-ordering-app-consume-tool-ts
- story-canonical-transcript-ordering-extension-broadcast-tool-ts
- story-canonical-transcript-ordering-projection-render-sort
- story-canonical-transcript-ordering-ts-provenance-audit
- feature-extension-hot-reload-via-process-restart
- story-hot-reload-agent-settled-hook-and-wrapper
- story-hot-reload-lifecycle-fence
- story-new-session-restart-fresh-extension-exit
- story-new-session-restart-fresh-restart-mechanism
- story-fix-onconnected-clobbers-working-midturn
- story-fix-working-flag-stuck-after-session-shutdown
- story-mesh-reconciliation-deletes-pairing-channel

### Security gate findings (14)
- feature-secure-transcript-key-loss-recovery-ux
- gate-security-secure-transcript-key-loss-recovery-ux
- gate-security-broker-audit-log-unbounded
- gate-security-compaction-replay-keys-unbounded
- gate-security-presence-offline-timestamps-unbounded
- gate-security-local-ipc-permissions (POSIX scope; Windows ACL deferred → backlog)
- gate-security-plaintext-pair-error-internal-details
- gate-security-debug-log-fallback-raw-exceptions
- gate-security-unindexed-plaintext-transcripts-retained
- gate-security-windows-path-separator-validation
- gate-security-cockpit-agent-boot-path-debugprint
- gate-security-cockpit-stale-pair-dir-orphan-sweep
- gate-security-orphaned-pre-rebrand-launchd-daemon
- gate-security-ci-mutable-action-refs (ci.yml scope; deps-audit/e2e-pairing deferred → backlog)

### Tests gate findings (8)
- gate-tests-codegen-number-only-partition
- gate-tests-debug-log-literal-success-assertions
- gate-tests-localboxes-restart-preservation
- gate-tests-mesh-auth-cache-ttl
- gate-tests-offline-buffer-per-peer-isolation
- gate-tests-pairing-qr-rpc-mode-no-seam-untested
- gate-tests-relay-heartbeat-first-tick
- gate-tests-sync-service-noecho-wallclock-timing

### Refactor gate findings + design features (17)
- feature-boundary-typed-decoders
- feature-lifecycle-disposal-async-void
- feature-protocol-contract-discriminator-registry
- gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward
- gate-refactor-boundaries-lsp-diagnostic-wire-map
- gate-refactor-boundaries-protocol-env-read
- gate-refactor-documentation-pairing-coordinator-deps-jsdoc
- gate-refactor-lifecycle-bye-frames-race-relay-shutdown
- gate-refactor-lifecycle-owner-identity-watcher-no-dispose
- gate-refactor-lifecycle-owner-ingress-floating
- gate-refactor-lifecycle-relay-auth-timeout-listener
- gate-refactor-lifecycle-self-revoke-discards-async-detach
- gate-refactor-protocol-contract-owner-channel-binary-island
- gate-refactor-protocol-contract-relay-client-hello-auth-literals
- gate-refactor-protocol-contract-relay-transport-control-literals
- gate-refactor-protocol-contract-session-projection-type-literals
- gate-refactor-protocol-contract-sync-user-input-handwritten

### Cruft (5), docs (1), patterns (2)
- gate-cruft-plain-peer-channel-unused-disconnect-callback
- gate-cruft-qr-terminal-rotation-dead-path
- gate-cruft-relay-plan-era-comments
- gate-cruft-relay-test-bool-assertions
- gate-cruft-unused-settings-relay-url-compatibility
- gate-docs-cockpit-guidance-local-only-contradiction
- gate-patterns-inconsistency-pairing-coordinator-stale-capability
- gate-patterns-inconsistency-pair-request-flow-typed-decoder

### Binding-consistency warnings

`binding_guard: warn`, `epic_cohesion: phased` — 0 CONFLICTs, 2 INCOMPLETEs
(informational under phased; not acted on):

- INCOMPLETE — `story-mobile-transcript-reorder-after-backlog-flush` (drafting,
  unbound) has parent `feature-canonical-transcript-ordering` bound to v0.4.0.
- INCOMPLETE — `story-canonical-transcript-ordering-systematic-ts-provenance-sweep`
  (drafting, unbound) has parent `feature-canonical-transcript-ordering` bound to
  v0.4.0.

Both are legitimately in-flight children excluded from this release; they will
bind to a later release when they reach `done`.

## Gate runs

**Tiered-gate trial (2026-08-12)** — first cut under the tiered model (evaluation tracked in backlog-idea-evaluate-tiered-release-gates): full gates (security / tests / refactor / cruft / docs / patterns) on the 13 feature items; security-only regression on the 14 security-origin items.

Raw findings (pre-dedupe): refactor 4H/1M · security 0H/3M · security-regression 2H/2M/1L (12 of 14 prior fixes held) · tests 4H/1M · cruft 1H/4M · docs 3H/4M/1L · patterns 4 candidates.

Deduped to 6 distinct High root causes:
- 5 genuine v0.4.0 blockers — restart-marker cross-process race; broker audit-log oversized-predecessor regression; launchd plist-not-unlinked regression; hot-reload recoverable-delivery doc drift; (+Phase 8) refresh-dist marker mode, launchd deactivation postcondition.
- 1 cluster (5 highs) routed to the in-flight `canonical-transcript-timestamp-ownership` arc (NOT blocking v0.4.0).

Disposition: 6 bound fix stories driven to `done` via autopilot drain + Phase 8 (all verified, tests green, commits bbecb92/92c5c3f/caf9e8d/ebbac4c/b4c33ca/96b2faf). 3 deferred items + the timestamp cluster + 14 mediums/lows + 4 pattern candidates → `.work/backlog/`.

**Phase 8 completion review (standard weight, one pass):** 2 material blockers found in the drain fixes (refresh-dist marker mode; launchd deactivation postcondition) — both fixed + verified; 2 lower-risk parked (marker handoff race; audit-test fixed-sleep flake).
