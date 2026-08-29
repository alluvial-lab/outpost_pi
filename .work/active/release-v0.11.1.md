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
