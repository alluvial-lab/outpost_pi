---
id: gate-tests-mobile-scanner-v7-boundary
kind: story
stage: done
tags: [app, testing]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-15
updated: 2026-08-20
---

# Exercise the real mobile_scanner v7 QR boundary after the 5→7 major bump

Post-hoc v0.5.0 tests-gate finding. Severity: **High** — the v0.5.0 dep refresh
upgraded the QR scanner across a major version with zero tests touching the
real plugin boundary.

## Severity
High

## Contract at risk
Users must be able to scan a pairing QR from both the standalone pairing page
and onboarding after the scanner upgrade (pairing is the product's front door).

## Location
- Harness gap: `app/test/ui/pairing/pairing_viewmodel_test.dart:725` (renders
  "without MobileScanner")
- Production boundary: `app/lib/ui/pairing/pairing_page.dart:128`,
  `app/lib/ui/onboarding/widgets/pair_step.dart:200`
- Dep: `mobile_scanner ^7.4.0` at `app/pubspec.yaml:38` (was 5.2.3)

## Evidence
Widget tests bypass the plugin entirely; E2E consumes an already-decoded pair
code — no test starts the camera or delivers a `BarcodeCapture` through the
upgraded native plugin.

## Remediation direction
Android/iOS integration smoke using the real scanner controller: start
scanning → deliver a valid QR → exactly one pairing transition → verify
stop/dispose. Include null/duplicate detections only where they protect the
one-shot pairing rule.

## Implementation

- Added `app/integration_test/mobile_scanner_boundary_test.dart`, tagged
  `e2e`, with one smoke for each production entry surface: `PairingPage` and
  `PairStep`.
- Each smoke renders the real `MobileScanner` widget, waits for its real
  controller to start, rasterizes a QR in-test from the canonical
  `outpostpi://pair` content shape, and uses the native
  `MobileScannerController.analyzeImage` path to obtain a real
  `BarcodeCapture`. The capture is then delivered through the production
  callback; no scanner/platform mock is used.
- The test asserts the app parser accepts the generated content, rejects an
  empty capture before the valid scan, stops the controller after the first
  valid capture, suppresses one duplicate capture, and observes exactly one
  pairing transition (`PairingPaired` / onboarding `onPaired`). It then removes
  each entry surface and verifies the owned controller rejects reuse after
  disposal.
- Added the SDK `integration_test` and test-only `qr` dev dependencies. The
  smoke is excluded from the default suite by its `e2e` tag. The run path is
  recorded in `docs/release-uat.md`.
- Verified locally: `flutter analyze` is clean. The default
  `flutter test --exclude-tags e2e` suite was exercised; its broad parallel
  run reported three existing unrelated `sync_service_test.dart` failures,
  and the documented `--concurrency=2` run reported two different existing
  `sync_service_test.dart` failures. The sync test file passes when run alone
  with `--concurrency=2`; the full-suite flakiness is not caused by this
  smoke. The integration smoke could not be executed or compiled
  through the device runner because this VM has no supported device/emulator;
  `flutter test --exclude-tags e2e integration_test/mobile_scanner_boundary_test.dart`
  stopped at device discovery for the same reason. Operator Android/iOS UAT
  remains pending and is required before closing the gate. `flutter build apk
  --debug` passed locally; no smoke execution is claimed.

### Bounded inline review (2026-08-16)
PASS — real-scanner smoke e2e-tagged out of the default suite, analyze + debug APK compile green; device execution remains operator UAT (honestly recorded, not claimed).

### Emulator execution (2026-08-20 — supersedes "device UAT pending" for automation)

First real execution happened on the LOCAL emulator (KVM unlocked on the VM;
AVD `outpost34`, android-34 google_apis x86_64, `-camera-back virtualscene`,
`-gpu swiftshader_indirect`). It immediately caught two harness bugs that
compile+analyze could never see: an untyped `ChangeNotifierProvider` that
registered the test subclass instead of `PairingViewModel` (ProviderNotFound
at page build), and a 12s camera-start budget far below swiftshader cold-init
reality. Also: `flutter test` reinstalls per run, clearing runtime grants —
`scripts/emulator-scanner-smoke.sh` auto-grants CAMERA (dialog-tap fallback).
Fixed in 6eb19fe1; **3 consecutive green runs** (`+2` each, ~11s).

Release-UAT step 6 now has an automatable path; the real-phone tier remains
reserved for true hardware-camera confirmation.
