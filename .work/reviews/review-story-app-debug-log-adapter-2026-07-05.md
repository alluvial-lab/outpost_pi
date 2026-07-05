# Review: story-app-debug-log-adapter

## 1. Verdict

**NEEDS FIXES.** The implementation is directionally aligned with the accepted design: the domain contract is pure, the 12 current typed events are scrubbed/capped, the adapter is file-backed, immediate-flush tags were expanded, and the targeted tests pass. I would not advance this story yet because two load-bearing guarantees are not actually met: `export()` does not read the file as source of truth, and the persisted file is append-only even after the in-memory ring evicts lines, so the on-disk “ring” can grow without the 1 MiB cap. There are also important lifecycle/race gaps around `_ensureLoaded()` reentrancy and the unawaited dispose/immediate flush, plus a privacy-test soundness gap for future variants.

## 2. Acceptance criteria

| Acceptance checkbox | Status | Evidence |
|---|---:|---|
| `DebugEvent` sealed class + `DebugTag` enum + variants in `domain/contracts/`. | PASS | `app/lib/domain/contracts/debug_log.dart:10` defines `DebugTag`; `:36` defines `sealed class DebugEvent`; variants are at `:47`, `:80`, `:103`, `:119`, `:143`, `:166`, `:182`, `:213`, `:236`, `:259`, `:283`, `:306`. |
| `ConnChannelLostEvent` carries `stale` bool (the takeover proof). | PASS | `ConnChannelLostEvent.stale` is required at `app/lib/domain/contracts/debug_log.dart:213-229`; tests cover both values at `app/test/domain/contracts/debug_log_test.dart:153-170`. |
| Each variant serializes through canonical `toJson()`; registry test asserts no forbidden keys + all string fields capped. | PASS for current variants; soundness gap below | Each current variant implements `toJson()` (`debug_log.dart:66`, `:93`, `:110`, `:132`, `:156`, `:173`, `:199`, `:226`, `:249`, `:272`, `:296`, `:319`). Tests check forbidden keys at `app/test/domain/contracts/debug_log_test.dart:97-109` and string caps at `:112-127`. The test is not future-proof; see Privacy. |
| No variant carries full body / image / tool args or results. | PASS for current fields | Current fields are ids/tails/status/counts/reasons and `preview`; no `body`, image, args, or result fields appear in the current variants (`debug_log.dart:47-324`). |
| `MsgSendEvent.preview` is the truncated `_preview`, never full text. | UNVERIFIABLE-FROM-CODE | The foundation code names and caps `preview` (`debug_log.dart:78-98`; test at `debug_log_test.dart:173-180`), but no capture site exists in this story to prove callers pass `_preview` rather than a short full message. This belongs to `story-app-capture-routing`. |
| `DebugLog implements Service` (so `addService<DebugLog>` disposes). | PASS | `DebugLog implements Service` at `debug_log.dart:354`; `Service.dispose()` is `void` at `app/lib/domain/contracts/service.dart:3-5`; `CustomInjector.addService<T extends Service>` disposes via `BindConfig(onDispose: (value) => value.dispose())` at `app/lib/config/utils/injector.dart:35-38`. Targeted tests compile. |
| `DebugLog` exported via `contracts.dart`; domain has no infra imports. | PASS | `app/lib/domain/contracts/contracts.dart:1` exports `debug_log.dart`; `debug_log.dart:1` imports only the domain `service.dart`, with no `dart:io`, `path_provider`, or sharing/UI imports. |
| Ring persists to `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`. | PASS with cap caveat | `_ensureLoaded()` builds `${dir.path}/remote_pi_debug.jsonl` from `getApplicationDocumentsDirectory()` at `debug_log_impl.dart:88-89`; `_flushAndReset()` appends to that file at `:196-198`. However, on-disk retention is not capped; see New bugs. |
| Ring survives app restart (warm-from-file, skipping corrupt lines). | PASS | `_ensureLoaded()` reads existing lines, `jsonDecode`s to skip corrupt lines, adds valid lines, and truncates at `debug_log_impl.dart:89-104`; tests cover restart at `app/test/data/debug/debug_log_impl_test.dart:54-72` and corrupt lines at `:74-90`. |
| Cap enforced on append (no overshoot between flushes). | PASS for `_ring`; FAIL for persisted file | `log()` adds to `_ring` then immediately calls `_truncate()` at `debug_log_impl.dart:124-125`; `_truncate()` evicts oldest at `:209-214`. But `_pending` is not pruned and `_flushAndReset()` appends evicted lines to disk (`:126`, `:189-198`), so the file-backed ring is not capped. |
| Per-field length caps; a huge untrusted string can't evict the window. | PASS for current variants | `kMaxFieldValueChars = 256` and `_cap()` are at `debug_log.dart:330-333`; current string fields call `_cap()` in each `toJson()`; oversized values are tested at `debug_log_test.dart:32-67` and `app/test/data/debug/debug_log_impl_test.dart:116-128`. The cap lives in domain variants, not in the adapter. |
| Critical events flush immediately (expanded set); routine events debounce 2s. | PASS for dispatch behavior | Expanded set includes `msgSend`, `msgFailed`, `sessionGate`, `sessionSync`, `connStatus`, `connChannelLost`, `connHydrate`, `workingConv`, `roomSnapshot` at `debug_log_impl.dart:43-53`. `log()` calls `_flushAndReset()` directly for those tags and `_scheduleFlush()` otherwise at `:127-132`; debounce timer is `2s` at `:39`, `:175-177`. Durability is still best-effort because the flush is unawaited. |
| `export()` reads from the file after a forced flush; works while OFF. | FAIL | `export()` does not read the file. It calls `_ensureLoaded()`, `_flushAndReset()`, then returns `_ring.join('\n')` at `debug_log_impl.dart:137-141`. That only warms from file once and then exports in-memory state. It is not gated by `_debugEnabled()`, so OFF behavior is okay. |
| `clear()` wipes ring + file but not `Preferences.debugLogging`. | PASS | `clear()` clears `_ring` and `_pending`, then writes an empty string to the log file at `debug_log_impl.dart:145-157`. It does not import or touch Preferences. |
| All public methods + timer callback catch `Object`; never rethrows. | FAIL | `jsonEncode(event.toJson())` is caught at `debug_log_impl.dart:116-123`, file load/write paths catch `Object` at `:87-107`, `:150-156`, `:194-203`. But `log()` calls `_debugEnabled()` outside the try at `:112-117`; a throwing callback would escape. `export()` and `clear()` also do not have outer public-method try/catch wrappers. |
| `dispose()` flushes pending lines. | PASS as best-effort only | `dispose()` cancels the timer and starts `_flushAndReset()` at `debug_log_impl.dart:163-172`; the lifecycle test drains the event queue and verifies disk at `app/test/data/debug/debug_log_impl_test.dart:154-162`. Since `Service.dispose()` is `void`, the flush is fire-and-forget and not guaranteed before process exit. |
| `log()` is a no-op when injected debug-enabled callback returns false. | PASS | `log()` returns before serialization at `debug_log_impl.dart:112-117`; test at `app/test/data/debug/debug_log_impl_test.dart:41-46`. |
| `flutter analyze` clean; `flutter test` green. | PASS for tests; analyze has known pre-existing info | Ran `flutter test test/domain/contracts/debug_log_test.dart test/data/debug/debug_log_impl_test.dart`: all 18 targeted tests passed. Ran `flutter analyze`: only `lib/ui/chat/widgets/input_bar.dart:802` deprecated `axisAlignment` info, which `app/CLAUDE.md` records as pre-existing and not review-blocking. |

