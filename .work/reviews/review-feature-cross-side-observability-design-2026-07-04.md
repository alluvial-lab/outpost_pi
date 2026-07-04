# Review: feature-cross-side-observability design

## 1. Verdict

**REWORK NEEDED.** The design is aimed at the right critical path and the app-side persistent ring log is the right first capability, but the current capture surface does not yet satisfy the feature goal: routing the 15 existing app `debugPrint` sites persists transport/send/session-gate breadcrumbs, but it misses the `ConnectionManager` reconnect/backoff/room-snapshot/working-state transitions that the named intermittent bugs explicitly need. Before implementation, revise the design to make the ring log a typed, privacy-safe diagnostic event surface with explicit reconnect/session events, crash-resilient flushing semantics, disposal wiring, and a non-hand-wavy fallback plan for the real-SDK harness.

## 2. Confirmed strengths

- The observability-first framing is real, not a relabel: the parent epic correctly identifies that extension `audit.jsonl` is retroactive while phone/relay logs are not (`.work/active/epics/epic-targeting-and-session-lifecycle-contracts.md:18-31`), matching the survey table (`.work/backlog/idea-cross-side-logging-for-debug.md:14-28`).
- The feature correctly prioritizes the phone-side ring log over heavier telemetry. The survey names the app persistent ring log as the highest-leverage near-term slice and keeps `adb logcat` as the live USB path (`.work/backlog/idea-cross-side-logging-for-debug.md:81-91`).
- The count claim is correct for the two named files: 8 `debugPrint` calls in `ws_transport.dart` and 7 in `sync_service.dart` (`app/lib/data/transport/ws_transport.dart:82,103,106,113,117,127,133,142`; `app/lib/data/sync/sync_service.dart:212,245,260,341,425,538,610`).
- Within those 15 sites, `sync_service.dart:260` is the only direct user-message preview (`text=${_preview(text, image)}`). The other listed sites log frame lengths/kinds, send ids/states, session-gate metadata, request failure text, or echo ids.
- The intended layer direction is basically sound: a domain contract implemented by a data adapter and wired in config follows the app layering rule (`app/CLAUDE.md`; `app/lib/domain/CLAUDE.md`; `app/lib/data/CLAUDE.md`).
- The relay half is now consistent with the prior relay review: the story records tail-only peer/id logging and char-boundary-safe `id_tail` tests (`.work/active/stories/story-relay-retroactive-file-logging.md:62-92`).

## 3. Material challenges

### A. Does the design actually achieve the goal?

#### A1. The selected 15 sites miss the reconnect state transitions the target bugs require

**Challenge.** The design says the ring log captures “working convergence, room snapshot adoption, reconnect hydration, send-failure surfacing, pending-send backstop, stale-session history guards, session-gate rejections” (`.work/active/features/feature-cross-side-observability.md:32-36`, `:111-116`). The actual 15-site surface captures some send/session-gate facts, but not the app’s reconnect/backoff/hydration state machine.

**Evidence.** The named reconnect bug asks for phone-side timing across app reconnect backoff, WireGuard/5G bring-up, and app state-machine stall (`.work/backlog/idea-mobile-drop-slow-recovery.md:47-49`). Those transitions live in `ConnectionManager`: connect emits `StatusConnecting` / `StatusOnline` and replays subscriptions (`app/lib/data/transport/connection_manager.dart:520-553`), retries emit `StatusRetrying(nextRetry, attempt)` (`:1177-1184`), resume hydration calls `_replaySubscriptions()` (`:329-337`, `:1136-1143`), room snapshots/announcements are applied in `_onControl` (`:566-706`), and `markRoomWorking` / `_markActiveRoomOffline` drive working/live convergence (`:914-929`, `:1194-1252`). None of those have `debugPrint` today; a global grep only finds the 15 app data sites plus an unrelated temporary UI `[input.enter]` line (`app/lib/ui/chat/widgets/input_bar.dart:196`).

