---
id: feature-cross-side-observability
kind: feature
stage: implementing
tags: [pi-extension, app, relay, observability, testing]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
---

# Cross-side observability & session-replacement reproduction (critical path)

## Brief

The single highest-leverage gap in this area, and the critical path for the
whole epic. The epic's reframed thesis is that the boundary bug class exists
because we are observability-blind on the phone (and relay) side where the
bugs manifest — the extension side is already retroactively diagnosable
(`audit.jsonl`), but the phone is only `debugPrint` → logcat (bounded, wiped
on reboot) and the relay is stdout only. Every wrong fix this session (the
`factoryApi` re-arm, the single-process framing) *also* passed its
mock-based tests because the mocks don't model `runtime.assertActive()` or
real SDK session replacement. This feature closes both gaps: the
**observability** that makes live bugs diagnosable after the fact, and the
**harness** that makes mock-only failures reproducible in CI.

## Scope (priority order)

1. **Phone-side persistent ring log** (`idea-cross-side-logging-for-debug`,
   2026-06-29 survey) — the lead child and highest-leverage piece.
   - Bounded in-memory ring buffer flushed to a file on device
     (`getApplicationDocumentsDirectory`), surviving reboot and buffer
     rollover.
   - In-app "Export debug log" share-sheet action.
   - Captures the state-transition lines that map 1:1 to the shipped resilience
     fixes: `working` convergence, room snapshot adoption, reconnect hydration,
     send-failure surfacing, pending-send backstop, stale-session history
     guards, session-gate rejections.
   - `adb logcat -d` remains the zero-setup USB path; the ring log covers the
     non-USB / reboot / buffer-rollover case (the actual failure mode for
     "anecdotal" bugs).
2. **Cross-side correlation key** — the message id is already shared between
   app (`[msg-send] id=…`) and extension (`app user_message id=…`). Extend it
   onto the relay forward path (`pi_forward`) so one id greps across all three
   sides. Confirm the `session_started_at` high-water as a secondary
   correlation key.
3. **Relay persistent logging** — optional file sink for `tracing` (stdout
   remains default; gate behind an env flag / container volume). The relay's
   stdout is gone on scroll/restart unless redirected at launch; a file sink
   makes the relay side match the extension's retroactive capability. Add a
   `debug!` on the forward path with `peer`, `room`, and message id so silent
   drops become visible without INFO spam.
4. **Transport-frame observability** (`story-add-transport-frame-observability`,
   parked) — privacy-safe, throttled diagnostic surface for dropped/malformed
   relay and peer-channel frames.
5. **Session-replacement integration harness** — drives a real
   `ctx.newSession()` / `/reload` / `/resume` / fork through the actual SDK
   `ExtensionRunner` and asserts post-replacement: message delivery works,
   history replays, app actions land on the fresh ctx, no stale-ctx throw
   reaches the wire. This is the test-side analog of the ring log — it makes
   the mock-only failures reproducible in CI instead of only in live use.
   If genuinely infeasible against the installed SDK, document exactly why and
   ship an honest xfail + the ring log as the diagnostic substitute.

## Why this is a feature, not a story