## 3. v2 review-finding closure

| v2 finding | Closure | Evidence |
|---|---:|---|
| A2 — crash-resilient flush | PARTIAL | The immediate set is now the expanded design set (`debug_log_impl.dart:43-53`) and `log()` bypasses debounce for those tags (`:127-132`), so there is no bug where the debounce fires instead. But the immediate flush is unawaited (`:130`), and `dispose()` is also fire-and-forget (`:172`), so “critical events already on disk” is overstated. |
| A3 — cap-on-append + field caps | PARTIAL | `_ring` is truncated in `log()` (`debug_log_impl.dart:124-125`) and string fields are capped in domain `_cap()` (`debug_log.dart:330-333`). The adapter itself does not enforce field caps, and the persisted file is append-only: evicted `_ring` lines can remain in `_pending` and be written to disk (`debug_log_impl.dart:126`, `:189-198`). |
| B2 — typed events + registry test | PARTIAL | Typed variants exist and current variants are tested (`debug_log_test.dart:32-67`, `:97-145`). But mentally adding a new `DebugEvent` variant with a `body` field does **not** necessarily fail: if the author forgets to add it to `allVariants()` and `expectedTypes`, the current tests never instantiate it and the hand-written `expectedTypes` set (`:76-89`) will still pass. |
| C2 — never throws | PARTIAL | `jsonEncode` failure is caught (`debug_log_impl.dart:116-123`); `getApplicationDocumentsDirectory()`/file-read failure is caught in `_ensureLoaded()` (`:87-107`); file clear/write failures are caught (`:150-156`, `:194-203`). Missing: `_debugEnabled()` is outside any catch (`:114`), and public methods lack outer catch-all wrappers. |
| C3 — dispose wiring | PARTIAL | `DebugLog implements Service` compiles in the targeted tests (`debug_log.dart:354`), and `DebugLogImpl.dispose()` overrides and starts a flush (`debug_log_impl.dart:163-172`). `CustomInjector.addService` would call `dispose()` (`injector.dart:35-38`). The unresolved limitation is that the Service contract is synchronous, so the final flush cannot be awaited. |
| E3 — untrusted-input boundary | PARTIAL | Current typed fields are primitives and capped; tests assert primitive values (`debug_log_test.dart:131-145`) and oversized strings (`:112-127`). `jsonEncode` failures are dropped safely (`debug_log_impl.dart:116-123`). However, enforcement is per-variant in domain, not adapter-level, and the registry test is not exhaustive for future variants. |
| F2 — export-from-file | DROPPED/PARTIAL | Warm-from-file is implemented (`debug_log_impl.dart:84-104`) and the first export can recover pre-existing file lines. But `export()` itself returns `_ring.join('\n')` (`:137-141`) and never re-reads the file line-by-line after the forced flush, so the file is not the source of truth. |

