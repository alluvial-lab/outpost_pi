---
id: feature-cockpit-async-action-ownership
kind: feature
stage: review
tags: [cockpit, refactor, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-18
---

# Cockpit: shared async UI-action and teardown ownership

## Brief

Eight gate findings across `cockpit/` describe Cockpit UI actions and lifecycle
hooks that invoke `Future`-returning work from sync button callbacks or
`initState` without `await`/`unawaited(...)`/error handling. The shared defect
is the same as the app-side lifecycle ownership gap, but in the desktop UI: a
discarded async future silently swallows failures, and one of them
(`gate-refactor-lifecycle-unguarded-async-workspace-projection`) calls
`PaneItem.dispose()` synchronously while `AgentSession.dispose()` is async —
teardown races that can leak process/subscription resources. This feature
defines the shared ownership pattern for Cockpit async UI actions and applies it
to:

- `gate-cruft-empty-catch-formatter-reload` — empty catch-swallow in formatter reload path
- `gate-refactor-lifecycle-unguarded-async-agent-composer` — agent composer drops session operation futures
- `gate-refactor-lifecycle-unguarded-async-connectivity-save` — relay save action discards its async save future
- `gate-refactor-lifecycle-unguarded-async-cron-log` — cron log initial load future discarded
- `gate-refactor-lifecycle-unguarded-async-daemon-actions` — daemon action buttons discard `Future`-returning callbacks
- `gate-refactor-lifecycle-unguarded-async-language-settings` — LSP probe future fired without explicit handling
- `gate-refactor-lifecycle-unguarded-async-schedule-actions` — schedule action buttons discard `Future`-returning callbacks
- `gate-refactor-lifecycle-unguarded-async-workspace-projection` — async tab disposal discarded by workspace teardown

## Simplification opportunity

Establish one owned-async pattern for the Cockpit UI layer (mirror the
`.catchError` / `unawaited` discipline the app feature defines) and ensure
async `dispose()` chains await before the owning widget tears down. No
public-surface behavior change.

## Source

Promoted from backlog by `scope` (2026-07-15). 8 `gate-refactor-lifecycle-*` /
`gate-cruft-*` findings from the v0.6.0 release gate passes.

## Refactor Overview

Refactor-design pass (2026-07-16). All 8 findings current (several line
numbers drifted — updated below). Five lenses produced 4 actionable steps.
Key decision: do NOT introduce an async executor/queue/loading-state
framework — a small `ownAsync`/`ownedAsyncAction` boundary adapter + existing
ViewModel error states suffice. The adapter forwards uncaught failures to
the originating zone (preserving current uncaught-error behavior) rather
than swallowing or newly presenting them.

## Behavior-changing finding to retag

### `gate-cruft-empty-catch-formatter-reload`
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:369-379` intentionally
catches+suppresses every `_reloadFromDisk` exception. Logging/reporting/displaying
this failure changes the silent-fallback contract. Detach this story from the
`[refactor]` feature and retag `[cockpit, bug]` for feature/bug design — that
follow-up decides deliberately between debug telemetry, an inline formatter
error, or retaining silence.

The other 7 stories remain pure-refactor ONLY if implementation preserves
their existing error behavior. Do not add new banners, logs, retries, or
fallback states for unexpected exceptions.

## Refactor Steps

### Step 1: Establish the Cockpit owned-async boundary
**Priority:** High | **Risk:** Low | **Source Lens:** missing abstraction / pattern drift
**Files:** new `cockpit/lib/app/core/ui/async_action.dart`, new `cockpit/test/ui/async_action_test.dart`
**Stories covered:** shared prerequisite for the 6 UI-action stories + workspace teardown

**Current State:** Cockpit uses direct `unawaited(...)` (e.g. `file_viewer.dart:128,152,188,225,378`, `cockpit_page.dart:79,295,308,368`) or coerces `Future<void> Function()` into `VoidCallback` (`onPressed: onTap == null ? null : () => onTap!()`). No common rule for retaining the uncaught-error path.

**Target State:**
```dart
void ownAsync(Future<void> future) {
  final zone = Zone.current;
  unawaited(future.catchError((Object error, StackTrace stackTrace) {
    zone.handleUncaughtError(error, stackTrace);
  }));
}

VoidCallback ownedAsyncAction(Future<void> Function() action) {
  return () => ownAsync(action());
}
```

**Implementation Notes:**
- Place in `core/ui` (both `cockpit` and `settings` use it; don't cross-import features).
- Capture caller's zone before installing the failure continuation; forward failures exactly once.
- NO `debugPrint`, `FlutterError.reportError`, banners, snackbars, or empty `catchError`.
- Preserve synchronous exceptions: invoke `action()` normally, attach ownership to the returned future.
- No generic variants until a real second parameter shape warrants one.

**Acceptance Criteria:**
- [ ] `ownAsync` forwards a failed future to a `runZonedGuarded` handler exactly once.
- [ ] `ownedAsyncAction` invokes its action exactly once per callback.
- [ ] Successful futures produce no extra notification/output.
- [ ] Neither helper swallows failures or introduces user-visible error behavior.
- [ ] `flutter analyze` passes.

**Rollback:** Remove helper + test; later steps revert to direct `unawaited(...)`.

### Step 2: Consolidate settings actions and lifecycle launches
**Priority:** High | **Risk:** Low | **Source Lens:** missing abstraction / pattern drift
**Files:** `connectivity_settings_panel.dart`, `daemon_settings_panel.dart`, `language_settings_panel.dart`, `schedule_settings_panel.dart`, `cron_log_dialog.dart`, `settings_components.dart` + tests
**Stories covered:** `gate-refactor-lifecycle-unguarded-async-connectivity-save`, `-cron-log`, `-daemon-actions`, `-language-settings`, `-schedule-actions`

**Current State:** Settings repeat the implicit future discard in lifecycle hooks + callback adapters (e.g. `connectivity:288-301 onSubmitted/onPressed`, `cron_log:34-41 initState->_load()`, `daemon:299,354,486 onPressed`, `language:113,155,165 _detect()`, `schedule:220-223,330 onToggle/onRun/onLog/onRemove`). ViewModels already convert expected domain failures into existing state (`ConnectivityViewModel.setRelay`→`relayError`, `DaemonsViewModel`→`actionError`, `CronViewModel`→`actionError`).

**Target State:** Use the shared boundary at every sync→async crossing: `onPressed: ownedAsyncAction(_save)`, `initState: ownAsync(_load())`, etc.

**Implementation Notes:**
- Keep expected failures in current ViewModel fields; helper handles only ownership + forwarding of genuinely uncaught failures.
- NO `try/catch` on `_save`/`_load`/`_detect`/daemon/schedule actions.
- Preserve mounted guards + positions.
- Don't await initial loads/polling from `initState`/`Timer` (intentionally detached).
- Don't fix out-of-order LSP probe completion here (cancellation = behavior change → separate bug).
- Extend assertions only where needed to prove one invocation per tap.

**Acceptance Criteria:**
- [ ] Every cited settings future is awaited inside its async method or passed through `ownAsync`/`ownedAsyncAction` at the sync boundary.
- [ ] Relay save still clears `_edited` only after successful `setRelay`.
- [ ] Daemon/schedule ops still use existing busy + `actionError` states.
- [ ] Cron log still displays current `null`/`actionError` fallback + retains mounted guard.
- [ ] LSP detection still sets `_available` to `null` immediately + publishes only while mounted.
- [ ] No new banner/log/retry/error copy/exception suppression.
- [ ] Targeted settings tests + `flutter analyze` pass.

**Rollback:** Revert call sites to original closures; helper can remain.

### Step 3: Make Agent Composer action ownership explicit
**Priority:** High | **Risk:** Medium | **Source Lens:** code smell / pattern drift
**Files:** `cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart`, `cockpit/test/ui/agent_session_turn_projection_test.dart`
**Story covered:** `gate-refactor-lifecycle-unguarded-async-agent-composer`

**Current State:** finding valid at `agent_composer.dart:324-331` (`/new`/`/compact` call `startNewSession()`/`compact()` unowned), `:501` (`session.send(message, images)`), `:567` (`_onOsDrop(detail.files)`), `:892,923` (`changeModel`/`changeThinking`), `:1241-1245` (`sendRelayControl`). File passes `_pickAttachment`/`_pasteFromClipboard`/`_submit` through `VoidCallback`-typed fields (`839,1136,1164`). Expected RPC failures already projected by `AgentSession` (`send:277-325`, `startNewSession:327-354`, `compact:356-366`, `changeModel:369-385`, `changeThinking:388-405`).

**Target State:** `ownAsync(widget.session.startNewSession())`, `ownAsync(session.send(message, images: images))`, `ownedAsyncAction(_submit)`, `ownedAsyncAction(() async { ... await session.changeModel(picked) })`, etc. Apply adapter at `_pickAttachment`/`_pasteFromClipboard`/`_submit` `VoidCallback` boundaries.

**Implementation Notes:**
- Preserve `_submit` ordering: clear composer before image normalization + RPC completion.
- Don't make `_runBuiltin` async (awaiting session creation/compaction before resetting input changes visible timing).
- Keep model/thinking dialogs awaited internally; own the whole dialog-to-RPC future at the `_Chip` boundary.
- Keep mounted checks; no context use after new awaits.
- No new transcript messages/error banners; `AgentSession` remains the expected-RPC-failure projection source.

**Acceptance Criteria:**
- [ ] Every cited composer operation has explicit ownership.
- [ ] Sending still clears text + attachments immediately.
- [ ] `/new` + `/compact` still reset input immediately + invoke exactly one session operation.
- [ ] Native drop still restores focus without waiting for file reads.
- [ ] Model/thinking selections invoke their session operation exactly once.
- [ ] Relay toggle disabled for non-live session.
- [ ] Existing `AgentSession` success/failure tests green; `flutter test test/ui/agent_session_turn_projection_test.dart` + `flutter analyze` pass.

**Rollback:** Revert only `agent_composer.dart`; no session/RPC contract changes.

### Step 4: Separate synchronous notifier disposal from awaited pane shutdown
**Priority:** High | **Risk:** Medium | **Source Lens:** code smell / lifecycle ownership
**Files:** `pane_item.dart`, `agent_session.dart`, `terminal_session.dart`, `workspace_projection.dart`, `cockpit_viewmodel.dart` + tests
**Story covered:** `gate-refactor-lifecycle-unguarded-async-workspace-projection`

**Current State:** `PaneItem extends ChangeNotifier` (sync `dispose()`). `AgentSession.dispose()` (`:478-485`) + `TerminalSession.dispose()` (`:108-113`) override it async (`await _process.dispose()` / `await _sub?.cancel()` + `await _gateway.kill()`). `WorkspaceProjection.disposeTab()` (`:296-300`) + `dispose()` (`:392-404`) call `item.dispose()` through the sync contract — teardown races, resources leak.

**Target State:** Give live pane resources an explicit async `close()` contract separate from `ChangeNotifier.dispose()`:
```dart
abstract class PaneItem extends ChangeNotifier {
  Future<void> close() async { super.dispose(); }
}
// AgentSession.close(): await _process.dispose(); await _signalSub?.cancel(); await super.close();
// TerminalSession.close(): await _sub?.cancel(); await _gateway.kill(); await super.close();
// WorkspaceProjection.disposeTab(String id) -> Future<void>: remove item, await watcher?.cancel(), await item?.close()
// dispose() -> Future<void>: Future.wait(ids.map(disposeTab))
```
At sync-required callers: `ownAsync(_workspace.disposeTab(id))`. At already-async boundaries (`CockpitViewModel.removeProject`): await `_workspace.disposeProject(...)`.

**Implementation Notes:**
- Don't widen `core/domain/contracts/disposable.dart` (sync interface for injector-owned services, wrong contract for UI panes).
- Remove the async `dispose()` overrides; tests/projection call `close()` for `AgentSession`/`TerminalSession`.
- Remove pane items + cancel debounce timers before the first await so UI can't rediscover a closing tab.
- Await watcher cancellation before closing the pane resource.
- Whole-project/projection teardown may close independent tabs concurrently with `Future.wait`.
- Preserve synchronous document mutation + immediate tab disappearance (future = resource shutdown completion, not delayed UI removal).
- `CockpitViewModel.dispose()`: `ownAsync(_workspace.dispose())` (Flutter notifier lifecycle can't await; intentional error-forwarding boundary).
- Where `removeProject`/worktree reconciliation are already async, propagate + await.
- Don't replace graceful process shutdown with sync force-kill to satisfy Flutter's `dispose()` signature.

**Acceptance Criteria:**
- [ ] No `PaneItem` subclass overrides `ChangeNotifier.dispose()` with `Future<void>`.
- [ ] `WorkspaceProjection.disposeTab()` removes item immediately but doesn't complete until watcher + pane shutdown complete.
- [ ] Regression test with delayed fake gateway proves `disposeTab()` waits for agent process teardown.
- [ ] `disposeProject()` + full projection disposal await every selected tab.
- [ ] Agent shutdown still converges an active turn to non-working/stale + kills/disposes RPC gateway.
- [ ] Terminal shutdown still cancels output before killing PTY.
- [ ] Existing close-tab/close-pane tests retain immediate document + selection behavior.
- [ ] All remaining sync teardown callers use `ownAsync`, not bare discarded futures.
- [ ] Targeted tests + full `flutter test` + `flutter analyze` pass.

**Rollback:** Revert the `close()` contract, restore subclass `dispose()` methods + sync projection methods. Code-only (no persistence/wire change).

## Implementation Order

1. **Step 1** — owned-async boundary + zone-forwarding regression test.
2. **Step 2** — settings callbacks, lifecycle launches, shared settings controls.
3. **Step 3** — Agent Composer callback ownership.
4. **Step 4** — explicit pane `close()` contract + awaited workspace teardown.
5. Verify from `cockpit/`: `flutter analyze`, `flutter test`, `flutter build macos` (when toolchain available).
6. Retag + detach `gate-cruft-empty-catch-formatter-reload` (behavior-changing); do NOT implement its error-reporting recommendation in this `[refactor]` feature.

## Implementation

Established `ownAsync` / `ownedAsyncAction` in `core/ui` as the single sync-to-async UI boundary. Failed detached futures are forwarded exactly once to the caller's originating zone, successful futures are inert, and synchronous action exceptions remain synchronous. Settings lifecycle launches/actions and Agent Composer callbacks now use that boundary without adding error UI, logging, retries, or fallback behavior.

Separated Flutter's synchronous notifier disposal from asynchronous pane-resource shutdown with `PaneItem.close()`. Agent and terminal sessions await their process/subscription teardown before disposing notifier state. Workspace tab removal and debounce cancellation remain synchronous and immediate, while watcher cancellation and pane closure are awaited; project and full-projection teardown fan in across every selected tab. Already-async Cockpit boundaries await shutdown, and synchronous notifier/widget boundaries use `ownAsync`.

`gate-cruft-empty-catch-formatter-reload` was already detached and retagged `[cockpit, bug]` by the design commit; its behavior-changing error-reporting recommendation was not implemented.

## Verification

- `flutter analyze` — passed with zero issues.
- `flutter test` — passed, 249 tests.
- Targeted async-action, settings, agent-session, workspace-projection, and Cockpit workspace command/document suites — passed.
- `flutter build macos` — unavailable on this Linux host (`flutter build` has no `macos` subcommand); no macOS toolchain smoke was possible.
