---
id: release-v0.9.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Release v0.9.0

Feature-lane minor cut: the 2026-08-26 autopilot drain (8 features, 22
standalone stories) + one late-bound archived stub. Includes the
operator-authorized public-history rescrub (cache residual accepted).

## Bound items

40 active done items (drain output; research child excluded as input) + 1
late-bound archived stub (gate-tests-fakesession-buildcontext-duplicate-
projection, done, never claimed by a prior release).

## Gate runs

### Gate runs
- **gate-tests** (2026-08-26) — 3 findings (High=1 bound: relay-failover production-seam interface coverage; Medium=2 backlog: brand-parser rejection matrix, cockpit fail-once commit recovery). Inline scanner, reduced isolation. Commit 0ceb8417.
- **gate-cruft** (2026-08-26) — 2 findings (High-conf medium: unused sync read-barrier seam; Med-conf low: unused Pi-host readiness helper; both ambient → backlog unbound, 0 release-blocking). Inline scan, reduced isolation. Commit 3e9dbe6e.
- **gate-security** (2026-08-26) — 3 findings (High=1 bound: custom-scheme pairing-token hijack via non-exclusive outpostpi:// deeplink; Medium=1 backlog: revocation retains pending outbox prompts; Low=1 backlog: cockpit JSON ambient perms). 9 domains audited inline, reduced isolation. Commit 0bb7a8d6.
- **gate-docs** (2026-08-26) — 11 findings (High-conf=4 bound: TLS overclaim in SPEC+ARCHITECTURE, relay README ws:// misconfig, missing v0.9.0 changelog entry, stale retry guidance vs outbox contract; Medium-conf=7 backlog: Playwright/check omissions, pattern staleness, §ref + plan/ links). Inline audit, reduced isolation. Commit e9e4f286.
- **gate-patterns** (2026-08-26) — 5 patterns cataloged (deterministic-completion-barriers, break-it-proof-regression-discipline, reachable-blob-history-content-scanning, atomic-snapshot-store-marker-last-migration, dual-execution-path-contract-documentation) + generation-fenced-async-ownership extended; catalog 36 indexed, digest verified; tracking item. Inline discovery, reduced isolation. Commit eb466329.
- **gate-refactor** (2026-08-26) — 9 findings (High=2 bound: owner_multiplexer pair-request + compaction discriminator hand-enumerations vs generated schema; Medium=7 backlog: lifecycle ownership across owner_multiplexer/relay_transport/cockpit main/file_viewer). 3 libraries loaded, boundaries clean. Inline scan, reduced isolation. Commit 5210ccf6.

## Shipped items

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| feature-cockpit-storage-json-vs-hive | Cockpit storage: evaluate JSON stores vs Hive (upstream 0802 | feature | — | f76ca4df9 |
| feature-cruft-consolidated-cleanup | Consolidated cruft cleanup (one behavior-preserving [refacto | feature | — | f76ca4df9 |
| feature-doc-drift-repair | Documentation drift repair (v0.4.0 + v0.5.0 batches, one pro | feature | — | f76ca4df9 |
| feature-fresh-session-shutdown-and-recoverable-delivery | Fresh-session shutdown + recoverable-delivery contract | feature | — | f76ca4df9 |
| feature-mobile-slash-command-invocation | Mobile command invocation (dedicated-operations model) | feature | — | f76ca4df9 |
| feature-public-flip-branding-and-exposure | Public flip: branding holdover cleanup + private-layer expos | feature | — | f76ca4df9 |
| feature-site-test-baseline | Site test baseline (with light/dark contract as first covera | feature | — | f76ca4df9 |
| feature-theme-token-cross-surface-contract | Theme token cross-surface contract (generate/golden the port | feature | — | f76ca4df9 |
| app-hydration-truncated-flag-not-surfaced | Session hydration truncation is invisible in the app | story | — | f76ca4df9 |
| app-relay-url-network-failover | Single relay URL leaves the app fully down when its network  | story | — | f76ca4df9 |
| backlog-app-no-outpostpi-deeplink-intent-filter | `outpostpi://` scheme parsed by the app but not declared as  | story | — | f76ca4df9 |
| backlog-cockpit-file-watch-reliability | Cockpit file-watch reliability (merged from 3 findings) | story | — | f76ca4df9 |
| backlog-ext-broker-no-reconnect-after-boot-tailscale-rebind | Broker holds no relay socket after VM reboot + tailscale lin | story | — | f76ca4df9 |
| backlog-peers-lock-restore-collision-safety | peers.lock restore-on-mismatch is not collision-safe | story | — | f76ca4df9 |
| backlog-relay-transport-stale-generation-active-dispatch | Generation-owned cancellation for in-flight relay dispatches | story | — | f76ca4df9 |
| feature-cockpit-storage-json-vs-hive-legacy-migration | Add storage paths and one-shot Hive export | story | — | f76ca4df9 |
| feature-cockpit-storage-json-vs-hive-remove-hive-runtime | Cut bootstrap over and remove Hive from the live runtime | story | — | f76ca4df9 |
| feature-cockpit-storage-json-vs-hive-repository-adapters | Replace repository adapters behind existing domain contracts | story | — | f76ca4df9 |
| feature-cockpit-storage-json-vs-hive-storage-port-json-store | Define the state-store port and atomic JSON adapter | story | — | f76ca4df9 |
| feature-cruft-consolidated-cleanup-step-1-app | Consolidated cruft cleanup: app | story | — | f76ca4df9 |
| feature-cruft-consolidated-cleanup-step-2-relay | Consolidated cruft cleanup: relay | story | — | f76ca4df9 |
| feature-cruft-consolidated-cleanup-step-3-pi-extension | Consolidated cruft cleanup: pi-extension hot-reload expiry c | story | — | f76ca4df9 |
| feature-fresh-session-shutdown-and-recoverable-delivery-boundary-e2e-proof | Prove quiesce-to-reconnect recovery across the owner channel | story | — | f76ca4df9 |
| feature-fresh-session-shutdown-and-recoverable-delivery-durable-mobile-resend | Persist and replay unconfirmed owner submissions on recovery | story | — | f76ca4df9 |
| feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain | Replace fixed-delay fresh exit with the lifecycle-owned drai | story | — | f76ca4df9 |
| feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract | Define the recoverable owner-delivery wire signal | story | — | f76ca4df9 |
| feature-public-flip-branding-and-exposure-brand-evidence-closure | Close the residual brand-evidence gap without restoring stal | story | — | f76ca4df9 |
| feature-public-flip-branding-and-exposure-history-rescrub | Rescrub the one post-flip leak from public refs | story | — | f76ca4df9 |
| feature-public-flip-branding-and-exposure-public-tree-guard | Redact the post-flip exposure regression and add a public-tr | story | — | f76ca4df9 |
| feature-site-test-baseline-computed-style-contract | Establish the browser-backed site theme contract | story | — | f76ca4df9 |
| feature-site-test-baseline-route-smoke-and-workflow | Add a thin production-route smoke baseline | story | — | f76ca4df9 |
| feature-theme-token-cross-surface-contract-app-theme-properties | Bind the mobile theme port to the shared dual-mode contract | story | — | f76ca4df9 |
| feature-theme-token-cross-surface-contract-cockpit-theme-properties | Bind the cockpit theme port to the shared dual-mode contract | story | — | f76ca4df9 |
| feature-theme-token-cross-surface-contract-contract-tooling | Establish the shared brand-contract fixture and canonical ma | story | — | f76ca4df9 |
| gate-docs-changelog-v090-user-visible-drain | CHANGELOG has no v0.9.0 entry for the shipped user-visible c | story | — | f76ca4df9 |
| gate-docs-foundation-transport-tls-claim | Foundation transport documentation claims relay WebSockets a | story | — | f76ca4df9 |
| gate-docs-mobile-retry-semantics-stale | Mobile remote-coding skill still promises idempotent-or-reje | story | — | f76ca4df9 |
| gate-docs-relay-readme-http-url-scheme | Relay README tells users to configure rejected WebSocket URL | story | — | f76ca4df9 |
| gate-patterns-v0.9.0 | Patterns extracted for v0.9.0 | story | — | f76ca4df9 |
| gate-refactor-protocol-contract-owner-multiplexer-compaction-discriminator | Owner multiplexer re-enumerates the generated compaction dis | story | — | f76ca4df9 |
| gate-refactor-protocol-contract-owner-multiplexer-pair-discriminator | Owner multiplexer re-enumerates the generated pair-request d | story | — | f76ca4df9 |
| gate-review-cockpit-bootstrap-wiring-test | Cockpit Hive bootstrap wiring needs an injectable boundary t | story | — | f76ca4df9 |
| gate-security-combined-app-verification-flaky | Combined app verification command is flaky | story | — | f76ca4df9 |
| gate-security-custom-scheme-pair-token-hijack | Android custom-scheme pairing links expose the enrollment to | story | — | f76ca4df9 |
| gate-security-postcss-override-vulnerable | pnpm overrides pin PostCSS to a version vulnerable to source | story | — | f76ca4df9 |
| gate-tests-app-relay-failover-production-seam | Exercise configured-to-paired relay failover through the pro | story | — | f76ca4df9 |
| story-identity-boot-restore-race | Fresh-install identity boot generates before the Block Store | story | — | f76ca4df9 |
| story-mobile-transcript-reorder-after-backlog-flush | Transcript reordered on phone after backlog flush + reconnec | story | — | f76ca4df9 |
| story-per-device-slim-release-apk | Per-device slim release APK | story | — | f76ca4df9 |
| gate-tests-fakesession-buildcontext-duplicate-projection | FakeSession.buildContext is a duplicate projection, not a bo | story | — | f76ca4df9 |

## Shipped

- **Date**: 2026-08-26 (rc.1 tagged; publish operator-gated per UAT)
- **Mapping**: tag-based (local tag; push external per conventions)
- **Items shipped**: 50 (41 bound at gate + 7 gate-blockers fixed in-release + changelog + patterns tracking)
- **Gate totals**: security 3 (1H bound-fixed) · tests 3 (1H bound-fixed) · cruft 2 (0 blocking) · docs 11 (4H bound-fixed) · patterns 5 cataloged +1 ext · refactor 9 (2H bound-fixed) — 9 medium/low parked unbound
- **Final verification**: app 979/979 · e2e 17/17 · extension 1103/3 · relay 234 + fmt/clippy · cockpit 316 · site check green · protocol 7/7 · exposure guard PASS
- **Operator UAT**: run docs/release-uat.md incl. pm verify-app-links checks; site deploy precedes app/extension rollout (assetlinks.json)

## rc UAT record (2026-08-26)

- **rc.1** — field captures (3 analyzed). All transport invariants green
  (0 swallowed sends, dedup/ordering oracles ok, clean reconnect ladder).
  Found + fixed: sticky failed-bubble (UserMessageConfirmed never cleared
  _failedUsers; red badge survived echo until a replay rebuild — the
  "flakey resync" operator report). Fix 53a9fef99, break-it-proven
  regressions, suite 981/981. Draft superseded (deleted; tag kept).
- **rc.2** — operator field-verified the airplane-mode send: message held
  offline, redelivered on reconnect exactly once, **bubble cleared to
  delivered** (the fix confirmed live). "Bubble behaved better now."
- Remaining known-untested in field: force-quit cold-start outbox
  recovery (covered by suite tests), App Links tap-through (assetlinks
  live; verified in emulator/merged-manifest; pm check still operator-
  optional).
