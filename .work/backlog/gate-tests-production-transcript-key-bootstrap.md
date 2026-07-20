---
id: gate-tests-production-transcript-key-bootstrap
kind: story
tags: [app, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Exercise the production transcript-key bootstrap seam

## Priority
Medium

## Value evidence
Item: `feature-secure-transcript-storage`

Contract / risk / regression / maintenance cost: `app/lib/data/local/boxes.dart:44-55` is the production composition boundary that reads the provisioning marker, loads the platform-secured key, validates it, opens encrypted boxes, completes migration, and only then writes `key_provisioned_v3`. Existing key tests at `app/test/data/local/transcript_storage_key_test.dart:7-93` cover `TranscriptStorageKeyManager` through an in-memory store, while file-backed storage and migration tests call the test-only path at `app/lib/data/local/boxes.dart:58-73`, which bypasses the production marker/key-store sequence. The security-critical adapter-to-Hive seam therefore has no regression proving first boot and fail-closed reboot use the same persisted key without opening transcript data early.

## Gap type
e2e-seam

## Suggested test
```dart
test('production bootstrap provisions once and fails closed before transcript open', () async {
  // Run the production bootstrap core against a temporary Hive directory and
  // injected TranscriptKeyValueStore. Assert one key write, marker-last order,
  // successful encrypted restart, and no transcript open on missing-key reboot.
});
```

## Test location (suggested)
`app/test/data/local/transcript_storage_bootstrap_test.dart`
