---
id: gate-refactor-lifecycle-attachment-messenger-after-await
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-20
---

# Guard attachment snackbar delivery after the async picker

## Library
lifecycle

## Rule
buildcontext-after-await

## Confidence
High

## Location
`app/lib/ui/chat/chat_page.dart:452`

## Issue
`_openAttach` captures a `ScaffoldMessengerState` from `context` before several awaits and uses it afterward without checking that the originating context is still mounted.

## Fix
Resolve the messenger only after the final await: check `context.mounted`, return when unmounted, then call `ScaffoldMessenger.of(context)` and deliver the attachment hint.

## Relevance
Release-relevant. The file is in the `v0.2.0` bundle.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent, so this finding has reduced review isolation.

## Implementation notes

- **Execution capability:** inline focused fix; the one-site lifecycle guard was safer and smaller than delegated coordination.
- **Files changed:** `app/lib/ui/chat/chat_page.dart`.
- **Fix:** `_openAttach` no longer captures `ScaffoldMessengerState` before the picker awaits. After the picker and hint subscription teardown, it returns when `context` is unmounted and resolves the messenger only for a live context.
- **Confirmation:** `flutter analyze` passed with zero issues; the complete non-e2e Flutter suite passed (792 tests). The repository-wide `flutter test` command additionally discovered four integration tests that require pairing harness endpoints; those failed only because the runner environment variables were absent.
- **Bounded inline review:** pass — the change is limited to the reported post-await UI delivery and preserves mounted-path behavior.
- **Adjacent issues parked:** none.
