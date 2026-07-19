---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: implementing
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
