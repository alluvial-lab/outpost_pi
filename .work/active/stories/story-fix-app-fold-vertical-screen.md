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
