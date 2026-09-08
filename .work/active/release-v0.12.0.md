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

Active done items (8):
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