**Recommendation.** Expand Unit 4 beyond “route existing `debugPrint`s.” Add typed `DebugLog` events at `ConnectionManager._emit`, `_scheduleRetry`, successful `_connect`, `_onChannelLost`, `_replaySubscriptions`, `_onControl` room/presence changes, `_markActiveRoomOffline`, and `markRoomWorking`. Keep them low-volume and privacy-safe: status, attempt, delay, peer tail, room id, session tail, working bool, snapshot counts, and monotonic timestamp.

#### A2. Crash survivability is overstated for the most diagnostic tail

**Challenge.** Warm-from-file survives clean restart after a flush, not a hard app crash just after the lines that matter. The design acknowledges “Worst-case crash loss = the unflushed tail (≤2s of lines)” (`feature-cross-side-observability.md:188-190`), but for a crash-triggered bug that tail is often the evidence.

**Evidence.** `main.dart` only calls `disposeDependencies()` from the Flutter widget `dispose()` path (`app/lib/main.dart:72-75`), not on process crash/kill. Flutter lifecycle docs in the mobile reference also warn lifecycle notifications are not guaranteed on abrupt termination (`.agents/skills/flutter-mobile/SKILL.md`, “WebSocket and lifecycle behavior”).

**Recommendation.** Change the durability policy. Either write-through each line with a small append+truncate strategy (volume is low), or keep debouncing only for routine info but force immediate flush for high-value events: send attempt, send failure/timeout, session-gate drop, status retry/offline/online, room snapshot/session rotation, and lifecycle pause/detach. The design should state exactly which events are sync/flush-now.

#### A3. The cap must be enforced on append, with field-size clamps

**Challenge.** The design says “ring-truncate drops oldest lines until under cap” (`feature-cross-side-observability.md:184-186`) but does not say whether truncation happens on every `log()` or only before flush/export. If it is only on flush, the in-memory ring can overshoot; if fields are unconstrained, a single malformed/untrusted string can dominate the ring.

**Evidence.** The proposed API accepts `Map<String, Object?>` (`feature-cross-side-observability.md:151`), and the planned fields include untrusted or semi-untrusted strings such as `senderRoom`, `controlType`, `error`, and `err` (`feature-cross-side-observability.md:232-236`; `ws_transport.dart:117-145`; `sync_service.dart:425`).

**Recommendation.** Specify truncation in `log()` immediately after encoding, plus per-field string limits before JSON serialization. Drop or truncate a single oversized entry rather than letting it evict the whole diagnostic window.

### B. Is the privacy scrubbing sound?

#### B1. The current 15 sites do not have another direct payload debug line, but the design mislabels two sites

**Challenge.** The specific “is `sync_service.dart:260` the only message-content line?” claim holds for the 15 sites, but the Unit 4 table is inaccurate and should be corrected before implementation.

**Evidence.** `sync_service.dart:341-342` is `[msg-failed] id=$id code=$code detail=...`, not `session-sync`; `sync_service.dart:538-542` is `[session-gate] drop type=... room=... reason=...`, not `session-sync`; only `sync_service.dart:425` is `[session-sync] request failed: $err`. `ws_transport.dart` logs raw frame length/kind and decode error text, not raw envelopes (`:82-145`).

**Recommendation.** Fix the table tags to `msg-failed`, `session-sync`, and `session-gate`, and make each tag’s persisted fields explicit. Add an acceptance check that each tag is tested or manually verified.

#### B2. “Privacy is at the call site” is too weak for a shareable release log

**Challenge.** The design puts the privacy invariant on 15+ call sites and says the adapter “serializes whatever fields it receives” (`feature-cross-side-observability.md:195-196`). That is the wrong boundary for a release-on, shareable log: one future call site can accidentally persist `text`, `image.data`, `ct`, tool args/results, or an error object whose string contains payload.

**Evidence.** Project rules require fail-fast boundaries and generated/inferred contracts for variant sets (`.agents/rules/code-design.md`, “Single source of truth” and “Fail fast at boundaries”). The proposed `DebugLog.log(String tag, {Map<String,Object?>? fields})` is an open string + open map (`feature-cross-side-observability.md:145-152`).

