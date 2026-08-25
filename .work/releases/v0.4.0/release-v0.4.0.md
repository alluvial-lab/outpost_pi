---
id: release-v0.4.0
kind: release
stage: released
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

Disposition: 6 bound fix stories driven to `done` via autopilot drain + Phase 8 (all verified, tests green, commits 053b1e6/e390c7a/51a4e1a/4fb6889/722e9e7/0811de9). 3 deferred items + the timestamp cluster + 14 mediums/lows + 4 pattern candidates → `.work/backlog/`.

**Phase 8 completion review (standard weight, one pass):** 2 material blockers found in the drain fixes (refresh-dist marker mode; launchd deactivation postcondition) — both fixed + verified; 2 lower-risk parked (marker handoff race; audit-test fixed-sleep flake).

## Shipped items

Bodies retained on disk (retain-bodies) under `release_binding: v0.4.0`.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| feature-boundary-typed-decoders | Boundary typed-decoder convergence | feature | — | bf9803a |
| feature-secure-transcript-key-loss-recovery-ux | Secure-transcript key-loss recovery UX | feature | — | bf9803a |
| feature-protocol-contract-discriminator-registry | Protocol-contract discriminator single-source-of-truth | feature | — | bf9803a |
| feature-extension-hot-reload-via-process-restart | Extension hot-reload via process restart (since `/reload` can't load ESM dist) | feature | — | bf9803a |
| feature-canonical-transcript-ordering | Canonical transcript ordering (server-ts provenance + render sort) | feature | — | bf9803a |
| feature-lifecycle-disposal-async-void | Lifecycle disposal + unguarded-async-void convergence | feature | — | bf9803a |
| gate-refactor-protocol-contract-owner-channel-binary-island | Binary owner-channel format is an undocumented protocol island | story | — | bf9803a |
| story-new-session-restart-fresh-restart-mechanism | /new from mobile: restart-without-continue mechanism (wrapper) | story | — | bf9803a |
| gate-security-orphaned-pre-rebrand-launchd-daemon | Launchd identifier cutover leaves the pre-rebrand daemon running | story | — | bf9803a |
| story-canonical-transcript-ordering-app-consume-tool-ts | App consumes server ts on live tool frames | story | — | bf9803a |
| story-fix-working-flag-stuck-after-session-shutdown | App's working indicator stuck true after a session shutdown during an active t | story | — | bf9803a |
| gate-tests-offline-buffer-per-peer-isolation | Cover independent buffering and cap accounting for simultaneous offline owners | story | — | bf9803a |
| gate-security-presence-offline-timestamps-unbounded | Presence offline timestamps retain attacker-created peer identities forever | story | — | bf9803a |
| story-canonical-transcript-ordering-extension-broadcast-tool-ts | Extension broadcasts canonical server ts on live tool frames | story | — | bf9803a |
| gate-tests-debug-log-literal-success-assertions | Two debug-log tests retain prohibited literal-success assertions | story | — | bf9803a |
| gate-security-ci-mutable-action-refs | CI executes mutable action references | story | — | bf9803a |
| gate-refactor-lifecycle-bye-frames-race-relay-shutdown | Secure-channel bye frames race relay shutdown | story | — | bf9803a |
| gate-refactor-protocol-contract-relay-client-hello-auth-literals | Relay authentication handwrites generated hello and auth types | story | — | bf9803a |
| gate-security-broker-audit-log-oversized-predecessor-regression | Broker audit log: oversized predecessor bypasses the 256 KiB ceiling | story | — | bf9803a |
| gate-cruft-plain-peer-channel-unused-disconnect-callback | Plain peer channel retains a suppressed, unused disconnect callback | story | — | bf9803a |
| gate-security-compaction-replay-keys-unbounded | Compaction replay-suppression keys grow for the full owner-channel lifetime | story | — | bf9803a |
| gate-security-debug-log-fallback-raw-exceptions | Debug-log fallback prints raw exceptions and stack traces | story | — | bf9803a |
| gate-tests-mesh-auth-cache-ttl | Cover mesh-authorization cache expiry and refresh | story | — | bf9803a |
| story-hot-reload-lifecycle-fence | Hot-reload: lifecycle fence + M2/M4 hardening | story | — | bf9803a |
| gate-security-secure-transcript-key-loss-recovery-ux | No recovery path after secure-storage key loss (fail-closed bricks startup) | story | — | bf9803a |
| gate-cruft-qr-terminal-rotation-dead-path | Unreachable legacy QR terminal rotation path remains in the extension | story | — | bf9803a |
| gate-security-unindexed-plaintext-transcripts-retained | Migration can complete while unindexed plaintext transcript boxes remain | story | — | bf9803a |
| gate-security-cockpit-agent-boot-path-debugprint | Agent boot debugPrints the absolute workspace path | story | — | bf9803a |
| gate-cruft-unused-settings-relay-url-compatibility | Remove unused Settings relay-URL compatibility projection | story | — | bf9803a |
| gate-refactor-lifecycle-self-revoke-discards-async-detach | Self-revoke discards asynchronous owner-channel teardown | story | — | bf9803a |
| gate-refactor-lifecycle-owner-ingress-floating | Observe asynchronous owner-ingress routing failures | story | — | bf9803a |
| gate-tests-sync-service-noecho-wallclock-timing | sync_service no-echo cases race the production 60ms timer under load | story | — | bf9803a |
| story-hot-reload-agent-settled-hook-and-wrapper | Hot-reload v2: PID-scoped arming + agent_settled quiescing gate + graceful SIG | story | — | bf9803a |
| gate-refactor-restart-marker-cross-process-race | Restart wrapper consumes any sibling Pi process's marker | story | — | bf9803a |
| gate-refactor-boundaries-lsp-diagnostic-wire-map | Decode LSP diagnostic maps at the adapter boundary | story | — | bf9803a |
| gate-refactor-lifecycle-owner-identity-watcher-no-dispose | Owner identity watcher is registered without lifecycle disposal | story | — | bf9803a |
| story-new-session-restart-fresh-extension-exit | /new from mobile: extension exits for a fresh session (interactive) | story | — | bf9803a |
| gate-tests-localboxes-restart-preservation | LocalBoxes.init restart preservation is only partially covered | story | — | bf9803a |
| gate-tests-codegen-number-only-partition | Codegen conditional-helper tests miss the number-only partition | story | — | bf9803a |
| gate-cruft-relay-plan-era-comments | Rewrite plan-era relay comments as current-state contracts | story | — | bf9803a |
| story-canonical-transcript-ordering-projection-render-sort | Projection renders authoritative bubbles in canonical server-ts order | story | — | bf9803a |
| story-canonical-transcript-ordering-ts-provenance-audit | Audit remaining live DateTime.now() paths for ts provenance | story | — | bf9803a |
| gate-refactor-lifecycle-relay-auth-timeout-listener | Relay auth timeout leaves its challenge listener attached | story | — | bf9803a |
| story-mesh-reconciliation-deletes-pairing-channel | Mesh reconciliation deletes the local pairing's channel keys (pairing oscillat | story | — | bf9803a |
| gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward | Parse mesh-members blobs through a typed boundary DTO | story | — | bf9803a |
| gate-patterns-inconsistency-pair-request-flow-typed-decoder | pair_request_flow decodes the untrusted pairing response with raw jsonDecode | story | — | bf9803a |
| gate-docs-cockpit-guidance-local-only-contradiction | Reconcile Cockpit's local-only guidance with its active control overlay | story | — | bf9803a |
| gate-refactor-documentation-pairing-coordinator-deps-jsdoc | Pairing coordinator dependency contract lacks JSDoc | story | — | bf9803a |
| story-v040-launchd-deactivation-postcondition | Legacy launchd deactivation is unverified and can silently fail | story | — | bf9803a |
| gate-cruft-relay-test-bool-assertions | Replace clippy-rejected boolean equality assertions in relay tests | story | — | bf9803a |
| gate-security-local-ipc-permissions | Supervisor control socket relies on ambient filesystem permissions | story | — | bf9803a |
| gate-refactor-boundaries-protocol-env-read | relay/src/protocol/outer.rs:34 | story | — | bf9803a |
| story-v040-refresh-dist-marker-mode | refresh-dist.sh creates markers the hardened wrapper rejects | story | — | bf9803a |
| gate-tests-pairing-qr-rpc-mode-no-seam-untested | showPairQr in non-TUI mode without the seam is untested | story | — | bf9803a |
| gate-security-windows-path-separator-validation | File name validation misses Windows path separators | story | — | bf9803a |
| gate-tests-relay-heartbeat-first-tick | Relay heartbeat first-tick timing has only partial test coverage | story | — | bf9803a |
| story-fix-onconnected-clobbers-working-midturn | `onConnected` publishes unconditional `working=false`, clobbering a genuine mi | story | — | bf9803a |
| gate-patterns-inconsistency-pairing-coordinator-stale-capability | pairing_coordinator listDevices dereferences captured ctx.ui after await | story | — | bf9803a |
| gate-docs-hot-reload-recoverable-delivery-drift | Hot-reload docs/comments claim a recoverable-delivery contract the code does n | story | — | bf9803a |
| gate-security-plaintext-pair-error-internal-details | Plaintext pairing errors expose raw internal failures to the relay | story | — | bf9803a |
| gate-security-cockpit-stale-pair-dir-orphan-sweep | Cockpit crash orphans the token-bearing pair seam directory | story | — | bf9803a |
| gate-refactor-protocol-contract-session-projection-type-literals | Session projection re-enumerates generated server message types | story | — | bf9803a |
| gate-refactor-protocol-contract-sync-user-input-handwritten | Live user-input identity uses a handwritten generated discriminator | story | — | bf9803a |
| gate-security-launchd-plist-not-unlinked-regression | Legacy launchd plist survives cleanup and can resurrect the old daemon | story | — | bf9803a |
| gate-security-broker-audit-log-unbounded | Local mesh audit log grows without a retention bound | story | — | bf9803a |
| gate-refactor-protocol-contract-relay-transport-control-literals | Relay transport duplicates generated control-frame types | story | — | bf9803a |

_Shipped 2026-08-12 · mapping: tag-based · 66 items · tiered-gate trial · Phase 8 standard_
