---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: done
id: gate-security-outbound-message-previews-logged
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Outbound message previews are written to logs

## Severity
Low

## Location
app/lib/data/sync/sync_service.dart:260

## Issue
debugPrint logs up to 80 characters of user message text, which can expose prompts or secrets through device logs.

## Recommendation
Log only message IDs/metadata, redact message bodies, and guard diagnostic logging behind debug-only flags.

## Design checkpoint

Remove `MsgSendEvent.preview` from `app/lib/domain/contracts/debug_log.dart`
and remove the successful-send preview from `SyncService` diagnostics while
retaining `_preview(...)` for existing user-visible turn/session state.

Acceptance evidence:
- `MsgSendEvent.toJson()` carries only tag, timestamp, id, and blocked state.
- A canary prompt/image still reaches the wire and transcript projection but is
  absent from both `debugPrint` capture and the structured debug event.
- The debug-event allow-list/forbidden-key test prevents `preview` from being
  reintroduced.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected high reasoning for the security-sensitive cross-stack feature).
- Review weight: `standard` (caller default); child story review is not applicable.
- Files changed: `app/lib/data/sync/sync_service.dart`, `app/lib/domain/contracts/debug_log.dart`, `app/test/data/sync/sync_service_test.dart`, `app/test/domain/contracts/debug_log_test.dart`.
- Tests added: canary prompt/image regression proving the original wire and transcript event retain content while console/typed diagnostics do not; registry regression forbidding `preview` and restricting `MsgSendEvent` to correlation metadata.
- Simplification: deleted the `MsgSendEvent.preview` field and its successful-send preview local while retaining `_preview(...)` for user-visible turn state.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: the authoritative specific-file rerun `flutter test --no-pub test/data/sync/sync_service_test.dart` passed all 91 tests (zero failures versus the caller's noted three-failure baseline); `flutter test --no-pub test/domain/contracts/debug_log_test.dart` passed all 10 tests. An earlier combined two-file run exposed one pre-existing timing-sensitive `delivery_pending` assertion, which passed on the required isolated-file rerun.
