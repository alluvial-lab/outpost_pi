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
updated: 2026-07-04
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

## Design decisions (locked 2026-07-04, operator-confirmed)

- **Release gating:** always-on, privacy-scrubbed subset. Intermittent bugs
  happen in release, and `adb logcat` only covers USB; an always-on ring log
  is what converts the "anecdotal" case to diagnosable. Privacy is enforced
  by scrubbing at the capture sites (never bodies/images), not by gating the
  logger off.
- **Share format:** jsonl. Matches the extension's `audit.jsonl` so a single
  message id greps across all three sides; machine-parseable for triage.
- **Ring log retention:** 1 MiB cap, single file, ring-truncate at cap (drop
  oldest lines, no multi-file rotation). Grounded in the measured capture
  surface: 15 `debugPrint` sites, all state-transition lines (NOT per-token
  `agent_chunk` streaming), so volume is per-turn (~5-10 lines/turn). 1 MiB
  covers 48h of reconnect-storm pathology with headroom; the operator's actual
  "few hours to hit errors" window is < 100 KiB even at heavy use.
- **Capture surface:** the 15 existing `debugPrint` sites in `ws_transport.dart`
  (`[ws-in] …`) and `sync_service.dart` (`[msg-send]`, `[msg-echo]`,
  `[session-sync]`, send-timeout, session-gate rejections). The one scrub
  point: `[msg-send] id=$id text=${_preview(text, image)}`
  (`sync_service.dart:260`) drops the `text=` preview in the persisted copy,
  keeps it in logcat (dev-only).
- **Relay file sink:** DONE 2026-07-04 (`story-relay-retroactive-file-logging`,
  stage:review) — `REMOTEPI_RELAY_LOG_DIR` + `tracing-appender` daily rotation,
  `EnvFilter` from `RUST_LOG`, cross-PC `pi_envelope` forward-path `debug!`
  with `env_id_tail` correlation.

## Architectural choice

**Thin `DebugLog` port in `domain/` + file-backed adapter in `data/` +
routed capture at the existing `debugPrint` sites.** The app already has a
clean `domain/` (contracts) ← `data/` (adapters) ← `config/` (DI) layering
(`app/CLAUDE.md`); the ring log fits it exactly: a `DebugLog` port the call
sites depend on, a `DebugLogImpl` adapter that persists to
`getApplicationDocumentsDirectory`, and a DI singleton so all call sites
share one ring. This keeps domain logic free of filesystem I/O (Ports &
Adapters) and makes the adapter swappable in tests.

Rejected: a logging package (`package:logging`) hierarchy. Heavier, and the
survey already noted it's in `pubspec.lock` but unused — adopting it would
add a configuration surface (loggers, levels, handlers) for no gain over a
single-purpose ring. The ring log has one job: retroactive capture of the
state-transition lines that map to the resilience fixes. A 60-line adapter
beats a framework.

## Implementation Units

### Unit 1: `DebugLog` port (lead child — the ring log)
**File**: `app/lib/domain/contracts/debug_log.dart` (+ export in `contracts.dart`)
**Story**: `story-app-persistent-ring-log`

```dart
abstract class DebugLog {
  /// Appends a structured line. [tag] is a short grep-able prefix (`ws-in`,
  /// `msg-send`, …). [fields] carries routing metadata + ids ONLY — never
  /// payload. Callers scrub; this contract does not parse payloads.
  void log(String tag, {Map<String, Object?>? fields});

  /// Persisted log as jsonl, or null when empty. Drives the share-sheet export.
  Future<String?> export();

  /// Clears the persisted log (after export, or to reset).
  Future<void> clear();
}
```

**Acceptance Criteria**:
- [ ] `DebugLog` is an abstract class in `domain/contracts/`.
- [ ] Exported via `contracts.dart`.
- [ ] No imports of `dart:io`, `path_provider`, or `share_plus` (domain purity).

### Unit 2: `DebugLogImpl` adapter
**File**: `app/lib/data/debug/debug_log_impl.dart`
**Story**: `story-app-persistent-ring-log`

```dart
class DebugLogImpl implements DebugLog {
  static const int _maxBytes = 1 << 20; // 1 MiB cap
  final List<String> _ring = []; // jsonl lines
  Timer? _flushTimer; // debounced 2s flush
  String? _filePath;
  // log(): append to ring, mirror to debugPrint (logcat), schedule flush
  // export(): flush + return ring joined
  // clear(): wipe ring + file
  // _ensureLoaded(): warm ring from existing file on startup
  // dispose(): final flush (best-effort)
}
```

