---
id: app-hydration-truncated-flag-not-surfaced
kind: story
stage: done
tags: [app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-25
updated: 2026-08-26
---

# Session hydration truncation is invisible in the app

Observed during v0.3.0 UAT (2026-07-25): after a fresh pairing, the first
visible transcript message was mid-session — correct behavior (hydration is
bounded to `SYNC_LIMIT_DEFAULT = 30` transcript events, extension-side
`syncLimit()`, tunable via `OUTPOST_PI_SYNC_LIMIT`) — but the operator read
it as a possible bug because nothing indicates earlier history exists.

The wire already carries the signal: `session_history.truncated` is parsed
(`app/lib/protocol/generated/protocol.g.dart:1138`) but never consumed in
`app/lib/data/sync/` or `app/lib/ui/`.

Direction: surface a subtle "earlier history on this device is not synced"
affordance at the top of the transcript when `truncated` is true (and/or let
the app request a larger limit in `session_sync` for on-demand backfill).
Not release-blocking; the bounded sync is the designed contract.

## Implementation notes
- Execution capability: inline, focused app state/UI change with a bounded transcript replay test.
- Review weight: standard (source: caller default).
- Files changed: `app/lib/data/sync/sync_events.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/ui/chat/states/chat_state.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/lib/ui/chat/chat_page.dart`, and `app/test/data/sync/sync_service_test.dart`.
- Tests added/removed: Added a sync regression test proving `truncated` is exposed and clears after a complete replay; the UI consumes that state through a keyed, subtle transcript notice.
- Simplification: No unrelated persistence or replay behavior changed.
- Discrepancies from design: The implementation surfaces the existing signal; on-demand larger-limit backfill remains intentionally deferred because the story's acceptance direction permits an affordance without a new wire request.
- Adjacent issues parked: none.
- Concurrent-work collision: a shared-checkout worker commit (`a4873ac8`) carried the hydration files under an unrelated cockpit message; the app surface was revalidated and restored in `efc574fb`.

## Prior blocker (resolved)
- Required `flutter analyze && flutter test --exclude-tags e2e --concurrency=2` verification was attempted. Analyze passed; the full suite reached 972 tests but timed out in two unrelated `PairingPage` widget tests after 10 minutes each. The focused truncation regression passed. Per test-integrity rules, the story remains `stage: implementing` until the required full suite is green.

## Closure (2026-08-26)
- Review verdict: PASS; the existing `session_history.truncated` signal is carried through `SyncService` and `ChatViewModel` and rendered as the keyed transcript notice required by the story.
- Stage: `done`.
- Focused verification: `test/data/sync/sync_service_test.dart --plain-name 'truncated session history is exposed as active-session state'` — 1/1 passed.
- Shared full-suite evidence: `flutter test --exclude-tags e2e --concurrency=2` — 976/976 passed on the quiescent machine (commits `cfa060b5..64614030`; the earlier PairingPage hang was fixed in `7000f226`).
- Collision review: resolved and accurately recorded. The hydration files were accidentally carried by the unrelated shared-checkout commit `a4873ac8`; `efc574fb` restored the app surface, and later sync-fix commits legitimately changed the shared sync test. No unresolved collision remains.
- Unmet acceptance criteria: none. On-demand larger-limit backfill remains explicitly deferred, as documented above.