## 4. New bugs

### Blocker — File-backed ring is not actually exported from the file and not capped on disk

- **Where:** `app/lib/data/debug/debug_log_impl.dart:124-126`, `:137-141`, `:189-198`, `:209-214`.
- **What:** `_truncate()` only removes lines from `_ring`. `_pending` still contains every unflushed line, including lines evicted from `_ring`, and `_flushAndReset()` appends the pending batch to the file. `export()` then returns `_ring`, not the file, masking the fact that the persisted file can grow beyond the 1 MiB ring cap and is not the export source of truth.
- **Why it matters:** This violates both the bounded-retention story and review F2. If the next fix changes `export()` to read the file as specified, exports may include old evicted lines and grow without bound.
- **Fix:** Make the file an atomic snapshot of the capped ring (e.g. after loading and appending, truncate `_ring`, then `writeAsString(_ring.join('\n') + optional trailing newline)` instead of append), or maintain a separate capped on-disk ring. In either case, `export()` should force-flush and then read/validate the file line-by-line as specified.

### Important — `_ensureLoaded()` is reentrant and can drop critical logs during first load

- **Where:** `app/lib/data/debug/debug_log_impl.dart:84-89`, `:185-193`.
- **What:** `_loaded = true` is set before `getApplicationDocumentsDirectory()` and file warm-up complete. A concurrent critical `log()` during the first `_ensureLoaded()` can enter `_flushAndReset()`, see `_loaded == true`, skip loading, find `_filePath == null`, and return after `_pending.clear()`.
- **Why it matters:** This can lose exactly the critical startup/reconnect tail the immediate-flush design is trying to preserve. It can also interleave warm-file lines after newly logged lines in `_ring`.
- **Fix:** Replace `_loaded` with a shared `Future<void>? _loadFuture` and await the same load future from all callers; set the loaded state only after path resolution finishes. Do not clear `_pending` permanently until a path exists and the write succeeds.

