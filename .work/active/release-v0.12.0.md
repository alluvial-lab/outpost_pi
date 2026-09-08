---
id: release-v0.12.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Release v0.12.0

Feature-lane minor cut (two-lane slicing): the two QOL features designed,
implemented, reviewed, and closed this session, plus the sync-limit default
bump (inline operator QOL change, no work item — rides as commit f44b94237).

## Bound items

Active done items (8) + in-flight fix (1):
- story-fix-metronome-phantom-close-teardown (operator pull-in 2026-09-08; targeted gates on completion)
- feature-fleet-update-from-mobile (+ 3 child stories: wire-protocol,
  extension-coordinator, app-ui)
- feature-mobile-session-context-telemetry (+ 3 child stories: schema-codegen,
  extension-sampler, app-render)

Late-bound archived stubs: none (all unbound archive entries are
status-stamped retired husks or non-done — skipped per the 2026-07-24
CONVENTIONS patch to the gather).

Also riding (no item): SYNC_LIMIT_DEFAULT 30 → 200 (f44b94237, inline by
operator call); v0.11.1 post-ship trunk fixes (background re-broadcast,
/new verification, close-attribution instrumentation, WS-stream-error relay
logging) that were never itemized.

## Gate runs
(populated as gates execute)

- **gate-refactor** (2026-09-08) — 0 findings (0 high, 0 medium, 0 low) from 4 libraries: boundaries (0 findings), lifecycle (0 findings), protocol-contract (0 findings), documentation (0 findings)

- 2026-09-07 — `patterns`: inline source-read-only scanner (reduced isolation; no nested scanner available in this host); audited the v0.11.1..HEAD bundle and existing 40-pattern catalog; 2 new patterns codified, 1 existing pattern extended, 0 inconsistencies.

### Gate runs
- **gate-security** (2026-09-08) — C0/H0/M1/L0: relay branch-metadata admission bound (medium, backlog, unbound); one duplicate skipped. Adjacent correctness flag on the fleet consumed-marker fed gate-tests.
- **gate-tests** (2026-09-08) — C0/H2/M1/L0: shared-home replay scope + long-deferral drain (both high, fixed in 20b61a61b + db8768f4b, stories done); commit-order oracle (medium, backlog).
- **gate-cruft** (2026-09-08) — 0 blocking; unused legacy fleet-arm builder (medium, backlog). `_publishRoomMetaPatch` type-derivation cleanup confirmed landed.
- **gate-docs** (2026-09-08) — 4 high blocking (ARCHITECTURE unions + room-meta inventory, PROTOCOL action table, CHANGELOG v0.12.0 entry — all fixed in 95430c93b, stories done); pi-extension skill staleness (medium, backlog).
- **gate-patterns** (2026-09-08) — 0 findings; 2 new patterns (injected-effect-coordinators, sentinel-copywith-nullable-fields), 1 extended (presence-aware-patch-merging).
- **gate-refactor** (2026-09-08) — 0 findings across 4 scan libraries, 103 paths.

Backlog items parked (unbound, non-blocking per gate_finding_routing):
gate-security-relay-branch-metadata-bound, gate-tests-fleet-report-commit-order-oracle,
gate-cruft-unused-legacy-fleet-arm-builder, gate-docs-pi-extension-skill-fleet-messages.

### RC artifacts (2026-09-08, v0.12.0-rc.1 draft)
- slim-arm64 release-signed: `outpost-0.12.0-27-arm64.apk` (32MiB)
  sha256 270b6c1c…e987 — install target for operator UAT
- debug-fat fallback: `outpost-0.12.0-27.apk` (197MiB)
  sha256 6f36da2f…09e6
- Version bumped 0.11.1+26 → 0.12.0+27 (9d470f4d9); gradle temp redirected
  off tmpfs (VM memory guard).
- PAUSED at the manual UAT checkpoint: operator installs the slim artifact
  (scp → workstation → adb install -r), runs the smoke runbook
  (docs/release-uat.md), performs the two deferred spot-checks (ctx% parity
  + amber tint; fleet Update live lane), and records an ack here. Remaining
  after ack: full e2e battery (minor-cut policy), tag v0.12.0, publish.
