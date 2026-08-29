---
id: release-v0.11.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# Release v0.11.0

Feature-lane minor cut (two-lane slicing). Per CONVENTIONS: six gates, FULL
e2e battery before publish (run-pairing.sh docker suite + live lanes +
600s seeded chaos soak), rc flow with operator UAT checkpoint, tag-based
mapping (local tag, operator pushes), retain-bodies.

## Bound items (12)

Direct (this batch):
- story-offline-state-liveness-ux
- story-pair-code-clipboard-copy
- feature-background-work-working-state
- story-background-work-ext-tracker
- story-background-work-app-surface
- story-fix-midstream-hydrate-reorder-flicker
- story-fix-stale-ime-watchdog-single-shot
- story-cleanup-ext-sdk084-compat-batch
- story-cleanup-app-flutter347-deprecations

Pre-session unbound stragglers (code shipped in v0.10.x APKs; substrate
first-bound here):
- story-fix-app-stale-ime-inset
- story-mobile-extension-command-invocation
- story-system-status-events-in-agent-turn-stream

## Gate runs
(populated as gates run)

- 2026-08-28 — `tests`: inline scanner (reduced isolation per orchestrator adaptation); audited 12 bound items / 92 commit-union paths; 3 findings (High=1, Medium=1, Low=1), with 1 release-blocking story and 2 unbound backlog items; skip list contained 6 prior gate-tests items, 0 duplicate candidates skipped.
- 2026-08-28 — `docs`: inline scanner (reduced isolation per orchestrator adaptation); audited 12 bound items / 92 commit-union paths; 10 findings (foundation-doc-assertion=1, changelog-gap=1, repo-skill-staleness=4, pattern-skill-staleness=4), with 2 high-severity release-bound stories and 8 medium/low unbound backlog items; skip list contained 7 prior gate-docs items, 0 duplicate candidates skipped.
- 2026-08-28 — `patterns`: inline source-read-only scanner (reduced isolation per orchestrator adaptation); audited 12 bound items / 92 commit-union paths; 3 new patterns codified, 0 inconsistencies; existing durable-first/edge-triggered patterns and sub-three-occurrence watchdog/timestamp candidates skipped; skip list included existing gate-patterns items and the canonical 36-pattern catalog.
- **gate-refactor** (2026-08-28) — 0 findings (0 high, 0 medium, 0 low) from 3 libraries: boundaries (0), lifecycle (0), protocol-contract (0). Inline rule check per orchestrator adaptation (no nested scanner); 5 already-tracked findings skipped.
- **gate-cruft** (2026-08-28) — inline deep cleanup scan (reduced isolation per orchestrator adaptation; no nested scanner); audited 12 bound items / 92 commit-union paths; 5 findings (High=1, Medium=4, Low=0), with 1 release-relevant blocking story and 4 ambient unbound backlog items; 0 decision-required findings; 4 already-tracked gate-cruft findings skipped.
- 2026-08-28 — `security`: inline source-read-only scanner (reduced isolation per orchestrator adaptation; no nested scanner); audited 12 bound items / 92 commit-union paths across auth, crypto, secrets, injection, API, infrastructure, data-protection, dependency, and error/logging domains; 2 findings (Critical=0, High=0, Medium=1, Low=1), both routed to unbound backlog; skip list contained 3 live prior-release gate-security items, 0 duplicate candidates skipped.

## Battery + rc record (2026-08-28)

- Full e2e battery GREEN 23:11:16Z: run-pairing docker suite (18), live
  lanes golden/failure/state-shapes/grid/capture-delivery, 600s seeded
  chaos soak. (First battery attempt aborted on an orchestrator arg
  error — lane names vs file paths; resumed, all green. Log:
  .work/session-notes/v0110-battery.log.)
- App version bumped 0.10.1+24 → 0.11.0+25 (135bc3b24); first rc build
  had stale version artifacts — caught and rebuilt.
- v0.11.0-rc.1 draft: fat outpost-0.11.0-25.apk (197MiB) + slim arm64
  outpost-0.11.0-25-arm64.apk (31MiB), release-signed, attached.
- apk-launch-smoke: SKIPPED, recorded reason — emulator torn down
  post-battery and this is not a toolchain-swap candidate; five live
  lanes + soak exercised emulator install/launch/resume on the debug
  build this session. Operator may run it from the draft artifacts
  before publish.
- Post-UAT diagnosis landed before the final tag: the extension's 79-byte
  `background:true` patch was present on the live wire but rejected as
  `invalid_json` by the stale 2026-08-23 relay image, which predates the
  `d13b85fec` schema fix. Final tag remains paused for current-trunk relay
  redeploy, full Pi restart, and operator re-verification.

Awaiting operator UAT (runbook incl. stack-currency pertinence retests)
before final tag + collapse.
