---
id: gate-refactor-lifecycle-legacy-migration-source-boxes
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-20
---

# Close legacy transcript source boxes on every migration exit

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/data/local/transcript_storage_migration.dart:131` (the projection-source path repeats the ownership gap at line 171)

## Issue
`migrate` opens each plaintext legacy event/projection Hive box but does not close it on malformed, ambiguous, conflict, hook-failure, or early-continue exits; source deletion closes boxes only after the entire migration succeeds.

## Fix
Give every opened legacy source box an explicit local owner and close it in `finally` on all non-deletion exits, while preserving the verified-success path that deletes the source only after every destination has been copied and reopened successfully.