**Implementation Notes**:
- **1 MiB cap is byte-based, not line-based** — ring-truncate drops oldest
  lines until under cap. (Earlier 8000-line draft was a guess; the measured
  surface justifies the byte cap for 48h coverage.)
- **Debounced flush** (2s timer): appends write to the in-memory ring
  immediately; a timer batches file writes to avoid per-frame I/O. Worst-case
  crash loss = the unflushed tail (≤2s of lines).
- **Warm on startup**: `_ensureLoaded()` reads the existing file into the ring
  so a restart keeps recent history (the whole point — survive reboot).
- **Never throw**: the logger must not break the app. All file I/O wrapped in
  try/catch with `debugPrint` fallback.
- **Privacy is at the call site, not here**: the adapter serializes whatever
  fields it receives. The scrubbing happens in Unit 4 (call-site routing).

**Acceptance Criteria**:
- [ ] Ring persists to `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`.
- [ ] Ring survives app restart (warm-from-file on `_ensureLoaded`).
- [ ] Ring is capped at 1 MiB (oldest lines dropped); no unbounded growth.
- [ ] Crash in file I/O does NOT propagate (logger never breaks the app).
- [ ] Debounced flush; no per-frame file write.

### Unit 3: DI wiring + export UI
**File**: `app/lib/config/dependencies.dart`, `app/lib/ui/settings/*`
**Story**: `story-app-persistent-ring-log`

- Register `DebugLogImpl` as a singleton in `setupDependencies()` (alongside
  `LocalBoxes`).
- Add `exportDebugLog()` / `clearDebugLog()` to `SettingsViewModel`.
- Add a `_DebugSection` to `settings_page.dart` with two actions:
  - **Export debug log** → `share_plus` share sheet (jsonl file).
  - **Clear debug log** → confirm dialog, then `clear()`.

**Acceptance Criteria**:
- [ ] `DebugLog` resolves via `injector.get<DebugLog>()` in data + UI.
- [ ] Settings page has an "Export debug log" action that opens the share sheet.
- [ ] Exported content is jsonl; empty-when-nothing-to-export returns null
  (action disabled or shows "no log yet").

### Unit 4: Route capture sites (the 15 `debugPrint`s)
**File**: `app/lib/data/transport/ws_transport.dart`, `app/lib/data/sync/sync_service.dart`
**Story**: `story-app-persistent-ring-log`

Route the 15 existing `debugPrint` sites through `_debugLog.log(tag, fields: …)`.
Each call keeps its existing `debugPrint` (logcat path unchanged) AND persists
a privacy-scrubbed jsonl line. The full capture surface:

| Tag | File:line | Fields persisted | Scrub |
|---|---|---|---|
| `ws-in` | `ws_transport.dart:82,103,106,113,117,127,133,142` | `bytes`, `kind`, `stage`/`senderRoom`/`controlType`/`error` | — |
| `msg-send` | `sync_service.dart:212,245,260` | `id`, `blocked`/send state | **drop `text=` preview at :260** |
| `msg-echo` | `sync_service.dart:610` | `id` | — |
| `session-sync` | `sync_service.dart:341,425,538` | `err`/state | — |

**The scrub point** (`sync_service.dart:260`): the persisted copy logs
`{id: …}` only; the logcat `debugPrint` keeps `id=$id text=${_preview(text, image)}`
for dev. This is the single explicit privacy boundary in the capture surface.

**Acceptance Criteria**:
- [ ] All 15 sites route through `DebugLog.log` (ring persists).
- [ ] Existing `debugPrint` behavior unchanged (logcat still gets every line).
- [ ] `[msg-send]` persisted line has NO `text`/image preview; logcat does.
- [ ] No message body or image content reaches the persisted/shared log.
- [ ] Correlation: a message id in `[msg-send]` / `[msg-echo]` matches the
  extension's `app user_message id=…` and the relay's `env_id_tail`.

### Unit 5: Cross-side correlation key (relay half DONE)
**File**: relay (done), app confirmation
**Story**: none — verification only

The relay half shipped (`story-relay-retroactive-file-logging`). The app
half is implicit in Unit 4: the `id` field in `msg-send`/`msg-echo` IS the
correlation key. Confirm at implementation time that the app's `user_message`
id, the extension's `app user_message id`, and the relay's `env_id_tail` are
the same value end-to-end (survey says yes; a one-line grep check).