**Recommendation.** Replace the open map with a typed diagnostic-event registry, e.g. `DebugLog.log(DebugEvent event)` where each event variant owns its allowed fields and scrubbing. At minimum, make `tag` an enum/const registry and have the adapter reject/discard forbidden field names (`text`, `image`, `data`, `body`, `payload`, `ct`, `args`, `result`, `prompt`, `message`) and non-primitive/oversized values.

#### B3. The logcat-vs-persisted split is underspecified and internally inconsistent

**Challenge.** The design wants logcat to keep `[msg-send] id=$id text=...` while the persisted copy drops the preview (`feature-cross-side-observability.md:237-240`). That is implementable, but not with the Unit 2 comment that `log()` “mirror[s] to debugPrint (logcat)” (`feature-cross-side-observability.md:174`). If `DebugLog.log` mirrors, it will either duplicate every existing debug line or need both a verbose and scrubbed representation.

**Evidence.** Unit 4 separately says each call keeps its existing `debugPrint` and persists a scrubbed jsonl line (`feature-cross-side-observability.md:226-227`). That conflicts with Unit 2’s adapter mirroring comment.

**Recommendation.** Make `DebugLog` persistence-only. Existing `debugPrint` calls remain the logcat path; `_debugLog.log(...)` writes only the scrubbed structured record. If the adapter needs a fallback debugPrint on I/O failure, that fallback must never include user fields.

### C. Is the layering sound?

#### C1. The layer placement is sound; the contract type is not

**Challenge.** `DebugLog` in `domain/contracts/` with a data adapter respects Ports & Adapters, but `Map<String,Object?>` is too weak for this repo’s fail-fast/generated-contract discipline.

**Evidence.** App layer rules allow domain contracts and data implementations (`app/CLAUDE.md`; `app/lib/domain/CLAUDE.md`; `app/lib/data/CLAUDE.md`). Code-design rules discourage ambiguous maps crossing boundaries and ask variant sets to have one registry (`.agents/rules/code-design.md`). The design’s open map is exactly the shape that can drift (`feature-cross-side-observability.md:151`).

**Recommendation.** Define `DebugEvent` / `DebugLogEntry` in domain with typed primitive fields and a canonical tag registry. Keep filesystem/path-provider/share-plus in data/UI only.

#### C2. “Never throws” needs concrete catch boundaries, including async timers

**Challenge.** “Never throws” is achievable only if every public method and timer callback catches `Object`/`StackTrace`, not just `Exception`, and if JSON serialization itself cannot throw on arbitrary field values.

**Evidence.** `getApplicationDocumentsDirectory()` and file I/O can fail; `jsonEncode` can fail on non-encodable `Object?` values; the design says all file I/O is wrapped but leaves serialization and timer callbacks unspecified (`feature-cross-side-observability.md:193-196`).

**Recommendation.** Specify: public `log/export/clear/dispose` catch `Object, StackTrace`; scheduled flush callbacks catch internally; field values are limited to `String/int/bool/null` (or typed wrappers) before encoding; failures emit a scrubbed fallback `debugPrint('[debug-log] ...')` and never rethrow.

#### C3. Dispose is dangling unless the adapter is registered as a disposable service

**Challenge.** Unit 2 mentions `dispose(): final flush` (`feature-cross-side-observability.md:178`) and Unit 3 says register as a singleton (`:209-210`), but the current injector only disposes `addService` / `addRepository`; `addOther` and `addInstance` do not dispose.

**Evidence.** `CustomInjector.addService` wires `BindConfig(onDispose: value.dispose())`, while `addOther` is a lazy singleton without dispose (`app/lib/config/utils/injector.dart:29-38`). `app/lib/config/CLAUDE.md:84-90` documents the same lifecycle. `main.dart` calls `disposeDependencies()` on widget teardown (`app/lib/main.dart:72-75`), so disposal exists if and only if DI uses the disposing registration path.

