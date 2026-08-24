---
id: story-fix-app-compact-composer-ime-loop
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Keep the Android keyboard attached through compact-composer transitions

## Symptom

On a Pixel Fold running app 0.6.0+8 in two-window mode with Heliboard, the
keyboard disappeared while the operator was typing. The short allocated window
and keyboard animation could repeat the focus loss as an IME restart loop.

## Root cause

`ChatPage` selected compact composer chrome directly from the current remaining
height at a single 280dp threshold. Animated Android `viewInsets` could jitter
across that boundary in a roughly 420dp-tall window. Each mode change also
changed the root container key inside `InputBar`; Flutter therefore replaced the
`TextField`/`EditableText` subtree even though `InputBar` still owned the same
controller and `FocusNode`. Detaching the focused editable caused Android to
restart the IME, which changed the inset again and fed the threshold loop.

## Fix

Keep the 280dp compact entry threshold, but retain compact mode until remaining
height exceeds a separate 360dp exit threshold. Give the input bar container one
stable identity across mode changes; only padding, previews, and `maxLines`
respond to the compact parameter. Controller and focus ownership remain in the
long-lived `InputBar` state.

## Regression test

`app/test/ui/chat/chat_compact_composer_test.dart` drives a 420dp-tall
`ChatPage` through a noisy keyboard-inset ramp and requires one compact entry
that remains compact at the settled 280dp inset. It also focuses an `InputBar`,
performs legitimate standard→compact→standard changes, and requires the same
`FocusNode`, controller, and `EditableText` element to remain attached and
focused. The Pixel Fold golden matrix also asserts that the settled 797x411
keyboard case remains compact at the unchanged entry threshold.

## Failing reproduction

Before the fix, the focused regression produced both failures that form the
loop:

```text
Expected: [6, 6, 1, 1, 1, 1]
  Actual: [6, 6, 1, 6, 1, 1]

Expected: true
  Actual: <false>
```

The first mismatch is the compact→standard→compact bounce while animated
insets jitter around 280dp remaining height. The second is the replaced
`EditableText` element across a legitimate mode change. Command: `flutter test
test/ui/chat/chat_compact_composer_test.dart`.

## Implementation notes

- **Execution capability:** `sol/high`; selected because this is a focused UI
  lifecycle repair whose correctness depends on Flutter element identity and
  Android IME/focus behavior.
- **Files changed:** adaptive composer thresholds, `ChatPage`'s retained compact
  decision, `InputBar`'s stable container identity, focused regression tests,
  and the Fold golden-matrix compact assertion.
- **Ownership boundary:** `_InputBarState` continues to own the controller and
  `FocusNode` above the parameter-driven composer subtree. No route, ViewModel,
  protocol, persistence, or threshold-entry behavior changed.
- **Four-step confirmation:** the two focused regressions failed before and pass
  after; `flutter analyze` reports no issues; the full non-e2e suite passes all
  910 tests with `--concurrency=2`; the complete Fold matrix passes and directly
  asserts compact `maxLines == 1` for the settled 797x411+280dp-keyboard case.
  The host-side reproduction now crosses noisy inset values without mode bounce
  or editable replacement. The exact Pixel Fold/Heliboard device reproduction
  was not rerun because this task explicitly has no emulator or attached device.
- **Adjacent issues parked:** none discovered.

## Bounded inline review

**Verdict: PASS.** Reviewed the focused diff against the operator report and the
fails-before evidence. The 280dp entry point is unchanged; the 360dp exit bound
prevents inset jitter from reversing compact state; initial settled keyboard
layout remains compact; and the stable container key preserves the same
controller, `FocusNode`, and `EditableText` element while padding and `maxLines`
change. The focused tests, full suite, analyzer, and Fold matrix are green. No
material blocker, unrelated behavior change, or adjacent issue was found. Per
standalone-story policy, this was a bounded inline self-review with no
independent or cross-model reviewer.
