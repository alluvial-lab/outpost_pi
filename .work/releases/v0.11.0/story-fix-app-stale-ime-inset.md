---
id: story-fix-app-stale-ime-inset
kind: story
stage: done
tags: [app, bug, ux]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Recover single-pane layout from a stale Android IME inset

## Symptom

During v0.9.0-rc.2 soak on a Pixel Fold cover display in ordinary single-pane phone use, the app intermittently rendered in the top half of the screen with dead space below. The keyboard was not visible; opening and closing it forced a fresh Android inset notification and restored the full layout.

## Root cause

`PaneCollapseImeDismissal` reasserts `TextInput.hide` only when the adaptive shell changes from two panes to one. A phone that stays single-pane has no convergence action when Android retains a stale nonzero IME `viewInsets.bottom` after the text-input connection closes, so every routed surface continues honoring the obsolete inset indefinitely.

## Fix approach

Generalize the existing shell-owned IME boundary to observe text-input focus and window metrics in both shell modes. Reassert `TextInput.hide` after a focused editable disconnects while an inset remains, and arm a lifecycle-owned watchdog whenever a keyboard-sized bottom inset persists.

Flutter 3.44.4 exposes no global `TextInput.isConnected` or IME-visibility API: `TextInputConnection.attached` exists only on a connection instance, and `EditableText` keeps its connection private. Android's `flutter/textinput` channel likewise has commands but no query. The Android host now registers a narrow method channel that returns `rootWindowInsets.isVisible(WindowInsets.Type.ime())`; the watchdog checks this platform visibility before recovery, so a real keyboard is never dismissed. A focused `EditableText` is the conservative fallback where that Android channel is absent or unsupported.

The timeout is four seconds: comfortably beyond normal IME animation/metrics convergence while limiting the field-observed dead-space defect. A 100dp arming threshold excludes small overlay/transient insets and targets the hundreds-of-dp keyboard signature. When fallback recovery acts, it emits the existing `layoutMode` diagnostic with `trigger: ime-watchdog` and then reasserts the cheap, idempotent `TextInput.hide` command.

## Regression test

- `app/test/routing/adaptive_test.dart`: reproduce a phone-sized, nonzero bottom view inset with platform IME visibility false and require a watchdog `TextInput.hide` exactly at the fake-clock deadline; prove a focused, platform-visible real IME survives beyond the timeout; and prove focus loss gets an immediate second hide reassertion.
- `app/test/routing/app_router_test.dart`: exercise the production full-screen phone chat with no pane/route/focus transition and assert both the platform recovery command and `layoutMode(trigger: ime-watchdog)` field evidence while preserving the existing split-collapse and edge-to-edge coverage.

## Implementation notes

**Execution capability:** `openai-codex/gpt-5.6-sol`, selected because the targeted patch crosses Flutter focus/metrics lifecycle, the Android embedding, router composition under a root chat route, and field diagnostics. Direct implementation kept one owner across this cohesive boundary.

**Files changed:**

- `app/lib/routing/adaptive.dart` generalizes the existing lifecycle boundary with focus-loss reassertion, a four-second/100dp stale-inset watchdog, platform visibility query, and owned teardown.
- `app/android/app/src/main/kotlin/dev/kevoun/outpostpi/MainActivity.kt` exposes Android's current IME visibility and removes the handler at engine cleanup.
- `app/lib/routing/app_router.dart` wires watchdog field diagnostics and repairs layout-event structural deduplication.
- `app/lib/domain/contracts/debug_log.dart` and its registry/routing tests bring the already-added `layoutMode` double metric and external UI seam into the diagnostic contract.
- `app/test/routing/adaptive_test.dart` and `app/test/routing/app_router_test.dart` add the regression family.

**Fails-before evidence:** the single-pane fake-clock test reached four seconds with zero `TextInput.hide` calls (`Expected length 1; Actual length 0`). The focus-loss test observed only EditableText's ordinary hide (`Expected length 2; Actual length 1`). The pre-existing production router test also exposed that the immediately preceding layout instrumentation commit had not registered a test `DebugLog`; the repaired seam now records and asserts the real event.

**Break-it proof:** temporarily bypassing both the platform-visibility and focused-editable guards made `focused real keyboard is never dismissed by the watchdog` fail with one forbidden `TextInput.hide`. Restoring the guards made the same test pass. No scratch mutation remains.

**Confirmation:**

1. The three new adaptive tests and the production router seam pass with deterministic `WidgetTester.pump` fake time.
2. `flutter analyze` reports no issues.
3. `flutter test --exclude-tags e2e --concurrency=2` passes all 984 tests (981 baseline + 3 regressions).
4. `flutter build apk --debug` compiles the Android channel and produces `app-debug.apk`; the artifact remains ignored.
5. The production seam reproduces the field signature on full-screen phone chat (411x797, `imeDp: 280`, no transition), observes `TextInput.hide` plus `trigger: ime-watchdog`, and then restores the inset to zero. Physical Pixel Fold rc.3 confirmation remains operator UAT.

No adjacent product issue was found or parked.

## Bounded inline review

**Verdict: approve.** This is a standalone story, so review stayed in the host context with no independent, fresh-context, or cross-model reviewer. One material race was found and fixed before approval: a stale inset could coexist briefly with a newly focused editable before Android's visibility bit became true, so fallback recovery now requires both platform IME visibility false and no focused `EditableText` before hiding.

The final lifecycle has one shell owner for the focus listener, metrics observer, and timer; disposal removes/cancels all three. Pane-collapse behavior and its re-expansion guard remain intact. The full-screen root chat is covered while the underlying shell owner remains mounted. Query errors fail safe against dismissing a real keyboard, and no user input or sensitive data enters the host channel or diagnostics. The channel is internal, has engine-cleanup teardown, and changes no wire/persistence/public contract. Tests cover fails-before stale state, focus loss, real-IME protection, route integration, field evidence, and the existing fold/edge-to-edge cycle; final analyze, 984-test suite, and debug APK build are green. Foundation docs contain no assertion contradicted by this focused Android lifecycle fix.

**Nits rejected:** renaming `PaneCollapseImeDismissal` would better reflect its broadened ownership, but the existing name is the v0.8.1 regression boundary named throughout historical tests/evidence; renaming adds churn without changing the fix contract.
