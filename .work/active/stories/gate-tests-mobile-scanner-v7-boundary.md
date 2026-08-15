---
id: gate-tests-mobile-scanner-v7-boundary
kind: story
stage: implementing
tags: [app, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-08-15
updated: 2026-08-15
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
