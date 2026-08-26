---
id: story-fix-app-fold-vertical-screen
kind: story
stage: done
tags: [app, bug, ux]
parent: null
depends_on: []
release_binding: v0.8.1
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Restore full app height after a folded-device keyboard cycle

## Symptom

On a Pixel Fold at folded/phone width, the app can retain unused vertical space after a keyboard cycle, as though the window never expanded after the IME closed.

## Root cause

When the production shell changes from the 842x701 two-pane posture to 411x797 single-pane while the detail composer owns the IME, Flutter moves primary focus to the remaining route scope but emits no `TextInput.hide` command. The shell assumed focus movement alone would close the IME. Pixel Fold WindowManager can retain the old IME inset across that posture resize, so the now-visible phone pane stays shortened. The compact-composer hysteresis, ordinary phone chat `MediaQuery`, master-pane isolation, and modal inset restoration all follow complete simulated close ramps correctly; the missing convergence action is at the two-pane-to-single-pane router transition.

## Fix approach

Wrap the adaptive navigator composition in a stateful transition boundary. When an active IME inset exists and the shell changes from two panes to one, explicitly unfocus and send `TextInput.hide` after the collapse frame so Android begins the close animation and publishes the ramp back to zero. Keep master Home isolation, modal inset restoration, and compact-composer thresholds unchanged.

## Regression test

- `app/test/ui/chat/chat_compact_composer_test.dart`: simulate the complete 411x797 folded keyboard open/close ramp and assert the chat receives zero, returns to its full 411x797 extent, restores the composer bottom, and has no residual compact state.
- `app/test/routing/app_router_test.dart`: focus the production 842x701 detail composer, collapse to 411x797, require the missing platform hide command, animate the close to zero, and assert full Home height; then open the master dialog after the route/posture changes and verify its full inset-close ramp while Home stays height-stable.

## Implementation

**Execution capability:** `openai-codex/gpt-5.6-sol` at high reasoning. The fix is small, but it crosses Flutter focus, router composition, platform text-input signaling, and fold posture metrics, so the stronger implementation capability was appropriate.

**Files changed:**

- `app/lib/routing/adaptive.dart` adds the lifecycle-owned split-collapse IME convergence boundary.
- `app/lib/routing/app_router.dart` keeps that boundary mounted across both adaptive shell shapes.
- `app/test/ui/chat/chat_compact_composer_test.dart` covers the complete folded phone inset cycle and final viewport.
- `app/test/routing/app_router_test.dart` covers the two-pane-to-phone transition, platform hide request, close ramp, route-mid-open modal ramp, and master isolation.
- `.work/backlog/backlog-app-fold-not-using-full-vertical-screen.md` retains its promotion pointer.

**Fails-before evidence:** the production router seam test failed with `Expected: contains 'TextInput.hide'; Actual: []` after resizing the focused 842x701 detail pane to 411x797. The ordinary 411x797 chat inset ramp and the master-modal close ramp already converged to zero, eliminating the compact hysteresis and master `MediaQuery` restoration as holders of the stale value.

**Confirmation:**

1. Targeted chat + production-router regression tests pass.
2. `flutter analyze` reports no issues.
3. `flutter test --exclude-tags e2e --concurrency=2` passes all 957 tests.
4. `flutter test test/golden/` regenerates the complete fold render-evidence matrix and passes both golden tests.

No emulator was used: the failure boundary and the missing platform method call reproduce deterministically in the production router widget test. No adjacent issues were found or parked.

## Bounded inline review

**Verdict: pass.** The patch acts only on the split-to-single transition while an IME inset is active, keeps the wrapper state alive across both router shapes, defers focus/platform effects until after the collapse frame, and guards a queued callback against disposal or an immediate re-expansion. It does not alter compact thresholds, master-pane isolation, modal inset restoration, routing state, or wire/domain boundaries. Regression coverage exercises the reported folded cycle plus the two named alternate paths; analyze, full tests, and fold goldens are green. No material blocker or follow-up finding remains.

## RC.2 regression correction: preserve system-bar insets

Operator UAT of v0.8.1-rc.1 found that the folded app drew under Android's three-button navigation bar after the pane-collapse IME dismissal. The rc.1 boundary had two gaps: its delayed `FocusManager.instance.primaryFocus?.unfocus()` targeted whichever focus survived after the detail pane was replaced rather than the departed detail editor, and the folded child inherited Android's transient keyboard-visible `MediaQuery.padding` (zero at the system edges) even when stable `viewPadding` still described the status and navigation bars. There was no `SystemChrome` immersive-mode call and no explicit `viewPadding` removal; the over-broad global unfocus plus forwarding transient zero padding was the over-correction.

The rc.2 correction removes the global unfocus. The boundary now issues only `TextInput.hide`, retains every IME inset update, and, only after an IME-active split-to-single transition, derives safe `padding` from the current `viewPadding - viewInsets` without reducing any platform-provided padding. The correction resets when the shell returns to two panes.

