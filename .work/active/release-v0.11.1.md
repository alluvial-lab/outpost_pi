---
id: release-v0.11.1
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: null
created: 2026-08-29
updated: 2026-08-29
---

# Release v0.11.1

Patch-lane cut (two-lane slicing; bugs/polish in shipped surfaces).
Changed surfaces: app (home tile) + pi-extension (/new completion path).
No wire schema, no relay — relay 0.5.2 (deployed 2026-08-28) is current.
Battery per patch-lane policy: pairing suite + lanes touching changed
surfaces (golden — UI change; state-shapes — session replacement;
capture-delivery — delivery across session replacement).

## Bound items
- story-orchestrating-room-tile-dot (pulsing-blue room-tile state)
- story-fix-new-wedge-bare-pi (/new completes in-process or exits — never strands)

## Gate runs
(populated as gates run)
- 2026-08-29 — `security`: inline source-read-only scanner (reduced isolation per operator adaptation; no nested scanner); audited 2 bound items / 11 commit-union paths across authentication/authorization, API, input-validation, secrets/configuration, dependency, data-protection, cryptography, and error/logging domains; 1 finding (Critical=0, High=0, Medium=1, Low=0), routed to unbound backlog; skip list contained 2 existing gate-security items, with 1 duplicate room-discovery candidate skipped.
- 2026-08-29 — `docs`: inline source-read-only scanner (reduced isolation per operator adaptation; no nested scanner); audited 2 bound items / 9 bundle paths; 2 findings (foundation-doc-assertion=1 High, pattern-skill-staleness=1 Medium), with 1 release-blocking story and 1 unbound backlog item; skip list contained 10 prior v0.11.0 gate-docs items, with 0 duplicate candidates skipped. Changelog v0.11.0 text was checked for false claims; the expected v0.11.1 entry remains a release-deploy Phase 5.5 responsibility.
- 2026-08-29 — `patterns`: inline source-read-only scanner (reduced isolation per operator adaptation; no nested scanner); audited 2 bound items / 9 commit-union paths; 1 new pattern codified, 2 existing patterns extended (`presence-aware-patch-merging`, `lifecycle-boundary-state-convergence`), 0 inconsistencies; deduped the existing 39-pattern catalog and rejected sub-three-occurrence candidates.
- 2026-08-29 — `tests`: inline source-read-only scanner (reduced isolation per operator adaptation; no nested scanner); audited 2 bound items / 11 commit-union paths across contract, regression, lifecycle-host, visual-state, and test-integrity seams; 2 findings (Critical=0, High=1, Medium=1, Low=0), with 1 release-blocking story and 1 unbound backlog item; 0 low-value tests flagged. Skip list contained 3 prior v0.11.0 gate-tests items, with 0 duplicate candidates emitted.
- **gate-refactor** (2026-08-29) — 1 finding (1 high, 0 medium, 0 low) from 3 libraries: boundaries (0 findings), lifecycle (1 finding), protocol-contract (0 findings). Inline rule checks only (reduced isolation per operator instruction; no nested scanner); 0 already-tracked findings skipped.
- **gate-cruft** (2026-08-29) — 0 findings (High=0, Medium=0, Low=0; inline deep cleanup scan, reduced isolation per operator instruction; no nested scanner); audited 2 bound items / 11 commit-union paths; 0 release-relevant, 0 ambient, 0 decision-required; 4 already-tracked v0.11.0 gate-cruft findings skipped. The retired `fresh_session_restart_unavailable` string appears only in work-record history, not live runtime/docs/tests/help; the StatefulWidget tile has no dead parameters or unused imports.