**Recommendation.** Make `DebugLog` extend/implement the project `Service`/`Disposable` contract or register the concrete adapter with an explicit dispose hook. Add a test or review acceptance that `disposeDependencies()` flushes pending log lines.

### D. Is the harness (Unit 7) appropriately de-risked?

#### D1. The xfail fallback is honest but not an adequate substitute for the harness

**Challenge.** Unit 7’s fallback says “ship an honest xfail + the ring log as the diagnostic substitute” if the SDK `ExtensionRunner` cannot be driven headless (`feature-cross-side-observability.md:268-282`, `:329-332`). That weakens the feature’s second purpose: preventing another mock-only wrong fix.

**Evidence.** The parent epic explicitly says every wrong fix passed mock-based tests because mocks do not model real SDK session replacement (`.work/active/epics/epic-targeting-and-session-lifecycle-contracts.md:20-25`, `:63-70`). The prior review also identified the harness/observability path as the critical evidence gate (`.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`, B3/C2).

**Recommendation.** Keep the spike, but revise the fallback: if `ExtensionRunner` is infeasible, the story must produce an alternate verification plan before session-replacement fixes proceed. Options: process-level harness around a real Pi session, SDK-seam wrapper test that exercises `runtime.assertActive()` behavior, or a documented manual smoke recipe with required ring/extension/relay artifacts attached to the work item. Do not count “ring log + manual reproduction someday” as equivalent to CI harness coverage.

### E. Did the design address prior reviews, or inherit gaps?

#### E1. Top-level dependency is fine; a child story is not actually re-parented

**Challenge.** `feature-cross-side-observability` correctly has `depends_on: []` because the epic makes it the first critical path (`feature-cross-side-observability.md:7`; parent epic dependencies section). `story-app-persistent-ring-log` also has no dependency and is the lead child (`story-app-persistent-ring-log.md:7`). But Unit 6 says `story-add-transport-frame-observability` is already re-parented to this feature, and the file disagrees.

**Evidence.** Unit 6 says the story is folded under this feature (`feature-cross-side-observability.md:260-266`). The story frontmatter still says `parent: epic-remote-session-resilience-refactor` and `depends_on: [feature-adversarial-codebase-review]` (`.work/active/stories/story-add-transport-frame-observability.md:5-7`).

**Recommendation.** Update `story-add-transport-frame-observability.md` frontmatter to this feature (or stop claiming it is re-parented). Revisit the stale `depends_on` edge.

#### E2. The testing plan repeats part of the relay logging test gap

**Challenge.** The app testing plan tests ring mechanics and a couple of sync-service routes, but it does not prove that all capture sites route through the logger. This mirrors the prior relay finding that logging behavior was not tested.

**Evidence.** The feature’s capture-site tests cover `[msg-send]`, `[msg-echo]`, and correlation only (`feature-cross-side-observability.md:306-311`). There is no test for `ws_transport.dart` routing, `msg-failed`, `session-gate`, or `session-sync`, despite the Unit 4 acceptance requiring all 15 sites to route (`feature-cross-side-observability.md:242-247`).

**Recommendation.** Add a fake `DebugLog` and tests at the seam where possible: `WsTransport.demuxPostAuthInboundFrame` decisions produce expected events, `SyncService` send/timeout/gate paths produce expected events, and a simple static/registry test fails if a declared `DebugEvent` variant has no routing test.

#### E3. Untrusted-input risk is lower than the relay panic, but still present

**Challenge.** There is no direct app analogue of the relay UTF-8 slicing panic, but malformed frames can still feed arbitrary strings into the persisted log. Open `Object?` fields can break JSON serialization or create huge/noisy records.

**Evidence.** `ws_transport.dart` converts malformed-frame exceptions to `decision.error` (`app/lib/data/transport/ws_transport.dart:141-145`), and the planned fields include `senderRoom` / `controlType` from decoded frames (`feature-cross-side-observability.md:232`). The proposed adapter accepts arbitrary `Object?` (`:151`).

**Recommendation.** Treat the logger as an untrusted-data boundary: typed primitive fields only, length caps, JSON encoding errors caught, and line skipping/truncation on malformed persisted jsonl during warm load (`feature-cross-side-observability.md:322-326`).

