---
id: gate-docs-e2e-live-selector-pin-guard
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# E2E README omits live selectors and the pinless-AVD guard

## Drift category
readme-staleness

## Location
- Doc: `e2e/README.md:30-36,42-44`
- Contradicting source: `e2e/run-live.sh:16-20,141-149,286`

## Current doc text
> `e2e/run-live.sh state-shapes`
> `e2e/run-live.sh grid`
> ...
> They require `/dev/kvm` access, the `outpost34` AVD, Android SDK emulator/adb...

## Contradiction
The live runner now exposes `mesh` and `capture-delivery` selectors in addition to
`state-shapes` and `grid`, and every run calls `assert_pinless_e2e_avd` before the
device test. The README neither documents those entry points nor warns that a
secure keyguard/PIN fails the headless lane.

## Required edit
Update the live-lane command examples and prerequisites to list all four named
selectors and document the pinless-AVD guard and its recovery action. Keep the
selector and guard names synchronized with `e2e/run-live.sh`.