**Fails-before regression evidence:** with a simulated 24dp status-bar inset and 48dp three-button navigation-bar inset surviving in `viewPadding`, the production router collapse test failed before the correction at `Expected: <24>; Actual: <0.0>` because the folded Home `SafeArea` received transient zero system padding. The completed assertion also requires the Home scroll surface to stop at y=749 rather than extend to the 797dp window bottom. After the correction, both status and navigation-bar bounds pass while the same test still observes `TextInput.hide` and the full 200 → 80 → 0 IME close ramp.

**Verification:**

- Focused regression/original paths: `app/test/routing/app_router_test.dart` and `app/test/ui/chat/chat_compact_composer_test.dart` pass (16 tests), covering folded keyboard cycle, navigation/modal mid-cycle, and two-pane collapse.
- `flutter analyze` passes with no issues.
- `flutter test --exclude-tags e2e --concurrency=2` passes all 957 tests. An initial run hit the already-parked `idea-app-sync-service-suite-flakes` load-sensitive assertion; the exact test passed immediately in isolation and the required full rerun was green.
- `flutter test test/golden/ --concurrency=2` passes the complete fold render-evidence matrix (2 tests).

**RC.2 bounded inline review:** pass. The change is confined to the existing router transition owner, preserves the rc.1 ghost-IME signal and inset ramp, does not touch Android window/system-UI configuration, and adds a fails-before safe-area assertion at the production router seam. No new adjacent issue was found; the one suite flake is already parked as `idea-app-sync-service-suite-flakes`.

## RC.3 regression correction: pass through platform padding

Operator UAT of v0.8.1-rc.2 showed Android's opaque three-button navigation bar permanently over the lower chat controls: the attachment/settings row, composer, and microphone continued beneath the black system surface instead of stopping above it. The visible back arrow identifies the screenshot as the root `/chat` route, not the tablet detail branch.

The Android host is a plain `FlutterActivity`; `AndroidManifest.xml` requests `adjustResize`, the launch/normal themes do not opt out of edge-to-edge, and app code makes no `SystemChrome` mode call. Flutter 3.44 targets API 36, where edge-to-edge is mandatory: system bars overlay the Flutter window and routed surfaces must consume the system insets themselves.

RC.2 gave pane collapse two unrelated responsibilities. It correctly sent `TextInput.hide`, but then kept an intermediate `MediaQuery` installed and re-derived `padding` from `viewPadding - viewInsets`. That made the transition boundary a second inset authority, while the screenshot's root chat route was outside that shell override. During IME metrics convergence, `Scaffold` removes the animated bottom inset from its body; a default `SafeArea` can therefore observe transient bottom `padding == 0` even while stable bottom `viewPadding == 48` still describes the overlaid navigation bar.

RC.3 restores one owner per inset. `PaneCollapseImeDismissal` now issues only `TextInput.hide` and returns its child unchanged, so folded Home receives the platform padding directly. The root Chat `SafeArea` uses `maintainBottomViewPadding`, so Flutter's own stable system-bar value remains reserved while `Scaffold` owns IME resizing. No hand-built `MediaQuery` padding remains, and the original 200 → 80 → 0 IME close ramp still reaches zero.

**Fails-before regression evidence:** the combined production-router regression failed against rc.2 at `Expected: no matching candidates; Actual: Found 1 widget with pane-collapse MediaQuery padding override`. The completed family also simulates a 24dp status bar and 48dp three-button navigation bar, exercises the split-detail collapse plus a complete folded root-chat keyboard cycle, requires both Home and the chat composer to stop at y=749 in the 797dp viewport, verifies the transient padding-zero/stable-viewPadding case, and still requires `TextInput.hide` plus a final zero IME inset.

**Verification:**

- Focused router and compact-composer files pass (16 tests).
- `flutter analyze` passes with no issues.
- `flutter test --exclude-tags e2e --concurrency=2` passes all 957 tests. One final-state run hit the already-parked `idea-app-sync-service-suite-flakes` multi-block assertion (`Expected: 2; Actual: 0`); the exact test passed immediately in isolation and the required full rerun was green.
- `flutter test test/golden/ --concurrency=2` passes the complete fold render-evidence matrix (2 tests); no golden changed.

**Execution capability:** `openai-codex/gpt-5.6-sol` at high reasoning, selected because the regression crosses Android 15+ forced edge-to-edge behavior, Flutter engine inset semantics, Scaffold/SafeArea ownership, routed shell topology, and fold/IME lifecycle convergence.

**RC.3 bounded inline review:** pass. The patch deletes the rc.2 inset authority instead of adding another formula, keeps the rc.1 platform dismissal at the narrow split-collapse boundary, passes system padding directly to folded Home, and lets the root Chat `SafeArea` retain stable navigation padding through IME metric convergence. The regression test covers the screenshot route and all three ping-pong failures in one production family. No version field, Android host configuration, compact threshold, modal restoration path, or generated golden was changed. No adjacent issue was found or parked.
