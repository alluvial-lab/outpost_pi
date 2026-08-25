---
id: story-app-debug-log-adapter
kind: story
stage: done
tags: [app, observability]
parent: feature-cross-side-observability
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
review_addressed: 2026-07-05
---

# App debug log: typed `DebugEvent` registry + `DebugLogImpl` adapter + lifecycle

## Status

**Done 2026-07-05.** Verdict: Approve — story verified by 4-pass adversarial
review (ACCEPTED); fast-lane advance. flutter analyze clean (only the
pre-existing axisAlignment deprecation info); flutter test 640 passed
(614 existing + 26 new). Reviews at `.work/reviews/review-story-app-
debug-log-adapter-v{1..4}-2026-07-05.md`.

Four adversarial review passes:
- v1 (NEEDS FIXES): blocker file-cap/export-from-file, 4 importants, 2 nits, privacy gap.
- v2 (NEEDS FIXES, re-review): confirmed v1 fixes landed; caught a NEW
  blocker (clear-vs-flush race introduced by the snapshot-write restructure).
- v3 (NEEDS FIXES): caught that the v2 fix commit CLAIMED to fix clear() but
  the edit never applied — clear() still didn't await _flushFuture; the
  regression test passed for trivial timing reasons.
- v4 (ACCEPTED): independently verified the actual fix landed (f7793b0),
  confirmed the rewritten regression test has teeth (revert experiment: test
  FAILS without the fix, PASSES with it), full suite 640 passed, analyze clean.

All acceptance criteria met. 26 tests (10 registry + 16 adapter) green.

## Scope (Units 1+2 of `feature-cross-side-observability`)

Foundation story — no UI, no capture sites yet. Delivers the typed event
registry, the ring-buffer adapter, and the dispose-wired lifecycle. The
debug toggle (story-app-debug-toggle-ui) and capture-site routing
(story-app-capture-routing) build on this.

### Unit 1: `DebugLog` port + `DebugEvent` registry
**File**: `app/lib/domain/contracts/debug_log.dart` (+ export in `contracts.dart`)

- `sealed class DebugEvent` with a `DebugTag` enum + one variant per capture
  site family (`WsInEvent`, `MsgSendEvent`, `MsgEchoEvent`, `MsgFailedEvent`,
  `SessionGateEvent`, `SessionSyncEvent`, `ConnStatusEvent`,
  `ConnChannelLostEvent`, `ConnHydrateEvent`, `RoomSnapshotEvent`,
  `WorkingConvEvent`, `ReplayDedupEvent`, …). `ConnChannelLostEvent` carries
  a `stale` bool — the duplicate-connection-takeover proof.
- Each variant serializes through one canonical `toJson()`; a registry test
  asserts no forbidden keys (`body`, `image`, `data`, `args`, `result`,
  `prompt`, `message`, `ct`) and that all string fields are capped (review B2).
- No variant carries full message body / image data / tool args or results.
  `MsgSendEvent.preview` is the truncated `_preview`, never full text.
- `abstract interface class DebugLog implements Service` — extends the app's
  `Service` contract so `addService<DebugLog>` (the disposing DI path) wires
  `dispose()` → flush on teardown (review C3). `addInstance`/`addOther` do NOT
  dispose; the `T extends Service` type bound requires this.
- `void log(DebugEvent); Future<String?> export(); Future<void> clear();`
- No `dart:io` / `path_provider` / `share_plus` imports (domain purity).

### Unit 2: `DebugLogImpl` adapter + lifecycle
**File**: `app/lib/data/debug/debug_log_impl.dart`

- 1 MiB byte cap, ring-truncate on append (not just on flush).
- Per-field length caps (e.g. 256 chars) before `jsonEncode`; drop entry on
  encode failure.
- Critical-event immediate flush set (review v2 #2 — expanded to match the
  capture surface): `msgSend`, `msgFailed`, `sessionGate`, `sessionSync`,
  `connStatus`, `connChannelLost`, `connHydrate`, `workingConv`,
  `roomSnapshot`. (No `lifecyclePause`/`lifecycleDetach` — those tags are not
  defined as events.)
- `export()` force-flushes then reads from the FILE (source of truth),
  line-by-line, skipping unparseable lines. Works while debug logging is OFF
  (reads whatever is on disk — review v2 #5).
- `clear()` wipes ring + file but does NOT clear `Preferences.debugLogging`
  (the toggle state is separate from the captured data — review v2 #5).
- `_ensureLoaded()` warms ring from file on startup (skips corrupt lines).
- Never throws: `log/export/clear/dispose` catch `Object, StackTrace`; timer
  callback catches internally; failures emit scrubbed `debugPrint` and never
  rethrow.
- `dispose()` final flush (best-effort).
- `log()` early-returns when debug mode is OFF (checked via a `bool Function()`
  injected callback that reads `Preferences` — no I/O in the hot path).

## Acceptance criteria

- [ ] `DebugEvent` sealed class + `DebugTag` enum + variants in `domain/contracts/`.
- [ ] `ConnChannelLostEvent` carries `stale` bool (the takeover proof).
- [ ] Each variant serializes through canonical `toJson()`; registry test
      asserts no forbidden keys + all string fields capped.
- [ ] No variant carries full body / image / tool args or results.
- [ ] `MsgSendEvent.preview` is the truncated `_preview`, never full text.
- [ ] `DebugLog implements Service` (so `addService<DebugLog>` disposes).
- [ ] `DebugLog` exported via `contracts.dart`; domain has no infra imports.
- [ ] Ring persists to `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`.
- [ ] Ring survives app restart (warm-from-file, skipping corrupt lines).
- [ ] Cap enforced on append (no overshoot between flushes).
- [ ] Per-field length caps; a huge untrusted string can't evict the window.
- [ ] Critical events flush immediately (the expanded set above); routine
      events debounce 2s.
- [ ] `export()` reads from the file after a forced flush; works while OFF.
- [ ] `clear()` wipes ring + file but not `Preferences.debugLogging`.
- [ ] All public methods + timer callback catch `Object`; never rethrows.
- [ ] `dispose()` flushes pending lines.
- [ ] `log()` is a no-op when the injected debug-enabled callback returns false.
- [ ] `flutter analyze` clean; `flutter test` green (new adapter+lifecycle tests).

## Out of scope

- The settings toggle + export UI (story-app-debug-toggle-ui).
- Routing the 15 existing `debugPrint` sites + the 6 new `ConnectionManager`
  events (story-app-capture-routing).
- `path_provider` / `share_plus` deps land with the toggle-UI story (this
  story adds `path_provider` only if needed for the adapter; `share_plus` is
  UI-only).

## References

- Parent: `feature-cross-side-observability.md` (Units 1+2, Implementation Notes).
- Review v1: `.work/reviews/review-feature-cross-side-observability-design-2026-07-04.md`
- Review v2: `.work/reviews/review-feature-cross-side-observability-design-v2-2026-07-04.md`
  (A2 crash-resilient flush, A3 cap-on-append + field caps, B2/C1 typed events,
  C3 dispose wiring + `DebugLog implements Service`, E3 untrusted-input boundary,
  F2 export-from-file, #2 immediate-flush set expanded).
- `app/CLAUDE.md` — domain/data/config layering.
- `app/lib/domain/contracts/service.dart` — `abstract class Service implements Disposable`.
- `app/lib/config/utils/injector.dart` — `addService<T extends Service>` disposes via `BindConfig(onDispose)`; `addInstance`/`addOther` don't.
