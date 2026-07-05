# Review: feature-cross-side-observability design v2

## 1. Verdict

**PROCEED WITH FIXES.** The revision addresses the prior central design failure in substance: the app log is now debug-gated and app-global, but when enabled it is no longer just a persistence wrapper around the existing 15 `debugPrint`s; it adds first-class `ConnectionManager` and replay events for the reconnect/session surfaces the named bugs need. The remaining issues are fix-forward design/stories edits, not a full conceptual rework: Unit 4 must explicitly cover duplicate-connection/stale-channel takeover evidence, several line ranges need correction, the immediate-flush set is missing some critical tags it claims to protect, and the DI/dispose story is not type-correct as sketched against the current injector.

## 2. Prior-finding closure

| Prior finding | Closure | Evidence |
|---|---:|---|
| A1 — 15 existing sites miss `ConnectionManager` reconnect/working transitions | **PARTIALLY ADDRESSED** | Revised Unit 4b adds `conn-status`, `conn-channel-lost`, `conn-hydrate`, `room-snapshot`, `working-conv`, and `replay-dedup`. These map to real code, but duplicate-connection takeover is named in Design decisions and not explicit in the table; `StatusOffline` is named conceptually but is not currently emitted. |
| A2 — crash-resilient flush | **PARTIALLY ADDRESSED** | Unit 2 adds immediate flush for `msgSend`, `msgFailed`, `sessionGate`, `connStatus`, `roomSnapshot`, lifecycle pause/detach. Missing likely-critical `connChannelLost`, `connHydrate`, `workingConv`, and `sessionSync`; lifecycle tags are not otherwise defined/emitted in Units 1/4. |
| A3 — cap on append + field caps | **ADDRESSED** | Unit 2 and story adapter require cap-on-append and per-field caps before `jsonEncode`, with oversized/encoding-failure handling. The cap value is given as “e.g. 256”; acceptable, but implementation should lock the exact constant. |
| B1 — mislabeled 15-site tags | **ADDRESSED** | Revised tables correctly identify `sync_service.dart:341` as `msg-failed`, `:425` as `session-sync`, `:538` as `session-gate`; `ws_transport.dart` has the 8 `ws-in` sites. |
| B2 — call-site privacy too weak | **PARTIALLY ADDRESSED** | `DebugEvent` sealed variants are a much better scrub boundary than `Map<String,Object?>`, but the design still lacks a canonical serializer/allowed-key test that fails if a future variant adds `body`, `image`, `args`, `result`, etc. |
| B3 — logcat/persisted split inconsistent | **ADDRESSED** | Stale “mirror to debugPrint” wording is gone. Unit 4 says existing `debugPrint`s stay as logcat and `DebugLog` is persistence-only. |
| C1 — contract type too weak | **PARTIALLY ADDRESSED** | Typed `DebugEvent`/`DebugTag` registry addresses the open-map concern, but the sketched `class DebugLog` does not extend the app’s `Service` contract while the DI plan requires `addService<T extends Service>`. |
| C2 — “never throws” catch boundaries | **ADDRESSED** | Unit 2 specifies public methods and timer callbacks catch `Object, StackTrace`, JSON encode failures are caught/dropped, and fallback debugPrint is scrubbed. |
| C3 — dispose wiring | **PARTIALLY ADDRESSED** | Verified `CustomInjector.addService` disposes via `BindConfig(onDispose: value.dispose())`, and tests are added. But `addService<DebugLog>` will not compile unless `DebugLog` extends `Service` or injector gains an interface-to-disposable binding. |
| D1 — harness fallback hand-wavy | **ADDRESSED** | Unit 7 now requires a pre-mortem spike and an alternate verification plan before session-replacement fixes proceed; it no longer treats “xfail + ring log” as equivalent. |
| E1 — transport-frame story re-parent | **ADDRESSED** | `story-add-transport-frame-observability.md` now has `parent: feature-cross-side-observability` and depends on `story-app-debug-log-adapter`. |
| E2 — routing tests | **ADDRESSED** | Testing section and capture-routing story require fake-`DebugLog` tests for reconnect, send, gate, failure/sync, plus a registry/routing coverage test. |
| E3 — untrusted-input boundary | **ADDRESSED** | Typed variants + primitive/oversized field handling + warm-load corrupt-line skipping are now explicit. Residual semantic leakage risk remains under B2. |
| F1 — story split | **ADDRESSED** | Split into three app stories with sensible dependencies: adapter foundation, toggle UI depends on adapter, capture routing depends on adapter only. |
| F2 — export from file | **ADDRESSED** | Design and Unit 2 now say `export()` force-flushes then reads the file as source of truth. |

## 3. New challenges from the debug-gated reframe

- **Toggle state vs ring-file source of truth is mostly coherent, but should be explicit.** The design says `Preferences.debugLogging` gates future `log()` calls and `clear()` wipes ring + file. That implies toggling OFF must not wipe existing captured logs, and export should still read whatever is on disk. The UI story does not contradict this, but add an acceptance criterion so an implementer does not accidentally gate export/clear behind the switch.
- **Export while OFF should work.** This is consistent with “Export reads from the file” and the operator flow “reproduce, export, send.” The story should state: Export is available when debug logging is OFF if the file is non-empty; OFF only disables new capture.
- **Forgetting to enable the toggle is an accepted trade-off, not solved.** The reframe is no longer always-on telemetry. If the operator forgets to enable Debug logging before an intermittent bug, this design may miss it. That is acceptable for the stated “flip on, reproduce, export” operator-owned use case, but the Settings UI should say “captures only while enabled” to avoid false confidence.
- **Privacy posture is reasonable for operator-owned dumps but not self-enforcing enough yet.** Allowing truncated message previews is sound for internal debugging if the operator chooses the destination. It is still easy to overshare when sending a jsonl file to a collaborator. Add a UI warning (“May include truncated message previews and diagnostic IDs”) and a registry serialization test that forbids payload-like keys.