### F. Sizing and scope honesty

#### F1. Units 1-4 are not a clean “single stride” as written

**Challenge.** The story bundles new dependencies, a domain contract, file-backed adapter, DI lifecycle, two data producers, settings ViewModel, settings UI/share sheet, privacy scrubbing, and tests. That is heterogeneous work, and the previous inline attempt already failed compilation.

**Evidence.** The story records that an earlier inline build attempt was reverted because it left dangling `DebugLog`, `DebugLogImpl`, DI, viewmodel methods, and `_DebugSection` references (`story-app-persistent-ring-log.md:17-24`). The feature still calls Units 1-4 a “single stride” (`feature-cross-side-observability.md:286-287`). `app/pubspec.yaml` currently has neither `path_provider` nor `share_plus` in dependencies, while the story references adding both (`story-app-persistent-ring-log.md:112-113`).

**Recommendation.** Split the app work into at least three stories: (1) `DebugLog` typed contract + adapter + lifecycle tests; (2) settings export/clear UI + dependencies; (3) capture-site routing + privacy/correlation tests. If kept as one story, require a single owner and do not call it tiny/single-stride.

#### F2. Export semantics should be file-backed after flush, not just `ring.join` by assumption

**Challenge.** Unit 2 says `export(): flush + return ring joined` (`feature-cross-side-observability.md:175`). That is fine for the current process if `_ensureLoaded()` ran and pending lines are flushed first, but it does not recover lines lost in a hard crash before debounce, and it makes the file less clearly authoritative.

**Evidence.** The design’s own durability model has in-memory-first append and 2s flush delay (`feature-cross-side-observability.md:188-190`). Warm-from-file only loads what reached disk (`:191-192`).

**Recommendation.** Define the file as the export source of truth: `export()` should force a flush, then read and share the file content (or a temp export file). Pair this with the durability change in A2 so the most recent critical events are likely on disk before a crash.

## 4. The single most important question before implementation

**Is the phone ring log meant to diagnose reconnect/session-lifecycle bugs, or only persist today’s existing debugPrint breadcrumbs?** If it is the former, the design must add first-class `ConnectionManager`/session diagnostic events before implementation starts.

## 5. Recommended design revisions

1. **Revise Unit 4 in `.work/active/features/feature-cross-side-observability.md`** from “route the 15 existing `debugPrint`s” to “define and emit typed diagnostic events,” including `ConnectionManager` reconnect/backoff/hydration/room/working events plus the existing send/ws/session-gate breadcrumbs.
2. **Replace `DebugLog.log(String, Map<String,Object?>?)` in the same feature body** with a typed `DebugEvent`/tag registry and explicit allowed fields, field length caps, forbidden key rejection, and privacy tests.
3. **Resolve logcat/persisted semantics**: `DebugLog` should persist scrubbed jsonl only; existing `debugPrint`s remain the verbose logcat path. Remove the Unit 2 “mirror to debugPrint” comment or redesign the API with separate verbose/scrubbed fields.
4. **Strengthen durability semantics** in Unit 2: cap on append, critical-event immediate flush (or write-through), export from flushed file, line-by-line warm load that skips corrupt lines.
5. **Wire lifecycle explicitly** in Unit 3: register via a disposing DI path (`Service`/`Disposable` or explicit `BindConfig`) and add a `disposeDependencies()` flush acceptance test.
6. **Fix child/story metadata**: update `story-add-transport-frame-observability.md` parent/depends_on if it is really part of this feature; correct Unit 4’s mislabeled `msg-failed` and `session-gate` rows.
7. **Split `story-app-persistent-ring-log.md`** into adapter/lifecycle, settings export, and capture routing/privacy stories, or at least mark it as a larger coordinated app slice rather than “single stride.”
8. **Revise Unit 7 fallback**: an infeasible `ExtensionRunner` spike must produce an alternate verification path for session-replacement fixes, not merely an xfail plus production ring logs.