The ring log has open design decisions (retention/rotation policy, what's
release-safe to surface vs debug-mode-only, share-sheet format, privacy
scrubbing of payloads). The relay file sink has container/deploy implications
(volume mount, the live `remote-pi-relay` Docker container's stdout today).
The harness is design-bearing — building it against the installed SDK requires
figuring out how to drive the real `ExtensionRunner` from a vitest, which may
surface SDK constraints. All five are force-multipliers for the epic, not
one-line fixes.

## Unblocks

- Honest verification of every code fix under
  `epic-targeting-and-session-lifecycle-contracts`.
- Attribution of the reconnect cluster (`feature-reconnect-reproduction`).
- The `#2` stale-error repro (becomes reproducible instead of anecdotal).
- Rapid diagnosis of future boundary bugs (the instrumentation that would have
  caught this session's wrong premises earlier).

## Out of scope

- The contract prose (`feature-contract-gap-audit`) — downstream of what this
  finds.
- The reconnect cluster attribution itself (`feature-reconnect-reproduction`).
- The `#2` stale-error repro as a contract item (separate observe-and-diagnose
  task; this feature makes it reproducible, doesn't fix it).

## Design decisions (locked 2026-07-04, operator-confirmed; revised after design review)

- **Debug-gated, app-global, not always-on.** An app-level "Debug logging"
  toggle in Settings (persisted in `Preferences`) gates capture. When ON, the
  ring accumulates across peers/sessions until cleared or capped. When OFF,
  `log()` is an early no-op. This is an operator-owned diagnostic dump for the
  operator's own dev/testing, destinations operator-chosen (sent to the agent
  or the workstation) — NOT end-user telemetry. **Revisit condition:** if the
  product later wants always-on telemetry for end-user bugs, the privacy
  posture tightens then (full scrub of previews; not now).
- **Capture surface = "all the logs useful for debugging broadly,"** not just
  the existing 15 `debugPrint`s. This is the key revision from the design
  review (which flagged that routing existing breadcrumbs misses the
  `ConnectionManager` reconnect/backoff/room-snapshot/working-state
  transitions the named intermittent bugs actually need). The expanded
  surface (Unit 4):
  - **ConnectionManager** (first-class, the A1 gap): `connecting → online →
    retrying(attempt, delayMs) → offline`, `_onChannelLost`,
    `_replaySubscriptions` (resume hydration), `_onControl` room/presence/
    snapshot adoption, `markRoomWorking`/`_markActiveRoomOffline` (working
    convergence), duplicate-connection takeover.
  - **The existing 15 sites**: `ws-in` frame demux, `msg-send`/`msg-echo`,
    `msg-failed`, `session-gate` drops (`missing_session_id`/
    `session_mismatch`/`active_session_unknown`), `session-sync` failures.
    (Tags corrected from the review: `:341` is `msg-failed`, `:538` is
    `session-gate`, only `:425` is `session-sync`.)
  - **Sync/replay**: `session_history` replay dedup, transcript-event
    identity collisions (the duplication bug's surface), backfill triggers.
- **Privacy posture: operator debug dump, destinations operator-chosen.**
  Truncated message preview (`_preview(text, image)`) IS persisted (it's
  diagnostic for swallowed/dup/not-delivered bugs). Scrub only **full message
  bodies, image data, and tool args/results**. This is tighter than "log
  everything" but looser than the earlier end-user-telemetry scrub. The
  typed-event registry (below) makes the per-event scrub explicit.
- **Share format:** jsonl. Matches the extension's `audit.jsonl` so a single
  message id greps across all three sides; machine-parseable for triage.
  `session_id` + message `id` fields disambiguate which session a line belongs
  to in a multi-session dump.
- **Retention:** 1 MiB cap, single file, ring-truncate at cap (drop oldest
  lines). With the expanded capture surface the per-turn volume is higher
  (~10-20 lines/turn incl. ConnectionManager transitions), but 1 MiB still
  covers the operator's "few hours to hit errors" window with headroom.
- **Crash-resilient flush** (from the review): debounced 2s flush for routine
  lines, BUT critical events (send attempt, send failure/timeout, session-gate
  drop, status retry/offline/online, room snapshot/session rotation, lifecycle
  pause/detach) flush immediately. The diagnostic tail is the whole point;
  losing it on a crash defeats the feature.
- **Export reads from the file** (the source of truth), not the in-memory ring:
  `export()` force-flushes, then reads the file. This recovers lines that
  already reached disk even if the in-memory ring diverged.
- **Relay file sink:** DONE 2026-07-04 (`story-relay-retroactive-file-logging`,
  stage:review) — `REMOTEPI_RELAY_LOG_DIR` + `tracing-appender` daily rotation,
  `EnvFilter` from `RUST_LOG`, cross-PC `pi_envelope` forward-path `debug!`
  with `env_id_tail` correlation.

## Architectural choice

**Typed `DebugEvent` registry in `domain/` + file-backed adapter in `data/` +
DI singleton + app-global debug toggle.** The app's `domain/` (contracts) ←
`data/` (adapters) ← `config/` (DI) layering (`app/CLAUDE.md`) fits a ring
log exactly: a `DebugLog` port + a typed `DebugEvent` registry the call sites
emit, a `DebugLogImpl` adapter that persists to `getApplicationDocumentsDirectory`,
and a DI singleton gated by a `Preferences` debug flag.

**Typed events, not `Map<String, Object?>`** (from the review's B2/C1). The
reviewer flagged the open-map API as too weak for a release-log and offloading
the scrub invariant to 15+ call sites. Debug-gating loosens that from
security-critical to code-quality, but a typed registry is still the right
shape: each `DebugEvent` variant owns its allowed fields and its scrub, the
tag is an enum (not a free string), and the adapter rejects non-primitive /
oversized values. This documents the capture surface and makes the scrub
explicit per-event rather than hoping each call site remembers.

Rejected: a `package:logging` hierarchy. Heavier; the survey already noted
it's in `pubspec.lock` but unused. The ring log has one job: retroactive
capture of diagnostic events. A typed registry + a 60-line adapter beats a
framework.

## Implementation Units

### Unit 1: `DebugLog` port + `DebugEvent` registry
**File**: `app/lib/domain/contracts/debug_log.dart` (+ export in `contracts.dart`)
**Story**: `story-app-debug-log-adapter` (split A — see Implementation Order)

```dart
/// Typed diagnostic event. Each variant owns its allowed fields and its
/// scrub (full message bodies / image data / tool args+results are NEVER
/// fields; a truncated preview IS allowed for `msgSend`). Tag is an enum,
/// not a free string — the registry IS the capture surface.
sealed class DebugEvent {
  final DebugTag tag;
  final DateTime ts;
  const DebugEvent(this.tag, this.ts);
  /// Canonical serializer: every variant serializes through this one method.
  /// Tests assert no forbidden keys (body, image, data, args, result, prompt,
  /// message, ct) and that all string fields are capped (review B2/E3).
  Map<String, Object?> toJson();
}
// Variants (one per capture site family):
//   WsInEvent        {bytes, kind, stage?, senderRoom?, controlType?, error?}
//   MsgSendEvent     {id, blocked?, preview?}   // preview = truncated _preview
//   MsgEchoEvent     {id}
//   MsgFailedEvent   {id, code, detail}         // detail scrubbed to a short reason
//   SessionGateEvent {messageType, reason, sessionIdTail?}
//   SessionSyncEvent {err}                       // err = short reason, no content
//   ConnStatusEvent  {status, attempt?, delayMs?, peerTail?, room?}
//   ConnChannelLostEvent {peerTail?, room?, stale}  // stale=true = replaced
//     channel's onDone safely ignored (connection_manager.dart:1166-1170);
//     stale=false = current channel lost → retry started. THIS is the event
//     that distinguishes duplicate-connection takeover from real channel loss
//     (the idea-mobile-drop-half-open-tcp question).
//   ConnHydrateEvent {action, room?, snapshotCount?}
//   RoomSnapshotEvent{room, presenceCount?, working?}
//   WorkingConvEvent {room, working, reason}
//   ReplayDedupEvent {sessionId, eventIdTail, dropped}
//   ... (one per ConnectionManager/sync transition in the expanded surface)

/// Extends `Service` so `addService<DebugLog>` (the disposing DI path) wires
/// `dispose()` → flush on app teardown (review C3). `addInstance`/`addOther`
/// do NOT dispose; the type bound `T extends Service` requires this.
abstract interface class DebugLog implements Service {
  /// Early no-op when debug mode is OFF (checked via Preferences). When ON,
  /// appends the event to the ring + schedules flush (immediate for critical
  /// events, debounced for routine).
  void log(DebugEvent event);

  /// Force-flush, then read the file (source of truth). Null when empty.
  /// Works while debug logging is OFF (reads whatever is on disk).
  Future<String?> export();

  /// Wipe ring + file. Does NOT clear `Preferences.debugLogging` (the toggle
  /// state is separate from the captured data).
  Future<void> clear();
}
```

**Acceptance Criteria**:
- [ ] `DebugEvent` sealed class + variants in `domain/contracts/`; `DebugTag` enum.
- [ ] No variant carries full message body / image data / tool args or results.
- [ ] `MsgSendEvent.preview` is the truncated `_preview`, never full text.
- [ ] Each variant serializes through the canonical `toJson()`; a registry test
      asserts no forbidden keys (`body`, `image`, `data`, `args`, `result`,
      `prompt`, `message`, `ct`) and that all string fields are capped (review B2).
- [ ] `DebugLog implements Service` (so `addService<DebugLog>` disposes).
- [ ] No imports of `dart:io`, `path_provider`, or `share_plus` (domain purity).
- [ ] Exported via `contracts.dart`.

### Unit 2: `DebugLogImpl` adapter + lifecycle
**File**: `app/lib/data/debug/debug_log_impl.dart`
**Story**: `story-app-debug-log-adapter` (split A)

```dart
class DebugLogImpl implements DebugLog {
  static const int _maxBytes = 1 << 20; // 1 MiB cap
  static const Duration _flushInterval = Duration(seconds: 2);
  // log(): if !_debugEnabled() return; encode (typed→jsonl, cap field lengths,
  //        catch encode errors); append + truncate-on-append; immediate or
  //        debounced flush per tag.
  // export(): flushNow(); read file line-by-line; return joined (or null).
  // clear(): wipe ring + file.
  // _ensureLoaded(): warm ring from file, skip unparseable lines.
  // dispose(): flushNow() (best-effort).
  static const Set<DebugTag> _immediateFlushTags = {
    DebugTag.msgSend, DebugTag.msgFailed, DebugTag.sessionGate,
    DebugTag.sessionSync, DebugTag.connStatus, DebugTag.connChannelLost,
    DebugTag.connHydrate, DebugTag.workingConv, DebugTag.roomSnapshot,
  };
  // (lifecyclePause/Detach removed — not defined as events in Units 1/4.
  final List<String> _ring = [];
  Timer? _flushTimer;
  String? _filePath;
  final bool Function() _debugEnabled; // reads Preferences (no I/O in hot path)
  // log(): if !_debugEnabled() return; encode (typed→jsonl, cap field lengths,
  //        catch encode errors); append + truncate-on-append; immediate or
  //        debounced flush per tag.
  // export(): flushNow(); read file line-by-line; return joined (or null).
  // clear(): wipe ring + file.
  // _ensureLoaded(): warm ring from file, skip unparseable lines.
  // dispose(): flushNow() (best-effort).
}
```

**Implementation Notes** (from the review):
- **Cap enforced on append**, not just on flush — truncate oldest lines in
  `log()` immediately after encoding, so the in-memory ring never overshoots.
- **Per-field length caps** before `jsonEncode` — a malformed untrusted string
  (e.g. `ws-in` decode error, `senderRoom`) can't dominate the ring. Truncate
  field values to e.g. 256 chars; drop the entry if encoding fails.
- **Critical-event immediate flush** (the `_immediateFlushTags` set) — the
  diagnostic tail survives a crash. Routine lines keep the 2s debounce.
- **Export reads from the file** (source of truth), line-by-line, skipping
  unparseable lines — recovers disk state even if the in-memory ring diverged.
- **Never throws**: `log/export/clear/dispose` catch `Object, StackTrace`; the
  flush timer callback catches internally; failures emit a scrubbed
  `debugPrint('[debug-log] ...')` and never rethrow. The logger must not break
  the app even on platform/quota/permission failure.
- **Dispose wired** (review C3): register via the DI path that disposes
  (`addService` with `onDispose: debugLog.dispose()`), NOT `addInstance`/
  `addOther` (which don't dispose). `disposeDependencies()` in `main.dart`
  then flushes pending lines on app teardown.

**Acceptance Criteria**:
- [ ] Ring persists to `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`.
- [ ] Ring survives app restart (warm-from-file, skipping corrupt lines).
- [ ] Cap enforced on append (no overshoot between flushes).
- [ ] Per-field length caps; a huge untrusted string can't evict the window.
- [ ] Critical events flush immediately; routine events debounce 2s.
- [ ] `export()` reads from the file after a forced flush.
- [ ] All public methods + timer callback catch `Object`; never rethrows.
- [ ] `disposeDependencies()` flushes pending lines (lifecycle test).

### Unit 3: App-global debug toggle + export/clear UI
**File**: `app/lib/config/dependencies.dart`, `app/lib/ui/settings/*`, `app/lib/data/preferences/preferences.dart`
**Story**: `story-app-debug-toggle-ui` (split B)

- Add `debugLogging` (bool, default false) to `Preferences` (persisted).
- Register `DebugLogImpl` via `addService` (disposing) so `dispose()` flushes.
- Add `isDebugLogging` / `setDebugLogging(bool)` / `exportDebugLog()` /
  `clearDebugLog()` to `SettingsViewModel`.
- Add a `_DebugSection` to `settings_page.dart`:
  - **Debug logging** switch (on/off).
  - **Export debug log** → share sheet (`share_plus`, jsonl file).
  - **Clear debug log** → confirm dialog, then `clear()`.
- When OFF, `DebugLogImpl.log()` early-returns (cheap no-op).

**Acceptance Criteria**:
- [ ] Toggle persists across restarts in `Preferences`.
- [ ] When OFF, `log()` is a no-op (no serialization work, no file I/O).
- [ ] When ON, capture flows; export opens the share sheet with the jsonl file.
- [ ] `disposeDependencies()` flushes (lifecycle test passes).
- [ ] Export disabled / shows "no log yet" when `export()` returns null.

### Unit 4: Emit diagnostic events at the expanded capture surface
**File**: `app/lib/data/transport/connection_manager.dart` (NEW events), `app/lib/data/transport/ws_transport.dart`, `app/lib/data/sync/sync_service.dart`
**Story**: `story-app-capture-routing` (split C)

Two parts:

**4a — Route the existing 15 `debugPrint` sites** through `DebugLog.log(event)`,
keeping the existing `debugPrint` as the verbose logcat path. `DebugLog` is
persistence-only (it does NOT mirror to logcat — review B3); the existing
`debugPrint` calls stay as-is. Corrected tags:

| Tag | File:line | Persisted fields | Scrub |
|---|---|---|---|
| `ws-in` | `ws_transport.dart:82,103,106,113,117,127,133,142` | `bytes`, `kind`, `stage`/`senderRoom`/`controlType`/`error` | field-length caps |
| `msg-send` | `sync_service.dart:212,245,260` | `id`, `blocked`/state, `preview` (:260 only) | full body scrubbed; preview = truncated `_preview` |
| `msg-echo` | `sync_service.dart:610` | `id` | — |
| `msg-failed` | `sync_service.dart:341` | `id`, `code`, `detail` | detail = short reason |
| `session-gate` | `sync_service.dart:538` | `messageType`, `reason`, `sessionIdTail` | — |
| `session-sync` | `sync_service.dart:425` | `err` | err = short reason |

**4b — ADD first-class events at `ConnectionManager`** (the A1 gap the review
flagged — this is what makes the ring log actually diagnose the reconnect
cluster, not just repack existing breadcrumbs). Line numbers verified against
`app/lib/data/transport/connection_manager.dart` (review v2 E):

| Tag | File:line | Persisted fields |
|---|---|---|
| `conn-status` | `:534` (`StatusConnecting`), `:547` (`StatusOnline`), `:1183` (`StatusRetrying` in `_scheduleRetry:1177`) | `status`, `attempt?`, `delayMs?`, `peerTail?`, `room?` (no `StatusOffline` emitted today — leave it out of capture until/unless added) |
| `conn-channel-lost` | `_onChannelLost:1162-1175`, both branches | `peerTail?`, `room?`, `stale` (stale=true at `:1167` = replaced channel's onDone safely ignored; stale=false at `:1173` = current channel lost → retry started) |
| `conn-hydrate` | `_replaySubscriptions:1136-1143` (called from `requestResumeHydration:329-337`) | `action`, `room?`, `snapshotCount?` |
| `room-snapshot` | `_onControl:566`, `RoomAnnounced` case `:612`, `RoomMetaUpdated` case `:697`, `RoomsSnapshot` case `:743` | `room`, `presenceCount?`, `working?` |
| `working-conv` | `markRoomWorking:914` (guards `:921`, mutation `:938`), `_markActiveRoomOffline:1238` (triggered from `_startPing:1218`) | `room`, `working`, `reason` |
| `replay-dedup` | `sync_service.dart` replay/backfill | `sessionId`, `eventIdTail`, `dropped` |

The **`conn-channel-lost {stale}` event is the duplicate-connection-takeover
proof** for the app side — it answers "did my app correctly ignore the stale
channel's onDone, or did my current channel die and trigger retry?" (the
self-sustaining-retry-loop footgun the code comment at `:1166-1170` warns about).
The relay-side half of the same question ("did the relay supersede the old
conn immediately on duplicate auth, or after ping timeout?") lands as a
small follow-up: `story-relay-duplicate-auth-supersession-log`.

**Acceptance Criteria**:
- [ ] All 15 existing sites route through `DebugLog.log`; logcat unchanged.
- [ ] `ConnectionManager` emits the 6 new event types at the transitions listed.
- [ ] No full message body / image data / tool args or results in any event.
- [ ] `msg-send` persisted line includes the truncated `preview`; NOT full text.
- [ ] Correlation: `id` in `msg-send`/`msg-echo` matches the extension's
  `app user_message id` and the relay's `env_id_tail`.
- [ ] A fake-`DebugLog` test asserts the expected events fire on a reconnect/
  send/gate path (covers the "routing actually happens" gap the review E2
  flagged).

### Unit 5: Cross-side correlation key (relay half DONE)
**File**: relay (done), app confirmation
**Story**: none — verification only

The relay half shipped. The app half is implicit in Unit 4: the `id` field in
`msg-send`/`msg-echo` IS the correlation key. Confirm at implementation time
that the app's `user_message` id, the extension's `app user_message id`, and
the relay's `env_id_tail` are the same value end-to-end (survey says yes; a
one-line grep check).

### Unit 6: Transport-frame observability
**File**: parked — `story-add-transport-frame-observability` (drafting)
**Story**: `story-add-transport-frame-observability` (re-parent to this feature)

Privacy-safe, throttled diagnostic surface for dropped/malformed relay and
peer-channel frames. Already a drafting story; **re-parent to this feature**
(the review E1 caught that its frontmatter still points to
`epic-remote-session-resilience-refactor`). Design it as a follow-on child
after the ring log lands — it extends the same `DebugEvent` surface with
frame-drop counters.

### Unit 7: Session-replacement integration harness
**File**: `pi-extension/test/` (new)
**Story**: to spawn as `story-session-replacement-harness`

Drives a real `ctx.newSession()` / `/reload` / `/resume` through the actual
SDK `ExtensionRunner` and asserts post-replacement delivery + history +
actions. **Highest-risk unit** — feasibility depends on whether the
installed SDK's `ExtensionRunner` can be driven headless from a vitest.

**Pre-mortem spike first** (review D1): spike whether `ExtensionRunner` can
be instantiated and driven from a test. If feasible, spawn
`story-session-replacement-harness` with the full assertion matrix. If NOT
feasible, the story must produce an **alternate verification plan** before
session-replacement fixes proceed — NOT merely "xfail + ring log": options
include a process-level harness around a real Pi session, an SDK-seam wrapper
test exercising `runtime.assertActive()`, or a documented manual smoke recipe
with required ring/extension/relay artifacts attached to the work item. Do
not count "ring log + manual reproduction someday" as equivalent to CI
harness coverage.

## Implementation Order

Split into 3 stories (review F1 — the prior inline attempt failed; this is
heterogeneous work, not a single stride):

1. **`story-app-debug-log-adapter`** (Units 1+2) — typed `DebugEvent` registry
   + `DebugLog` port + `DebugLogImpl` adapter + lifecycle tests. Foundation;
   no UI, no capture sites yet.
2. **`story-app-debug-toggle-ui`** (Unit 3) — `Preferences.debugLogging` + DI
   wiring (disposing) + settings toggle + export/clear UI. Depends on #1.
3. **`story-app-capture-routing`** (Unit 4) — route the 15 existing sites +
   ADD the 6 `ConnectionManager` event types + privacy/correlation tests.
   Depends on #1; can run in parallel with #2.

Then:
4. **Unit 5** (correlation confirmation) — verification only, no story.
5. **Unit 6** (transport-frame observability) — re-parent + design as follow-on.
6. **Unit 7** (session-replacement harness) — spike first; pi-extension-side,
   runs in parallel with the app stories.

## Testing

### Unit tests: `app/test/data/debug/debug_log_impl_test.dart`
- Ring persists across `dispose()` + re-instantiate (warm-from-file, skips
  corrupt lines).
- Cap enforced on append (no overshoot between flushes).
- Per-field length caps: a huge untrusted string can't evict the window.
- Critical events flush immediately; routine events debounce (no per-`log()`
  file write for routine tags).
- `export()` reads from the file after a forced flush; returns null when empty.
- `clear()` wipes ring + file.
- All public methods + timer callback catch `Object`; never rethrows.
- `disposeDependencies()` flushes pending lines (lifecycle test — review C3).
- `log()` is a no-op when `Preferences.debugLogging` is false.

### Capture-site + routing tests: `app/test/data/...` (review E2)
- A fake `DebugLog` records the expected `DebugEvent`s on:
  - a reconnect path (status transitions, hydrate, room snapshot, working conv).
  - a send path (`msg-send` with truncated preview, `msg-echo`).
  - a session-gate drop (`session-gate` with reason).
  - a `msg-failed` and `session-sync` failure.
- `MsgSendEvent.preview` is the truncated `_preview`, NOT full text.
- Correlation: the persisted `id` matches the extension's `app user_message id`.
- A static/registry test fails if a declared `DebugEvent` variant has no
  routing test (catches "a capture site silently stopped emitting").

### UI test: `app/test/ui/settings/settings_page_test.dart`
- Toggle flips `Preferences.debugLogging` and persists.
- "Export debug log" opens the share sheet (mock `share_plus`); disabled /
  "no log yet" when `export()` returns null.
- "Clear debug log" confirms then wipes.

### Harness tests (Unit 7, if feasible)
- `ctx.newSession()` then `sendUserMessage` lands on the fresh ctx.
- `/reload` then history replays without stale-ctx throw.
- `/resume` then backfill populates the log (covers
  `story-mobile-chat-blank-on-pair-after-pre-pair-work`).

## Risks

- **Capture-volume higher than the 15-site estimate**: adding `ConnectionManager`
  transitions raises per-turn volume (~10-20 lines/turn). Mitigation: 1 MiB cap
  still covers the operator's "few hours" window; monitor and tighten if a
  reconnect storm evicts too fast.
- **Crash before the immediate flush of a critical event**: even immediate
  flush is async to disk. Mitigation: the events most likely to precede a
  crash (status transitions, send failure, session-gate drop) are in the
  immediate-flush set; the file is the export source of truth.
- **`share_plus` platform differences**: iOS vs Android share-sheet behavior.
  Low risk — the export is a plain jsonl file; both platforms handle it.
- **Harness infeasibility** (Unit 7): the installed SDK may not expose
  `ExtensionRunner` for headless driving. Mitigation: spike first; the fallback
  is an alternate verification plan (not just xfail), per review D1.
- **Routing 15 existing + 6 new sites through a new path could change behavior
  subtly**: mitigation — `DebugLog` is persistence-only (logcat `debugPrint`s
  stay as-is); the new events are at state transitions, not in hot loops; a
  registry test catches a silently-stopped emitter.
- **Privacy posture assumes operator-owned destinations**: if the product later
  ships always-on telemetry to end users, the scrub must tighten (full preview
  scrub, not just full-body). Recorded as a revisit condition above.

## Relationship to released bold work

Consumes the generated-protocol codegen (`epic-bold-generated-protocol`,
done) for any new diagnostic frame types. Does not duplicate
`epic-bold-reachability-contract` state-machine work — this feature adds
*instrumentation onto* the reachability states, not new states.