## 4. Line-number / capture-surface verification

### `connection_manager.dart`

- `conn-status` connect range is **mostly valid**: `_connect` is the right site; `StatusConnecting` is emitted at `connection_manager.dart:534`, `StatusOnline` at `:547`, and `_replaySubscriptions()` at `:551`. The claimed `:520-553` range covers it.
- Retry range is **valid**: `_scheduleRetry` emits `StatusRetrying` at `connection_manager.dart:1183`; claimed `:1177-1184` is close enough.
- `_onChannelLost` exists at `connection_manager.dart:1162-1173`, but the story table gives only the function name. This is the exact place where the duplicate-connection old-channel `onDone` is ignored (`:1166-1170`). Add an explicit event/field such as `staleChannelIgnored: true` or `reason: stale_replaced_channel` so the half-open/duplicate-auth bug is diagnosable.
- `conn-hydrate` sites are **valid**: `requestResumeHydration()` replays at `connection_manager.dart:330-337`, and `_replaySubscriptions()` is at `:1136-1143`.
- `_onControl` starts at `connection_manager.dart:566`, but the claimed `:566-706` is **incomplete** for room snapshots. `RoomMetaUpdated` continues past `:706`, and `RoomsSnapshot` handling runs roughly `:746-813`. If `room-snapshot` means authoritative `RoomsSnapshot`, the table must cite the later range too.
- `markRoomWorking` starts at `connection_manager.dart:914`, but the claimed `:914-929` only reaches the guards. The actual mutation/persist/schedule path continues through about `:938`.
- `_markActiveRoomOffline` is **misleadingly ranged**. The missed-ping trigger is in `_startPing` around `connection_manager.dart:1194-1221`; `_markActiveRoomOffline()` itself starts at `:1238` and runs to about `:1252`. Split those citations.
- The design mentions `connecting → online → retrying → offline`, but current code defines `StatusOffline` and does not appear to emit it. If “offline” means active-room offline via `_markActiveRoomOffline`, call it that; if it means connection status, add or remove that claim.

### Existing 15 `debugPrint` sites

- `ws_transport.dart` has exactly the 8 claimed `ws-in` sites: `:82`, `:103`, `:106`, `:113`, `:117`, `:127`, `:133`, `:142`.
- `sync_service.dart` corrected tags are verified: `msg-send` at `:212`, `:245`, `:260`; `msg-failed` at `:341`; `session-sync` at `:425`; `session-gate` at `:538`; `msg-echo` at `:610`.

## 5. Remaining material challenges

1. **DI/dispose type mismatch will block implementation if copied literally.** Current `CustomInjector.addService<T extends Service>()` disposes, but Unit 1 sketches `class DebugLog` without extending `Service`. Registering the port through `addService<DebugLog>` will fail the type bound. Fix by making the domain port `abstract interface class DebugLog extends Service`, or by adding an injector method that binds an interface to a disposable implementation.
2. **Immediate-flush set does not match the expanded capture surface.** `conn-channel-lost` and `working-conv` are exactly the sort of tail events a crash/reconnect bug needs. Either include them in `_immediateFlushTags` or explain why they are routine. Also define lifecycle pause/detach events if they remain in the set.
3. **Duplicate-connection takeover is promised but not made observable.** The backlog item `idea-mobile-drop-half-open-tcp` asks whether duplicate auth immediately supersedes the old connection. Relay file logging may answer the relay half, but the app log should still show fresh connect/auth and stale old-channel close ignored vs real channel loss.
4. **Typed scrub is not yet test-shaped.** The design says no variant carries full body/image/tool args/results, but should specify a `toJson()`/allowed-fields registry test that rejects forbidden keys and clamps all strings. Without that, the guarantee relies on reviewer memory.
5. **Units 1+2 are acceptable as one story but near the upper edge.** Domain registry plus file adapter plus lifecycle tests is a coherent foundation slice, but it is not tiny. If implementation stalls, split Unit 1 (pure domain/serialization registry) from Unit 2 (file adapter/lifecycle).

## 6. The single most important question before implementation

**Where will duplicate-connection takeover be proven: in the app ring log, the relay file log, or both — and what exact event distinguishes “old replaced channel closed and was safely ignored” from “current channel was lost and retry started”?**

## 7. Recommended fixes

1. **Update `.work/active/stories/story-app-capture-routing.md` and the parent Unit 4 table** to add an explicit duplicate/stale-channel event at `app/lib/data/transport/connection_manager.dart:1166-1170`, correct the `_onControl`, `markRoomWorking`, and `_markActiveRoomOffline` ranges, and clarify the nonexistent `StatusOffline` emission.
2. **Update Unit 2 in `.work/active/features/feature-cross-side-observability.md` and `story-app-debug-log-adapter.md`** so `_immediateFlushTags` includes `connChannelLost`, `workingConv`, and any truly critical hydrate/session-sync events; define or remove lifecycle pause/detach tags.
3. **Fix the DI contract in the design/stories**: make `DebugLog` extend `Service` or add a disposing interface binding in `app/lib/config/utils/injector.dart`; keep the lifecycle test that proves `disposeDependencies()` flushes.
4. **Specify the typed-event serializer contract** in `app/lib/domain/contracts/debug_log.dart`: each variant serializes through one canonical method; tests assert no forbidden keys and all string fields are capped.
5. **Add toggle/export semantics to `story-app-debug-toggle-ui.md` acceptance**: toggling OFF preserves existing ring/file; export and clear operate while OFF; clear wipes logs but not `Preferences.debugLogging`; UI warns that exports may include truncated previews.
