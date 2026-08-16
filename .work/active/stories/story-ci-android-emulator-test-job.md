---
id: story-ci-android-emulator-test-job
kind: story
stage: drafting
tags: [app, testing, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-16
updated: 2026-08-16
---

# CI Android emulator job for device-gated integration tests

Feasibility established 2026-08-16: the dev VM has no KVM/nested virt
(local emulator unusable), but GitHub Linux runners expose `/dev/kvm`
(nested virt since 2024), and the repo is public → Actions minutes are free.

## Why

`gate-tests-mobile-scanner-v7-boundary` landed a real-scanner integration
smoke that is emulator-compatible by construction (QR delivered via
`controller.analyzeImage()` through the real native ML-Kit decode; emulated
camera only needs to start the controller). It currently executes nowhere
automatically — device execution was left to operator UAT. This job makes it
part of the automated suite and provides the platform for future app
integration tests (Phosphor Beacon visual smoke, pairing e2e against relay
+ extension in-job).

## Design

- New job (extend `ci.yml` or a new `app-integration.yml` — prefer ci.yml
  beside the existing `app (analyze + test)` job; trigger on app/ paths).
- **Convention: every action ref SHA-pinned** (per
  `gate-security-release-workflow-action-pinning`, dbf46b84) — follow the
  comment style from ci.yml; resolve via `git ls-remote`.
- Steps: Java 17 + pinned flutter-action with the repo's FLUTTER_VERSION →
  `sdkmanager "emulator" "system-images;android-34;google_apis;x86_64"`
  (accept licenses) → `avdmanager create avd` (plain device profile) →
  boot headless: `-no-window -gpu swiftshader_indirect -noaudio
  -no-boot-anim -camera-back virtualscene`, KVM-accelerated (`-accel on`
  fails loudly if /dev/kvm is missing — no silent software-emulation fall-
  back) → `adb wait-for-shell` + poll `sys.boot_completed` with a hard
  timeout → `flutter test integration_test --tags e2e -d emulator-5554`
  → emulator kill + AVD cleanup in `if: always()`.
- Gradle heap capped (3G) per AGENTS.md; job runs serially after the unit
  job to avoid redundant cache warming.
- Emulator boot failures must be retries-or-fail, never skips: if the boot
  times out twice, the job fails red (a silently-skipped device gate is the
  failure mode release-uat.md exists to prevent).

## Follow-ons (not this story)

- **Local emulator dev loop (KVM pending host change)** — the VM is a
  Proxmox guest with default kvm64 vCPU type (vmx masked). Operator flips
  the host to `--cpu host` + full stop/start (2026-08-16 instructions
  handed off); then: sdkmanager emulator + android-34 google_apis x86_64
  image, AVD with `-camera-back virtualscene`, run the scanner smoke
  `-d emulator-5554`. Complements the CI job (local = interactive/dev loop,
  CI = always-on gate); does not replace it.
- Runbook note: ADB-over-tailnet wireless debugging for real-phone UAT
  (steps 6–7 of docs/release-uat.md) — operator doc, cheap.
- Automating the full pairing e2e (relay + extension + emulator app in one
  job) — separate feature if the emulator job proves stable.

## Verification

YAML parse + zero mutable action refs; first real run on push (expect the
scanner smoke green; emulator flakiness, if any, gets addressed by retry/
boot-hardening, not by tagging the test out).
