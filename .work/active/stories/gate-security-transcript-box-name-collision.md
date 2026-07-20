---
kind: story
release_binding: v0.2.0
parent: feature-secure-transcript-storage
stage: done
id: gate-security-transcript-box-name-collision
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-20
---

# Transcript Hive box names can collide after sanitization

## Severity
Medium

## Location
app/lib/data/local/boxes.dart:98

## Issue
_safe replaces unsafe characters with _ and collapses runs, so distinct room/session identifiers can map to the same transcript box name.

## Recommendation
Encode each key segment with a reversible safe encoding or a length-bounded hash, and avoid lossy replacement for storage identities.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for the security-critical persistence feature).
- Review weight: `standard` (caller default); child checkpoint does not receive independent review.
- Files changed: `app/lib/data/local/transcript_box_identity.dart`, `app/lib/data/local/boxes.dart`, `app/pubspec.yaml`, `app/pubspec.lock`, `app/test/data/local/transcript_box_identity_test.dart`.
- Tests added: deterministic SHA-256 tuple identity, demonstrated legacy aliases, segment sensitivity, and bounded lowercase ASCII output.
- Simplification: removed lossy naming from all normal transcript box access; legacy naming will exist only in the migration adapter.
- Discrepancies from design: checkpoint arrived at `stage:drafting` although the delegated implementation bundle was already active; completed directly as the feature's first implementation checkpoint.
- Adjacent issues parked: none.

## Verification
- `flutter test --no-pub test/data/local/transcript_box_identity_test.dart` — 4 passed.