### Important — Immediate/dispose flush is fire-and-forget, so the durability claim is stronger than the code

- **Where:** `app/lib/data/debug/debug_log_impl.dart:127-130`, `:163-172`; tests wait manually at `app/test/data/debug/debug_log_impl_test.dart:32-38`.
- **What:** Critical `log()` starts `_flushAndReset()` but does not await it. `dispose()` starts another unawaited flush. A critical event logged immediately before teardown can still be in an async file write when the process exits.
- **Why it matters:** The design’s “crash-resilient tail” should be described as best-effort unless there is an awaited lifecycle flush path. The test simulates normal teardown by draining the event queue, not a crash.
- **Fix:** Keep immediate flush best-effort in `log()`, but expose/drive an awaited `flushForTestingOrLifecycle()`/`Future<void> flush()` from lifecycle paths that can await. At minimum, update comments/tests to avoid claiming critical lines are already on disk.

### Important — `log()` can still throw if the debug-enabled callback throws

- **Where:** `app/lib/data/debug/debug_log_impl.dart:112-117`.
- **What:** `_debugEnabled()` is evaluated before the `try` that catches encoding failure.
- **Why it matters:** The story requires all public methods to catch `Object` and never rethrow. A Preferences read callback should not be able to break app code through logging.
- **Fix:** Wrap the whole public `log()` body in `try { ... } catch (Object e, StackTrace s) { _safeLog(...) }`, including `_debugEnabled()`.

### Important — Concurrent flushes can reorder writes

- **Where:** `app/lib/data/debug/debug_log_impl.dart:185-198`.
- **What:** Two `_flushAndReset()` calls can run concurrently. Each snapshots and clears the then-current `_pending`, then opens the same file in append mode. If both reach `openWrite` together, append order is not explicitly serialized by the adapter.
- **Why it matters:** Diagnostic logs are temporal. Reordered jsonl lines make reconnect/session timelines harder to trust.
- **Fix:** Serialize flushes with a `_flushFuture` chain/lock and append batches in call order.

### Nit — `_truncate()` is not byte-accurate

- **Where:** `app/lib/data/debug/debug_log_impl.dart:209-214`.
- **What:** `line.length + 1` counts UTF-16 code units, not UTF-8 bytes written to disk. It also counts one trailing newline per line, while `join('\n')` has `n - 1` separators and `writeln` appends a newline per written line.
- **Why it matters:** The cap is documented as bytes/1 MiB. Non-ASCII fields can make the real file/export larger than the accounting.
- **Fix:** Use `utf8.encode(line).length` plus the exact newline policy used for persistence/export.

### Nit — Production test seam should be annotated

- **Where:** `app/lib/data/debug/debug_log_impl.dart:74-79`.
- **What:** `DebugLogImpl.withMaxBytesForTest` is a public production constructor.
- **Fix:** Add `@visibleForTesting` (already available from `package:flutter/foundation.dart`) or make the seam library-private if tests can remain in the same library pattern.

### Non-issue — `export()`/`clear()` after `dispose()`

- **Where:** `app/lib/data/debug/debug_log_impl.dart:137-157`, `:163-172`.
- **Position:** These methods do not check `_disposed`, but there is no closed file handle or invalid platform resource kept by the adapter. They should generally work after dispose, aside from racing with the fire-and-forget dispose flush. This is acceptable if the service contract treats post-dispose use as best-effort/unsupported; otherwise add an explicit policy.

## 5. Privacy

