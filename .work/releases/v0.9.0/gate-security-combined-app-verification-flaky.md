---
id: gate-security-combined-app-verification-flaky
kind: story
stage: done
tags: [app, testing]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: security
created: 2026-07-19
updated: 2026-08-27
---

# Combined app verification command is flaky

## Folded evidence (groom 2026-08-26, from idea-app-sync-service-suite-flakes)

The instability is broader than the two-file command below — the whole
`sync_service_test.dart` suite is load-sensitive under concurrent execution:

- Two consecutive `flutter test --exclude-tags e2e --concurrency=2` runs
  failed **different** `app/test/data/sync/sync_service_test.dart` assertions
  (`two session ids on the same room use different boxes and index keys`,
  `foreign session_history is dropped before rows or index mutate`,
  `server error clears pending chunk flush so chat does not stay working`)
  while the complete file passed 96/96 at `--concurrency=1`.
- Recurred twice during v0.8.1 final verification
  (`.work/releases/v0.8.1/story-fix-app-fold-vertical-screen.md`).
- Direction: find the shared state leaking between concurrent isolates
  (singleton/Hive box/static timer surviving a test, or event assertion
  racing the production 60 ms timer — cf. fixed
  `gate-tests-sync-service-noecho-wallclock-timing`, v0.4.0). Explicit
  barriers/fakes per testing-integrity; goal is green at
  `--concurrency=2`, not another cap.

## Source

Parked from the `standard`-weight cross-model review of
`feature-redact-secrets-from-diagnostic-surfaces` (2026-07-19). Lower-risk
finding — test-infrastructure, not a product defect.

## Finding

The exact two-file app verification command
(`flutter test --no-pub test/data/sync/sync_service_test.dart test/domain/contracts/debug_log_test.dart`)
failed once at `sync_service_test.dart:388` during review; the redaction
regression itself passed, and an isolated `sync_service_test.dart` rerun passed
all 91 tests. The checkout had concurrent uncommitted app-storage work at the
time, so this is not evidence of a redaction regression.

## Risk rationale (why parked, not fixed this cycle)

A flaky required command weakens future regression evidence, but it is a
test-isolation/stability issue, not a product bug. The redaction feature's own
tests pass reliably when run in isolation.

## Recommended direction

Investigate test isolation/ordering: the failure at line 388 under combined
execution suggests shared state or ordering sensitivity between the two files.
Stabilize by ensuring each test file is hermetic (no shared singleton state
leaking across files in the same process).

## Implementation notes
- Execution capability: inline, test-infrastructure stabilization only; production lifecycle code was left unchanged.
- Review weight: standard (source: caller default).
- Files changed: `app/test/data/sync/sync_service_test.dart`.
- Tests added/removed: Replaced wall-clock `_settle()` sleeps with deterministic zero-delay event-loop barriers, disabled the test-only room snapshot debounce, added explicit `_waitUntil` barriers for session/projection/outbox completion, and added a user-message-specific send barrier so `SessionSync` cannot satisfy a resend assertion.
- Simplification: Removed timing dependence from the shared test helper; no assertions were weakened and no behavioral tests were deleted.
- Discrepancies from design: The required isolated sync suite now contains 115 tests after the already-folded outbox coverage; no production singleton or Hive lifecycle was changed because the failures reproduced at test completion boundaries.
- Adjacent issues parked: none.
- Concurrent-work collision: the outbox worker modified the shared `sync_service.dart`/test surface during this run; this fix stayed test-only and staged no production lifecycle changes.

## Verification evidence
- `flutter test --no-pub test/data/sync/sync_service_test.dart --concurrency=2`: passed twice consecutively after the final fix, 115/115 each run.
- The full app command was also re-run. Analyze passed, but the full suite still timed out in unrelated `PairingPage` widget tests and showed intermittent failures in other concurrent app tests; that broader runner issue is not waived here.

## Prior blocker
- Per the caller's full-suite requirement and test-integrity rules, the story remained `stage: implementing` until `flutter test --exclude-tags e2e --concurrency=2` was green for the whole app. The target `sync_service_test.dart` suite had already met the mandated repeated-run bar.

## Outbox interaction (2026-08-26)

Runtime instrumentation around transcript append/replay, outbox recovery, and
send-timeout arming separated one production regression from three test
completion gaps. The first local reproductions also demonstrated the instability:
the concurrent file run failed the echo-within-window test and the serial run
failed the steering-echo test rather than reproducing a stable named failure.

### Per-failure verdicts

- **`live agent_message(ts) + replay AgentMessageEvt collapse to one row` —
  test completion gap.** Instrumentation showed the live deterministic assistant
  fact persisted once and replay admitted only the missing user fact; the
  assistant replay remained a duplicate. The assertion could run before either
  detached write completed after outbox confirmation added another async
  continuation. The test now waits for the live row and directly awaits replay.
- **`no-echo send timeout (g) returning to a session fails a bubble already past
  the window` — production regression.** Activation rebuilt an immediately-due
  timeout from the persisted row, then outbox recovery resent the id and
  unconditionally replaced that overdue timer with a fresh window. Which timer
  won was scheduler-dependent. Recovery now refreshes the timeout only while the
  durable delivery is still inside its original window; an overdue backstop is
  preserved. A backdated transcript/outbox fixture with a fake scheduler failed
  before the fix and passes without wall-clock waiting after it.
- **`re-applying an IDENTICAL SessionHistory is idempotent` — test completion
  gap, not box churn.** Instrumentation recorded `appended=3` for the first
  history and `appended=0` for the identical replay; message-record comparison
  produced no second Hive mutation. The old counter snapshot could precede the
  first apply's watch emissions. The test now awaits each replay and the complete
  first watch projection before capturing the no-churn baseline.
- **`switching the writer to a new session ... OLD connection is dropped` —
  test completion gap.** The origin gate continued to drop the stale-channel
  frame. Under load the old session's detached confirmation could still be
  pending when activation advanced the lifecycle generation, making the test's
  own baseline nondeterministic. The test now waits for the original row and the
  replacement watch before injecting the straggler.

### Additional stabilization

The outbox path made the suite setup's fixed event-loop turns insufficient under
full-run I/O load. Setup now waits for the adopted channel, canonical
`ConnectionManager` session, and matching `SyncService` binding. Related
assertions wait on their actual durable or in-memory state: steering/outbox
completion, duplicate replay watches, session rotation, legacy-capability reset,
assistant finalization/index convergence, compaction/cancellation convergence,
and resend-start barriers. Assertions were not weakened and concurrency was not
reduced.

### Evidence

- `flutter test --no-pub test/data/sync/sync_service_test.dart --concurrency=2`:
  115/115 twice consecutively on the final tree.
- `flutter test --no-pub --exclude-tags e2e --concurrency=2`: 976/976 on the
  final tree. An extra stress repeat exposed a separate real-socket fixture's
  two-second load timeout; its exact isolated test passed 1/1. The required full
  command subsequently completed green.
- `flutter analyze --no-pub`: no issues found.

The full-suite acceptance bar is green, so this standalone story advances to
`done`.
