---
kind: story
release_binding: null
parent: feature-secure-transcript-storage
stage: done
id: gate-security-transcript-boxes-unencrypted
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Durable transcript data is stored in default Hive boxes

## Severity
Medium

## Location
app/lib/data/local/boxes.dart:77

## Issue
Transcript event logs are opened as default Hive boxes without an encryption cipher while they persist message text, images, tool args/results, and summaries.

## Recommendation
Encrypt durable transcript boxes with a key stored in platform secure storage, or explicitly gate/document plaintext local transcript retention.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical storage and key lifecycle work).
- Review weight: `standard` (caller default); child checkpoint does not receive independent review.
- Files changed: `app/lib/data/local/transcript_storage_key.dart`, `app/lib/data/local/boxes.dart`, `app/lib/main.dart`, `app/test/data/local/transcript_storage_key_test.dart`, `app/test/data/local/transcript_event_store_hive_test.dart`.
- Tests added: single-flight key provisioning, re-read validation, missing/malformed key refusal, key mismatch refusal, encrypted file sentinel, and same-key restart readback.
- Simplification: all transcript-bearing opens now pass through one cipher-backed facade; runtime remains the only plaintext operational box.
- Discrepancies from design: added a content-free SHA-256 key verifier to metadata so a valid-but-wrong 32-byte key is rejected before Hive's crash recovery can treat ciphertext as corruption. The checkpoint arrived at `stage:drafting`; completed directly within the active feature bundle.
- Adjacent issues parked: none.

## Verification
- `flutter test --no-pub test/data/local/transcript_storage_key_test.dart test/data/local/transcript_event_store_hive_test.dart test/data/local/records_test.dart` — 20 passed.
