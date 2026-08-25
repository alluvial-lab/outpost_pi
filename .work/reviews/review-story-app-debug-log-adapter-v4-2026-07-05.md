# Review: story-app-debug-log-adapter v4

## 1. Verdict

ACCEPTED. Commit f7793b0 actually applies the clear-vs-flush serialization this time, and the rewritten regression test has teeth: when I temporarily removed the await block from `clear()`, the targeted test failed by observing log resurrection. The focused test passes with the fix restored, the full app test suite is green at 640 tests, and `flutter analyze` reports only the known pre-existing `axisAlignment` deprecation info.

## 2. Fix verification

The fix is present in `app/lib/data/debug/debug_log_impl.dart` before `_ring.clear()`:

```dart
      final prev = _flushFuture;
      if (prev != null) {
        await prev.catchError((Object _, StackTrace _) {});
      }
      _ring.clear();
```

`grep -n "await prev.catchError" app/lib/data/debug/debug_log_impl.dart` reports:

```text
217:        await prev.catchError((Object _, StackTrace _) {});
```

The `prev.catchError` shape is sound for this use: it lets `clear()` continue to wipe even if the prior flush future completes with an error. Analyzer did not flag the repeated `_` parameters; the only analyzer issue was the known unrelated `axisAlignment` deprecation.

Revert experiment result: I temporarily removed the `final prev = _flushFuture; ... await prev.catchError(...)` block so `clear()` went straight to `_ring.clear()`. After the edit, `grep -c "await prev.catchError" lib/data/debug/debug_log_impl.dart` returned `0`. Running the targeted test failed:

```text
00:05 +0 -1: clear serializes with an in-flight flush (no log resurrection) [E]
  Expected: empty
    Actual: '{"tag":"connChannelLost","ts":"2026-07-05T17:15:05.548946Z","stale":false}\n'
              ''
...
00:05 +0 -1: Some tests failed.
```

That confirms the test is not passing for trivial timing reasons anymore. With the fix restored, the same targeted test passes:

```text
00:05 +1: All tests passed!
```

## 3. Seam soundness

`pendingFlush` and `flushDelayForTesting` are `@visibleForTesting` seams and are only referenced by the implementation and `app/test/data/debug/debug_log_impl_test.dart` in this checkout. No production caller uses them.

`pendingFlush` is a read-only exposure of `_flushFuture`; it does not alter production behavior. `flushDelayForTesting` adds only one nullable field read and branch inside `_flushNow()` before the snapshot write, so production overhead is negligible and only on flush, not on the `log()` hot path.

The delay injection point is appropriate for the regression: `_flushNow()` builds the stale snapshot first, then waits before `file.writeAsString(snapshot, flush: true)`. That keeps the in-flight `_flushFuture` alive at exactly the dangerous point, proving `clear()` must await it before wiping. This also does not desync the flush chain: `_flushFuture` is assigned to `thisFlush` before awaiting, and the existing `identical(_flushFuture, thisFlush)` guard still prevents an older flush from clearing a newer chained future.

Nit only: the test comment says setting `flushDelayForTesting = null` releases the delay, but the current flush has already captured `Duration(seconds: 5)`, so it really waits out the five-second `Future.delayed`. This is not a correctness problem; it just makes the focused test take about five seconds.

## 4. Regression check

- Focused fixed test: `flutter test test/data/debug/debug_log_impl_test.dart --plain-name "clear serializes"` passed (`00:05 +1: All tests passed!`).
- Full app suite: passed with 640 tests:

```text
00:32 +640: All tests passed!
```

- Analyze: ran `flutter analyze`. It returned the known pre-existing info only:

```text
info • 'axisAlignment' is deprecated and shouldn't be used ... lib/ui/chat/widgets/input_bar.dart:802:7 • deprecated_member_use
1 issue found. (ran in 4.4s)
```

No new analyzer finding is attributable to this change.

## 5. Action items

No blocking or important action items. Optional forward-looking nit: if this test's five-second runtime becomes annoying, replace the duration seam with a completer/fake-clock-style seam so the test can truly release the held write immediately instead of waiting out `Future.delayed`.
