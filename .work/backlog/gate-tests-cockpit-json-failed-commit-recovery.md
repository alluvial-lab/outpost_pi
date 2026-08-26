---
id: gate-tests-cockpit-json-failed-commit-recovery
created: 2026-08-26
updated: 2026-08-26
tags: [testing, cockpit]
release_binding: null
gate_origin: tests
---

# Cockpit JSON store does not prove recovery after an interrupted commit

## Priority
Medium

## Value evidence
Item: `feature-cockpit-storage-json-vs-hive-storage-port-json-store`.

Contract / risk / regression: the Hive replacement exists to prevent dirty-shutdown and Windows lock corruption. It promises flushed same-directory temporary files, bounded rename attempts, serialized snapshots, and a later flush attempt after a failed commit (`.work/active/features/feature-cockpit-storage-json-vs-hive.md:28-32`, `:184-200`, `:424-434`; `cockpit/lib/app/core/data/storage/json_state_store.dart:132-184`, `:288-316`). Existing tests prove successful replacement, concurrent ordering, quarantine, and permanent write-failure reporting (`cockpit/test/core/data/json_state_store_test.dart:119-249`). They do not prove the fail-once path: an interrupted/failed attempt must leave the prior complete envelope authoritative, report failure honestly, and allow `flush()` to persist the newest in-memory revision on retry. That is the state-convergence branch most directly tied to the motivating storage failure class.

Focused gate evidence: the JSON store, migration, exit lifecycle, and composition suites passed 21/21. Concurrent-open coverage includes the recent cache-poisoning fix; migration marker idempotency and quarantine remain covered.

## Gap type
complex-unit / interrupted-operation / durable-state convergence

## Suggested test
```dart
test('failed commit preserves old envelope and flush retries the newest revision', () async {
  // Seed a valid old envelope. Use a fail-once atomic-writer seam that records
  // the attempted snapshot without replacing the destination. Assert put()
  // reports the failure, the old file still decodes completely, then flush()
  // retries and commits the newest in-memory data with no stale temp artifact.
});
```

## Test location (suggested)
`cockpit/test/core/data/json_state_store_test.dart`
