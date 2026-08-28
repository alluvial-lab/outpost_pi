---
id: story-fix-stale-ime-watchdog-single-shot
kind: story
stage: review
tags: [app, bug, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# Stale-IME half-screen rendering persists: watchdog is single-shot and its recovery fails

## Symptom (operator report, 2026-08-28)

Keyboard hidden but the layout still renders half-screen (keyboard-height
space reserved) on the v0.10.1 release APK. This is the bug class
`story-fix-app-stale-ime-inset` (v0.10.0) targeted — the fix is present in
the build but the symptom persists: incomplete fix or variant.

## Evidence (capture-diagnosed, 2026-08-28T12-54 capture)

- 14 high-inset plateaus (`imeDp=328`, keyboard height) lasting 47–175
  seconds while the only surrounding events are agent-stream tags
  (`wsIn`, `workingConv`) — reading, not typing.
- The `ime-watchdog` recovery trigger fired **exactly once** in 96
  minutes, at 11:53:48.984. Timeline: inset was `0` at −4.5s; jumped
  straight to `328` at −4.0s (no animation frames — a wedged inset
  report, not a keyboard opening; correlates with a `working→false`
  transition); watchdog fired at +0s (= `kStaleImeWatchdogDelay` 4s) —
  and the watchdog only fires after checking `_isImeVisible()` is false
  AND no text-input connection, so "328dp inset with no keyboard" is
  objectively confirmed. The inset then stayed at 328 for ~50 MORE
  seconds: **the recovery (`TextInput.hide`) did not clear the wedge**.
- Code semantics (`app/lib/routing/adaptive.dart`,
  `_reconcileWatchdog`): once `_watchdogActedForInset` latches, the
  watchdog never re-arms until inset drops below 100dp — one recovery
  attempt per plateau, and apparently zero for the other 13 plateaus in
  this session.

## Root cause

Two-layer failure of the v0.10.0 backstop:
1. **Single-shot latch** — `_watchdogActedForInset` blocks any retry
   within a plateau; if the one attempt fails, the phantom state
   persists until an external event (operator rotates / room switch)
   resets the inset.
2. **Insufficient recovery method** — `SystemChannels.textInput
   .invokeMethod('TextInput.hide')` addresses the input channel, but the
   wedge is at the window-inset level (inset jumped 0→328 with no
   animation right at a turn boundary); hide does not force Android to
   re-evaluate `viewInsets`.

Cause-side observation for the fix to note (not necessarily fix): the
wedge appeared at a `working→false` transition with a non-animated
0→328 inset jump — worth instrumenting, but the fix lane is the
recovery path.

## Fix approach

- **Recovery = platform-channel `WindowInsetsControllerCompat.hide(ime())`**
  (new MethodChannel into `MainActivity`; androidx core is already on the
  classpath via Flutter; `minSdk = 34` makes the API unconditional — no
  version gating). Rationale: the wedge is at the window-inset layer
  (inset jumped 0→328 non-animated across a background return);
  `TextInput.hide` addresses only the input channel and provably failed
  in the 2026-08-28 capture. Upstream guidance on the engine inset edge
  conditions (flutter/flutter#118761) and the Android docs both point at
  the WindowInsetsController layer as the correct control surface. If
  `hide(ime())` alone does not dispatch a fresh inset pass on the wedged
  state, escalate to a show→hide toggle through the same controller.
- Re-arm the watchdog with bounded retry (re-attempt on a short interval
  while the phantom condition persists: inset ≥ threshold, IME not
  visible, no text connection — capped attempts with backoff so a
  legitimately-open keyboard never gets a permanent timer loop).
- Keep the existing diagnostics: every recovery attempt logs a
  `layoutMode` row (`trigger: ime-watchdog`), so field captures verify
  retries and which recovery method acted.
- **Upstream dependency note (park, not this story)**: flutter/flutter
  PR #191453 fixes the root cause class (#191156 background-return inset
  restore, #190974 animation jump) by calculating insets mathematically;
  it is NOT in our `flutter-3.47-candidate.0` framework. The next
  stack-currency pass should re-test this bug class against the newer
  engine and retire the watchdog if the platform fix holds.

## Regression test

Widget test(s) around `PaneCollapseImeDismissal` with fake view insets
and a pumped clock:
- phantom condition (inset ≥ threshold, IME invisible, no connection)
  persisting past the watchdog delay → recovery re-attempts (not
  single-shot) while the condition holds;
- legitimate keyboard-open (IME visible or connection active) → no
  recovery action;
- the chosen escalation actually drives the inset back to 0 in the
  test's fake environment (assert the recovery call sequence).

## Verification

`flutter analyze && flutter test --exclude-tags e2e` from `app/`.
Dispatch after `story-fix-midstream-hydrate-reorder-flicker` completes
(same subproject, avoid concurrent commits).

## Implementation notes

- **Root cause confirmed:** `_watchdogActedForInset` made recovery single-shot
  for each high-inset plateau, and `TextInput.hide` only addressed Flutter's
  input channel rather than the wedged Android window-inset controller. The
  watchdog now uses a bounded four-attempt retry budget and the Android host
  calls `WindowInsetsControllerCompat.hide(WindowInsetsCompat.Type.ime())`
  followed by `requestApplyInsets()`.
- **Files changed:** `app/lib/routing/adaptive.dart`,
  `app/android/app/src/main/kotlin/dev/kevoun/outpostpi/MainActivity.kt`,
  `app/test/routing/adaptive_test.dart`,
  `app/test/routing/app_router_test.dart`, and this story.
- **Tests:** Extended the existing stale-IME widget coverage to assert the
  platform recovery method, persistent-plateau retries and diagnostic callback
  per attempt, the four-attempt cap, legitimate visible and active-input
  paths, and the `TextInput.hide` fallback when the recovery channel is
  unavailable. The router seam now exercises the available platform channel.
  A separate Android platform-integration test is not required: the host
  handler is a small registration adapter, while the Dart call-site contract
  is covered with a mock method channel.
- **Four-step confirmation evidence:**
  1. The new focused adaptive widget tests pass, including the retry, cap,
     legitimate-input, and fallback cases.
  2. `flutter analyze && flutter test --exclude-tags e2e` passes from `app/`
     (1001 tests); `flutter build apk --debug` also compiles the Android host
     handler successfully.
  3. The capture's persistent-inset reproduction is replayed deterministically
     by the fake 280dp inset tests; a physical Pixel Fold recapture was not
     available in this environment, so no device-level symptom claim is made.
  4. The reported failure mode is addressed directly: each still-phantom
     plateau receives four window-inset recovery attempts, each emits the
     existing `ime-watchdog` diagnostic row, and a host/channel failure retains
     the prior input-channel fallback without touching legitimate keyboard
     paths.
- **Execution capability:** focused inline implementation, chosen because the
  fix is bounded to the routing watchdog, its Android registration adapter,
  and their contract tests; no coordination or cross-subproject changes were
  needed.
- **Parked adjacent observation:** the capture's cause-side non-animated
  `0→328dp` inset jump at the `working→false` background-return boundary is
  intentionally not bundled. The upstream Flutter fix context (#191453/
  #191156) remains a future stack-currency re-test and watchdog-retirement
  decision.