- **Important — The forbidden-key test is not exhaustive for future variants.** The forbidden set is declared at `app/test/domain/contracts/debug_log_test.dart:16-26`, and current variants are manually instantiated at `:32-67`. Adding a new variant with `toJson() => {'body': ...}` will only fail if the author also remembers to add it to `allVariants()`. The claimed compile-time guard is not present; `expectedTypes` is also hand-maintained at `:76-89`. Fix by adding a real single-source registry of event factories/metadata in `debug_log.dart` that tests iterate, or an exhaustive `switch` over `DebugEvent` in a helper that must be updated by the compiler plus a registry count derived from that helper.
- **Important — Forbidden keys are too narrow as a privacy invariant.** Exact keys `body`, `image`, `data`, `args`, `result`, `prompt`, `message`, `ct` are blocked, but payload-like names such as `content`, `payload`, `text`, `body_text`, `fullText`, `raw`, `toolOutput`, `imageBytes`, or `summary` would pass. The better invariant is positive allow-listing per event tag, not only a deny-list.
- **Preview cap is reasonable for the stated operator-owned dump, but not proof of “safe.”** `MsgSendEvent.preview` is capped to 256 code units (`debug_log.dart:330-333`; test `debug_log_test.dart:173-180`). For an operator-chosen debug export this is a reasonable diagnostic compromise, consistent with the parent design’s privacy posture. It would not be appropriate for always-on/end-user telemetry without a stricter preview scrub and UI warning.
- **The cap is exercised with oversized values.** The registry test uses `huge = 'x' * (kMaxFieldValueChars * 4)` for every current variant (`debug_log_test.dart:32-67`) and separately checks a 1000-character preview (`:173-180`). This is more than just checking the constant.

## 6. Layering/DI

- **Layering:** PASS. `debug_log.dart` imports only `package:app/domain/contracts/service.dart` (`debug_log.dart:1`) and has no `dart:io`, `path_provider`, `share_plus`, Flutter UI, or data/config imports. `DebugLogImpl` lives in `data/` and imports `dart:io`, `path_provider`, and `flutter/foundation.dart`, which is appropriate for an adapter (`debug_log_impl.dart:1-6`).
- **`DebugLog implements Service`:** PASS. The targeted tests compile, and Dart accepts the port as satisfying `T extends Service` for DI purposes (`debug_log.dart:354`; `service.dart:3-5`). `DebugLogImpl` implements `dispose()` at `debug_log_impl.dart:163-172`.
- **DI readiness:** Mostly ready for Unit 3. A registration shaped like `addService<DebugLog>(() => DebugLogImpl(debugEnabled: () => prefs.debugLogging))` matches the adapter constructor (`debug_log_impl.dart:70-72`) and the injector dispose path (`injector.dart:35-38`). Actual `dependencies.dart` wiring and `Preferences.debugLogging` are correctly out of scope for this story.

## 7. Action items

1. **Fix file/source-of-truth and disk cap semantics in `app/lib/data/debug/debug_log_impl.dart`.** Prefer writing an atomic snapshot of the capped `_ring` instead of append-only `_pending`, or otherwise enforce the same cap on disk. Then make `export()` read the file line-by-line after forced flush and skip corrupt lines.
2. **Make `_ensureLoaded()` concurrency-safe in `app/lib/data/debug/debug_log_impl.dart`.** Use a shared load future/lock; do not set loaded before path resolution completes; do not clear pending batches irreversibly when `_filePath` is unavailable or write fails.
3. **Wrap the entire public `log()` method in a catch-all in `app/lib/data/debug/debug_log_impl.dart`.** Include `_debugEnabled()` in the protected section.
4. **Serialize concurrent flushes in `app/lib/data/debug/debug_log_impl.dart`.** A simple `_flushFuture` chain is enough for deterministic batch order and fewer file races.
5. **Strengthen the registry/privacy test in `app/test/domain/contracts/debug_log_test.dart`.** Replace the hand-maintained `expectedTypes` illusion with a real event registry or another compiler-enforced exhaustiveness pattern; move from forbidden-key deny-list toward per-event allowed-key assertions.
6. **Annotate `DebugLogImpl.withMaxBytesForTest` with `@visibleForTesting`.** Also consider using UTF-8 byte accounting in `_truncate()`.
7. **After fixes, rerun:** `flutter test test/domain/contracts/debug_log_test.dart test/data/debug/debug_log_impl_test.dart` and `flutter analyze` from `app/` (noting only the known pre-existing `input_bar.dart:802` info if still present).
