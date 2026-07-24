---
id: gate-refactor-lifecycle-legacy-migration-source-boxes
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-24
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

## Implementation notes

- Wrapped each legacy event/projection source-box read in `try`/`finally` and closes its locally owned Hive box before any migration exit; verified sources remain on disk until the existing post-copy deletion phase.
- Added a malformed-projection regression assertion that the retained source box is no longer open.
- Verification: targeted `flutter test test/data/local/transcript_storage_migration_test.dart` passed (12 tests); `flutter analyze` passed with no issues. Full `flutter test` ran 814 passing tests but could not run six pre-existing E2E tests because the runner did not supply required pairing endpoint environment values (`pairing e2e endpoints were not provided by the runner`).

## Review

Bounded inline review (orchestrator, 2026-07-23): diff inspected — `try`/`finally`
wraps both legacy source loops with `await source.close()` on every exit;
deletion path preserved (full 12-test migration suite green). New assertion
proves a malformed source is closed before abort. Approved -> done.
