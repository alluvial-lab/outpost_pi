---
id: gate-tests-android-ime-recovery-live-seam
created: 2026-08-28
updated: 2026-08-28
tags: [testing, app]
release_binding: null
gate_origin: tests
---

# Exercise stale-IME recovery through the real Android window-insets seam

## Priority
Medium

## Value evidence
Item: `story-fix-stale-ime-watchdog-single-shot` (also protects the earlier
`story-fix-app-stale-ime-inset` boundary)

Contract / risk / regression / maintenance cost: the field-observed half-screen
bug survived the first watchdog implementation even though its Dart widget tests
and debug APK build were green; capture evidence showed the input-channel hide
fired but left the 328dp wedge for another ~50 seconds
(`.work/active/stories/story-fix-stale-ime-watchdog-single-shot.md:33-40`). The
follow-up moved recovery to `WindowInsetsControllerCompat.hide(ime())` plus
`requestApplyInsets()` (`app/android/app/src/main/kotlin/dev/kevoun/outpostpi/MainActivity.kt:42-60`), but verification again stops at mocked Dart method channels and compilation. The item explicitly records that no Android platform integration test ran and no physical Pixel Fold recapture was available (`story-fix-stale-ime-watchdog-single-shot.md:120-134`). No current live integration lane references the IME recovery channels or asserts inset convergence.

A deterministic test cannot reproduce every OEM/Fold WindowManager wedge, so
this is not release-blocking and does not replace operator UAT. A device lane
would still materially protect the real method-channel registration, Android
controller call, focus/visibility guards, and post-hide layout convergence—the
exact boundary the prior mock-only fix failed to validate.

## Gap type
e2e-seam / bug-regression / unavailable-dependency boundary

## Suggested test
```dart
testWidgets('real Android IME close converges the production chat viewport', (tester) async {
  // Run on the existing outpost34 live AVD with the production MainActivity.
  // Focus the real chat composer and wait for a keyboard-sized viewInset.
  // Dismiss/background+foreground through the live fault channel, then assert
  // the inset and chat viewport return to full height within a bounded window.
  // Also assert no ime-watchdog recovery occurs while the real IME is visible.
  // Record a structural diagnostic when recovery is needed; never claim this
  // emulator scenario reproduces the Pixel Fold OEM wedge.
});
```

## Test location (suggested)
`app/integration_test/live_state_shapes_test.dart` (or a focused
`app/integration_test/live_ime_recovery_test.dart` selected by `e2e/run-live.sh`)
