---
id: gate-security-mobile-failure-detail-logged
kind: story
stage: implementing
tags: [app, security]
parent: feature-diagnostic-privacy-hardening
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-23
---

# Mobile failure diagnostics retain raw server error details

## Severity
Low

## Domain
Error Handling & Logging / Data Protection

## Relevance
Release-relevant

## Location
`app/lib/data/sync/sync_service.dart:547`

## Evidence
```dart
debugPrint('[msg-failed] id=$id code=$code detail=${debugDetail ?? message}');
...
detail: _shortReason(debugDetail ?? message),
```

## Issue
When a server `error` rejects a pending message, `message` is supplied directly to `_failPendingSend` (`app/lib/data/sync/sync_service.dart:1267`). The app writes it verbatim to `debugPrint` and stores its first 120 characters in the persistent exportable `MsgFailedEvent`, despite the debug contract's stated content-free privacy invariant. The extension can construct these server errors from raw exception messages, including delivery errors at `pi-extension/src/index.ts:2205` and action failures at `pi-extension/src/actions/handlers.ts:147`. Provider/SDK/filesystem error strings can carry prompt fragments, token-like values, local paths, or response details, so a shared mobile diagnostic export can disclose content even though successful-send previews were removed. Capture is debug-gated and requires an error path, making this Low severity.

## Remediation direction
Map failure diagnostics to a closed set of content-free categories/codes before both console and ring-log capture. Keep the user-visible error behavior separate if product UX still requires detail, but remove arbitrary `message`/`Error.message` strings from `MsgFailedEvent` and add a canary regression covering server-originated delivery/action errors.

## Scope widening (feature-design 2026-07-23)

The design (Unit 1 of `feature-diagnostic-privacy-hardening`) folds the identical
leak shape one field away into this checkpoint: `SessionSyncEvent.err`
(`sync_service.dart:647` passes `_shortReason(err)` from an arbitrary Object).
This story therefore also owns: deleting `SessionSyncEvent.err`, deleting the
now-dead `debugDetail` parameter and `_shortReason`, introducing
`kAdmissibleFailureCodes` / `admitFailureCode`, and extending the registry
test's forbidden keys with `detail`/`err`. Exact signatures and acceptance
criteria live in the parent feature body.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