### Unit 6: Transport-frame observability
**File**: parked — `story-add-transport-frame-observability` (drafting)
**Story**: `story-add-transport-frame-observability` (already exists)

Privacy-safe, throttled diagnostic surface for dropped/malformed relay and
peer-channel frames. Already a drafting story; re-parented to this feature.
Design it as a follow-on child after the ring log lands — it extends the
same `DebugLog` surface (or a relay-side equivalent) with frame-drop counters.

### Unit 7: Session-replacement integration harness
**File**: `pi-extension/test/` (new)
**Story**: to spawn as `story-session-replacement-harness`

Drives a real `ctx.newSession()` / `/reload` / `/resume` through the actual
SDK `ExtensionRunner` and asserts post-replacement delivery + history +
actions. **Highest-risk unit** — feasibility depends on whether the
installed SDK's `ExtensionRunner` can be driven headless from a vitest.

**Pre-mortem spike first**: before designing the full harness, spike whether
`ExtensionRunner` can be instantiated and driven from a test. If feasible,
spawn `story-session-replacement-harness` with the full assertion matrix. If
not, document exactly why and ship an honest xfail + the ring log as the
diagnostic substitute (the epic's strategic-decisions section already
permits this fallback).

## Implementation Order

1. **Units 1-4** (the ring log) — `story-app-persistent-ring-log`, single
   stride. This is the lead and the actual gap closure; the rest build on it.
2. **Unit 5** (correlation confirmation) — verification only, no story.
3. **Unit 6** (transport-frame observability) — `story-add-transport-frame-
   observability` (already drafting), follow-on after the ring log surface
   exists.
4. **Unit 7** (session-replacement harness) — spike first, then spawn
   `story-session-replacement-harness` if feasible. Highest-risk; runs in
   parallel with the above since it's pi-extension-side, not app-side.

## Testing

### Unit tests: `app/test/data/debug/debug_log_impl_test.dart`
- Ring persists across `dispose()` + re-instantiate (warm-from-file).
- Ring caps at 1 MiB (oldest dropped; no unbounded growth).
- File I/O failure does NOT throw (logger never breaks the app).
- Debounced flush coalesces writes (no per-`log()` file write).
- `export()` returns null when empty; jsonl when populated.
- `clear()` wipes ring + file.

### Capture-site tests: `app/test/data/sync/sync_service_test.dart` (extend)
- A `[msg-send]` line persists with `id` but NO `text`/image preview.
- A `[msg-echo]` line persists with `id`.
- Correlation: the persisted `id` matches what a mock extension would emit
  as `app user_message id`.

### UI test: `app/test/ui/settings/settings_page_test.dart` (extend)
- "Export debug log" action opens the share sheet (mock `share_plus`).
- Action disabled / shows "no log yet" when `export()` returns null.

### Harness tests (Unit 7, if feasible)
- `ctx.newSession()` then `sendUserMessage` lands on the fresh ctx.
- `/reload` then history replays without stale-ctx throw.
- `/resume` then backfill populates the log (covers
  `story-mobile-chat-blank-on-pair-after-pre-pair-work`).

## Risks

- **Ring log warm-from-file on a corrupted file**: a half-written jsonl from
  a crash could fail to parse. Mitigation: read line-by-line, skip unparseable
  lines (don't fail the whole warm). Already in the "never throw" rule.
- **`share_plus` platform differences**: iOS vs Android share-sheet behavior.
  Low risk — the export is a plain text/jsonl file; both platforms handle it.
- **Harness infeasibility** (Unit 7): the installed SDK may not expose
  `ExtensionRunner` for headless driving. Mitigation: spike first; the epic
  already permits the xfail + ring-log substitute fallback. This is the
  riskiest unit and the one most likely to surface a hard constraint.
- **Capture-site regression**: routing 15 `debugPrint`s through a new path
  could change behavior subtly (e.g. a `debugPrint` that was inside a hot
  loop). Mitigation: the capture surface is state-transition lines, not
  per-token; none are in hot loops. Existing tests stay green.

## Relationship to released bold work

Consumes the generated-protocol codegen (`epic-bold-generated-protocol`,
done) for any new diagnostic frame types. Does not duplicate
`epic-bold-reachability-contract` state-machine work — this feature adds
*instrumentation onto* the reachability states, not new states.
