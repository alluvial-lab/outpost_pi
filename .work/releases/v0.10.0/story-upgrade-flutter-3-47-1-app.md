---
id: story-upgrade-flutter-3-47-1-app
kind: story
stage: done
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: [story-migrate-app-agp9-built-in-kotlin]
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Upgrade Flutter to 3.47.1 (APP-ONLY — cockpit dormant)

SCOPE REVISED (cockpit dormancy 2026-08-27): app + e2e-pairing + app-release pins to 3.47.1; NO macOS/appcast work (cockpit stays frozen 3.44.4). Pixel Fold UAT incl. stale-IME behavior check is the evidence gate.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Status (2026-08-27)

Mechanical scope COMPLETE via the AGP 9 capstone (3d4b0e9df): Flutter
3.47.1/Dart 3.13.1 + AGP 9.1.0/Gradle 9.3.1 + builtInKotlin=true + pins
moved (app CI/release/E2E; cockpit stays frozen 3.44.4). Verification:
987 tests, speech 33, zero build warnings, signed release+slim, badging ok.
newDsl=false retained (Flutter 3.47.1 vs AGP new-DSL failure — tracked).
REMAINING: operator Pixel Fold UAT (v0.10.0-rc.1 artifact), evidence gate
incl. stale-IME behavior on 3.47.

## Closure (2026-08-27)

Operator published v0.10.0 from the rc.1 build ("Publish") after field
verdict on the rc build + the full pre-phone battery (no-start guard, 7-lane
e2e incl. 600s chaos soak — zero unexpected findings, capture-delivery
green). UAT gate satisfied by operator decision.
