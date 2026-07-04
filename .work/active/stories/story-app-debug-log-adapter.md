---
id: story-app-debug-log-adapter
kind: story
stage: implementing
tags: [app, observability]
parent: feature-cross-side-observability
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

# App debug log: typed `DebugEvent` registry + `DebugLogImpl` adapter + lifecycle

## Scope (Units 1+2 of `feature-cross-side-observability`)

Foundation story — no UI, no capture sites yet. Delivers the typed event
registry, the ring-buffer adapter, and the dispose-wired lifecycle. The
debug toggle (story-app-debug-toggle-ui) and capture-site routing
(story-app-capture-routing) build on this.

### Unit 1: `DebugLog` port + `DebugEvent` registry
**File**: `app/lib/domain/contracts/debug_log.dart` (+ export in `contracts.dart`)

- `sealed class DebugEvent` with a `DebugTag` enum + one variant per capture
  site family (`WsInEvent`, `MsgSendEvent`, `MsgEchoEvent`, `MsgFailedEvent`,
  `SessionGateEvent`, `SessionSyncEvent`, `ConnStatusEvent`, `ConnHydrateEvent`,
  `RoomSnapshotEvent`, `WorkingConvEvent`, `ReplayDedupEvent`, …).
- No variant carries full message body / image data / tool args or results.
  `MsgSendEvent.preview` is the truncated `_preview`, never full text.
- `class DebugLog { void log(DebugEvent); Future<String?> export(); Future<void> clear(); }`
- No `dart:io` / `path_provider` / `share_plus` imports (domain purity).

### Unit 2: `DebugLogImpl` adapter + lifecycle
**File**: `app/lib/data/debug/debug_log_impl.dart`

- 1 MiB byte cap, ring-truncate on append (not just on flush).
- Per-field length caps (e.g. 256 chars) before `jsonEncode`; drop entry on
  encode failure.
- Critical-event immediate flush (`msgSend`, `msgFailed`, `sessionGate`,
  `connStatus`, `roomSnapshot`, `lifecyclePause`, `lifecycleDetach`); routine
  events debounce 2s.
- `export()` force-flushes then reads from the FILE (source of truth),
  line-by-line, skipping unparseable lines.
- `clear()` wipes ring + file.
- `_ensureLoaded()` warms ring from file on startup (skips corrupt lines).
- Never throws: `log/export/clear/dispose` catch `Object, StackTrace`; timer
  callback catches internally; failures emit scrubbed `debugPrint` and never
  rethrow.
- `dispose()` final flush (best-effort).
- `log()` early-returns when debug mode is OFF (checked via a `bool Function()`
  injected callback that reads `Preferences` — no I/O in the hot path).

## Acceptance criteria

- [ ] `DebugEvent` sealed class + `DebugTag` enum + variants in `domain/contracts/`.
- [ ] No variant carries full body / image / tool args or results.
- [ ] `MsgSendEvent.preview` is the truncated `_preview`, never full text.
- [ ] `DebugLog` exported via `contracts.dart`; domain has no infra imports.
- [ ] Ring persists to `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`.
- [ ] Ring survives app restart (warm-from-file, skipping corrupt lines).
- [ ] Cap enforced on append (no overshoot between flushes).
- [ ] Per-field length caps; a huge untrusted string can't evict the window.
- [ ] Critical events flush immediately; routine events debounce 2s.
- [ ] `export()` reads from the file after a forced flush.
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
- Review: `.work/reviews/review-feature-cross-side-observability-design-2026-07-04.md`
  (A2 crash-resilient flush, A3 cap-on-append + field caps, B2/C1 typed events,
  C3 dispose wiring, E3 untrusted-input boundary, F2 export-from-file).
- `app/CLAUDE.md` — domain/data/config layering.
- `app/lib/config/utils/injector.dart` — `addService` disposes; `addInstance`/`addOther` don't.
