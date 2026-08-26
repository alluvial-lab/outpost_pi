---
id: backlog-peers-lock-restore-collision-safety
kind: story
stage: drafting
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-08-26
---

# peers.lock restore-on-mismatch is not collision-safe

Surfaced by thorough review pass 9 of `feature-owner-message-e2e-authentication`
(2026-07-23) and parked as Important hardening (below the current-cycle
material bar; the pass-8 ABA fix it extends is sound).

## Finding

`pi-extension/src/pairing/storage.ts:578-597` — after a reclaimer moves a
mismatching lock generation to quarantine, restoration does
`rename(quarantinePath, lockPath)`. If a third acquirer created an empty
`peers.lock` (but has not yet written `owner.json`), POSIX rename may replace
that empty directory; if `owner.json` was written, restore fails with an
uncaught non-empty-directory error, leaving the moved holder quarantined while
the third holder proceeds. Mutual exclusion is not guaranteed and a third lock
generation is not preserved in that window.

## Why parked

Reaching the restore branch requires an already-degraded/incomplete lock
holder plus narrow timing inside the reclaim path — a compound scenario. The
ordinary reclaimer-vs-reclaimer and reclaimer-vs-successor races ARE closed
(exclusive reclaim marker + owner-token fencing + post-rename verification,
`storage.test.ts:438-547`).

## Direction when picked up

Non-clobbering restoration protocol (e.g. rename with existence check +
requeue the quarantined generation rather than replacing a reappeared
lockPath), plus a deterministic `afterReclaimRenamed` test that inserts a
third generation before restore.
