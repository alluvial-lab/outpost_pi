---
id: release-v0.7.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Release v0.7.0

First gated release since v0.4.0 (v0.5.0 was tagged out-of-flow, bound
retroactively, gates post-hoc). This release claims everything since:
48 active done items + 7 late-bound archived stubs, spanning the upstream
harvest, the live-oddities + chaos e2e program (incl. nightly cadence and
skew drills), six mobile fix families (swallow/blank/dedup/working/churn/
reconnect UX), the fold/split-screen usability pass, debug-capture
delivery (schema+extension+app), the four routed v0.5.0 post-hoc gate
findings, and the CI emulator job.

## Bound items

- 48 active done items (see work-view --release v0.7.0): features
  upstream-harvest, e2e-live-oddities-suite, e2e-chaos-expansion,
  fold-usability-pass, debug-capture-delivery + all child stories +
  standalone fix stories + gate-* carryovers + story-ci-android-emulator-test-job.
- 7 late-bound archived stubs (unbound at gather; archived_atop retained
  as provenance).

### Binding-consistency warnings (guard: warn, cohesion: phased)

- CONFLICT ×4 resolved at bind: archived parent stubs
  epic-targeting-and-session-lifecycle-contracts and
  feature-reconnect-reproduction were unstamped v0.1.0-era leaks (children
  bound v0.1.0); stamped to v0.1.0 and removed from this bundle.
- INCOMPLETE ×3 fixed: three chaos-expansion stories missed by the
  work-view gather (index lag); bound directly.

## Gate runs

- **gate-tests** (2026-08-24) — 6 findings (High=5, Low=1; 5 coverage gaps, 1 low-value-test removal)

(planned: security, tests, cruft, docs, patterns, refactor — then manual UAT)

- **gate-security** (2026-08-24) — 2 findings (High=1, Medium=1; inline scanner, reduced isolation)
- **gate-patterns** (2026-08-24) — 7 patterns
- **gate-cruft** (2026-08-24) — 4 findings
- Scanner isolation: reduced — no subagent tool is exposed in this host; the deep documentation drift brief ran inline read-only.
- **gate-docs** (2026-08-24) — 21 findings
- **gate-refactor** (2026-08-24) — 8 findings


## Shipped

- **Date**: 2026-08-24
- **Mapping**: tag-based (`v0.7.0` tag; push external per conventions)
- **Items shipped**: 98 (93 active-bound moved here; 5 late-bound archived
  stubs remain in `.work/archive/` with bodies per retain-bodies)
- **Gate totals**: 41 findings fixed in-release; 7 patterns codified
- **UAT**: operator ack 2026-08-24 (field capture battery + manual pass;
  APK 0.7.2+14, extension 0.2.1 live, relay 0.5.1 unchanged)
- **Publishing**: local tag only — `git push origin main v0.7.0` is the
  operator's manual step (140+ commits ride together)

## Known issues at ship time

- Reconnect hedge: auth-read stall uncovered (~30s recovery) + late
  fallback supersede churn — found in UAT capture
  `debug/app-capture-2026-08-24T08-58-48-427Z-dd9fe9d1c3c6`; shipped per
  operator call with the fix scoped as
  `story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel`
  (first item of the post-v0.7.0 queue; in the nightly known-open
  inventory).

## Shipped items

Bodies live on disk (retain-bodies) here and in `.work/archive/` for stubs.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| feature-debug-capture-delivery | Deliver app debug captures directly to the paired Pi session | feature | — | cc0e516c |
| feature-e2e-chaos-expansion | Chaos expansion: exhaust the reachable fault space around the live-oddities harn | feature | — | cc0e516c |
| feature-e2e-live-oddities-suite | E2E suite for live-use transient oddities (capture-first + chaos/soak) | feature | — | cc0e516c |
| feature-fold-usability-pass | Fold / split-screen / large-resolution usability pass | feature | — | cc0e516c |
| feature-upstream-remote-pi-harvest | Upstream remote_pi harvest — 2026-08 divergence sweep (459 commits) | feature | — | cc0e516c |
| gate-cruft-duplicate-subagent-comment | Remove the superseded subagent message-end comment | story | — | cc0e516c |
| gate-cruft-empty-soak-expectation-scaffold | Remove the empty targeted-finding branch from the live soak | story | — | cc0e516c |
| gate-cruft-stale-pending-status-comments | Correct pre-reconnect semantics in pending-message comments | story | — | cc0e516c |
| gate-cruft-upload-single-slot-limit | Remove the numeric max-inflight abstraction from the single-slot capture upload | story | — | cc0e516c |
| gate-docs-agent-reference-refresh-post-v050 | Refresh the agent reference surface after the v0.5.0 dependency refresh | story | — | cc0e516c |
| gate-docs-app-claude-analyzer-anchor | App analyzer guidance points at the old input-bar line | story | — | cc0e516c |
| gate-docs-app-claude-retired-plan | App guidance points agents at the retired plan/ directory | story | — | cc0e516c |
| gate-docs-architecture-capture-union | Architecture wire-union lists omit the shipped capture-upload family | story | — | cc0e516c |
| gate-docs-architecture-room-meta-drift | Architecture still claims TS and Dart room metadata drift | story | — | cc0e516c |
| gate-docs-changelog-v051-v070-gaps | Changelog stops at v0.5.0 while later artifacts shipped | story | — | cc0e516c |
| gate-docs-cockpit-rpc-readme | Cockpit README presents the compatibility RPC as the active transport | story | — | cc0e516c |
| gate-docs-e2e-live-selector-pin-guard | E2E README omits live selectors and the pinless-AVD guard | story | — | cc0e516c |
| gate-docs-flutter-mobile-ping-interval | Flutter mobile skill documents the obsolete WebSocket ping interval | story | — | cc0e516c |
| gate-docs-pattern-explicit-interleaving-anchor | Async-interleaving pattern points at the wrong Pi-host harness line | story | — | cc0e516c |
| gate-docs-pattern-generation-fenced-anchors | Generation-fenced pattern anchors no longer quote the current implementations | story | — | cc0e516c |
| gate-docs-pattern-identity-watermark-anchors | Identity-watermark pattern anchors point at unrelated storage code | story | — | cc0e516c |
| gate-docs-pattern-palette-anchor | Paired-palette pattern anchors no longer show theme resolution | story | — | cc0e516c |
| gate-docs-pattern-pane-teardown-anchor | Pane-teardown pattern points at terminal paste code | story | — | cc0e516c |
| gate-docs-pattern-resource-policy-anchor | Centralized-resource pattern cache anchor no longer shows eviction | story | — | cc0e516c |
| gate-docs-pattern-snapshot-replay-anchor | Snapshot-replay pattern points at a non-mapper extension line | story | — | cc0e516c |
| gate-docs-pattern-stale-capability-anchors-v070 | Stale-capability pattern anchors drifted again after session hardening | story | — | cc0e516c |
| gate-docs-pattern-subscription-anchor | Subscription pattern points at mesh send code | story | — | cc0e516c |
| gate-docs-pi-capture-protocol-list | Pi extension skill protocol lists omit capture-upload messages | story | — | cc0e516c |
| gate-docs-protocol-island-scan-rule | Protocol scan rule still treats generated Dart relay frames as an island | story | — | cc0e516c |
| gate-docs-readme-app-version | Root README pins sideload status to the obsolete app-v0.3.x | story | — | cc0e516c |
| gate-docs-spec-owner-multiplexer | SPEC describes the obsolete singleton owner channel | story | — | cc0e516c |
| gate-patterns-v0.7.0 | Patterns extracted for v0.7.0 | story | — | cc0e516c |
| gate-refactor-documentation-chat-page-component | Document the adaptive chat-page component contract | story | — | cc0e516c |
| gate-refactor-documentation-debug-log-service | Attach the debug-log service contract to its public implementation | story | — | cc0e516c |
| gate-refactor-documentation-input-bar-component | Convert the input composer contract to native dartdoc | story | — | cc0e516c |
| gate-refactor-documentation-malformed-envelope-handler | Document the relay malformed-envelope escape hatch | story | — | cc0e516c |
| gate-refactor-lifecycle-capture-upload-runtime | Fence capture finalization and its timer to the owning runtime | story | — | cc0e516c |
| gate-refactor-lifecycle-connect-fallback-cancellation | Complete a superseded reconnect hedge even when its factories remain pending | story | — | cc0e516c |
| gate-refactor-lifecycle-pairing-dialog-stale-context | Reacquire the Pi UI before opening the pairing dialog | story | — | cc0e516c |
| gate-refactor-protocol-broker-room-control-literals | Derive broker room-control sends from the generated discriminator registry | story | — | cc0e516c |
| gate-security-capture-upload-chunk-amplification | Bound capture-upload chunk and event-count amplification | story | — | cc0e516c |
| gate-security-capture-upload-disk-quota | Bound cumulative disk use for delivered debug captures | story | — | cc0e516c |
| gate-security-release-workflow-action-pinning | Pin mutable GitHub Actions refs in the release workflows (signing/publishing aut | story | — | cc0e516c |
| gate-tests-backfill-anchor-interleavings | Exercise viewport-anchor revision fences before the queued restore runs | story | — | cc0e516c |
| gate-tests-capture-uploader-failure-matrix | Cover capture-upload transport loss, deadlines, and malformed acknowledgements | story | — | cc0e516c |
| gate-tests-concurrent-first-run-pairing-race | Deterministic coverage for the concurrent first-run pairing race | story | — | cc0e516c |
| gate-tests-mobile-scanner-v7-boundary | Exercise the real mobile_scanner v7 QR boundary after the 5→7 major bump | story | — | cc0e516c |
| gate-tests-nightly-findings-fail-closed | Make the nightly findings reconciler prove every alert class fails closed | story | — | cc0e516c |
| gate-tests-reconnect-supervisor-edge-coverage | Prove reconnect supersession closes every losing authenticated channel | story | — | cc0e516c |
| gate-tests-rework-fold-matrix-duplicates | Remove byte-identical fold-matrix captures and vacuous file assertions | story | — | cc0e516c |
| gate-tests-two-pane-keyboard-router-seam | Drive keyboard ownership through the production two-pane router | story | — | cc0e516c |
| story-app-send-swallowed-session-identity-unavailable | sendMessage silently drops the message when session identity is unavailable | story | — | cc0e516c |
| story-capture-delivery-app-upload | Capture upload: app quick action + chunked upload client + progress UX | story | — | cc0e516c |
| story-capture-delivery-e2e | Capture upload: live two-side e2e + triage compatibility | story | — | cc0e516c |
| story-capture-delivery-protocol-extension | Capture upload: schema, codegen, extension handler, session note | story | — | cc0e516c |
| story-ci-android-emulator-test-job | CI Android emulator job for device-gated integration tests | story | — | cc0e516c |
| story-e2e-chaos-clock-version-skew | Clock skew + version-skew drills | story | — | cc0e516c |
| story-e2e-chaos-fault-moment-grid | Deterministic fault×moment grid | story | — | cc0e516c |
| story-e2e-chaos-fault-vocabulary | Fault vocabulary: degradation toxics, relay kill, compound faults | story | — | cc0e516c |
| story-e2e-chaos-mesh-lane | Mesh lane: second Pi, cross-Pi delivery | story | — | cc0e516c |
| story-e2e-chaos-nightly-cadence | Nightly seeded soak cadence | story | — | cc0e516c |
| story-e2e-chaos-oracle-invariants | Oracle invariants: replay dedup, DB↔UI consistency, ordering, identity stability | story | — | cc0e516c |
| story-e2e-chaos-state-shapes | State shapes: multi-session, re-pair cycles, long uptime | story | — | cc0e516c |
| story-e2e-oddities-capture-triage | Capture-first: decode/triage tooling for the debug-capture rings | story | — | cc0e516c |
| story-e2e-oddities-chaos | Chaos soak: randomized fault schedule against the four invariants | story | — | cc0e516c |
| story-e2e-oddities-failure | Failure-mode device tests incl. the parked-oddity regression scenarios | story | — | cc0e516c |
| story-e2e-oddities-golden | Golden-path device tests: pair → chat → persist → cold-open render | story | — | cc0e516c |
| story-e2e-oddities-harness-infra | Device-lane harness infrastructure: emulator app × compose stack | story | — | cc0e516c |
| story-fix-app-backfill-anchor-fights-user-scroll | Backfill viewport anchoring restores stale anchors and fights user scroll | story | — | cc0e516c |
| story-fix-app-backfill-reflow-viewport | Interrupted-turn backfill on reconnect reflows the visible transcript (perceived | story | — | cc0e516c |
| story-fix-app-blank-chat-direct-open | Render persisted history when opening directly into an existing chat | story | — | cc0e516c |
| story-fix-app-blanked-projection-during-churn | Blank chat during churn: dedup drops all replay while projection is unbuilt | story | — | cc0e516c |
| story-fix-app-cold-replay-duplicates-persisted-transcript | Prevent cold replay from duplicating persisted transcript rows | story | — | cc0e516c |
| story-fix-app-compact-composer-ime-loop | Keep the Android keyboard attached through compact-composer transitions | story | — | cc0e516c |
| story-fix-app-concurrent-replay-admission-race | Concurrent hydration paths admit duplicate replay events (reordering/duplication | story | — | cc0e516c |
| story-fix-app-connect-supervisor-duplicate-auth-cycle | Connect supervisor races itself: same-device duplicate auth cycles every 2-11s | story | — | cc0e516c |
| story-fix-app-offline-working-state-flap | Room working-state flaps idle every ~10s while disconnected instead of holding a | story | — | cc0e516c |
| story-fix-app-reconnect-churn-timeout-lifecycle-failures | Attribute reconnect churn timeout lifecycle failures | story | — | cc0e516c |
| story-fix-app-reconnect-stale-first-attempt | First reconnect attempt after a drop stalls the full 10s; immediate retry succee | story | — | cc0e516c |
| story-fix-app-replay-silently-dropped-on-session-rotation | Replay batch silently dropped when the session rotated during a disconnect windo | story | — | cc0e516c |
| story-fix-app-session-rotation-late-echo-sticks-working | Keep completed rooms idle when a late user echo arrives | story | — | cc0e516c |
| story-fix-mesh-post-pair-roster-bootstrap-empty | Bootstrap mesh roster when membership arrives during bridge attachment | story | — | cc0e516c |
| story-fix-soak-identity-window-submission-drop | Preserve submissions raced by reconnect generation changes | story | — | cc0e516c |
| story-fold-chat-adaptivity | Chat adaptivity: compact keyboard-landscape, compact narrow headers, wide readin | story | — | cc0e516c |
| story-fold-golden-harness-fidelity | Golden render matrix must be trustworthy (fonts, isolation, overflow-as-failure, | story | — | cc0e516c |
| story-fold-home-sheets-adaptivity | Home + sheets adaptivity: compact narrow header, wide list cap, height-adaptive  | story | — | cc0e516c |
| story-fold-system-pages-a11y-floors | System pages responsive-center + touch-target and type floors | story | — | cc0e516c |
| story-fold-two-pane-policy | Two-pane eligibility needs master+min-detail; divider contrast; keyboard isolati | story | — | cc0e516c |
| story-harvest-app-session-robustness-ports | App session robustness ports: reconnect room preservation + iOS onboarding gate | story | — | cc0e516c |
| story-harvest-app-working-idle-reconciliation | Working-state reconciliation: authoritative idle beats stale transcript.working | story | — | cc0e516c |
| story-harvest-cockpit-crash-class-ports | Cockpit crash-class ports: deleted-workspace recovery + bounded Hive-open retry | story | — | cc0e516c |
| story-harvest-extension-robustness-ports | Extension robustness ports: keyring timeouts, identity precedence, print guard | story | — | cc0e516c |
| story-harvest-mesh-ingress-queueing | Queue Pi-to-Pi mesh messages between agent runs | story | — | cc0e516c |
| story-harvest-relay-overlapping-owner-auth | Overlapping-owner mesh authorization is order-dependent (first match wins) | story | — | cc0e516c |
| idea-mobile-drop-slow-recovery | Mobile network drop: slow end-to-end recovery (~5 min) | story | — | cc0e516c |
| idea-mobile-outgoing-message-swallowed | Mobile: outgoing user message swallowed (not delivered, not surfaced) | story | — | cc0e516c |
| story-mobile-send-timeout-relay-room-main-mismatch | Phone user message "not delivered" — relay sees `room=main` while app believes ` | story | — | cc0e516c |
| story-reconnect-derived-contract-claims-audit | Audit reconnect-derived contract claims after the physical drop trace | story | — | cc0e516c |
