---
id: story-ci-android-emulator-test-job
kind: story
stage: review
tags: [app, testing, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-16
updated: 2026-08-20
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

- **Local emulator dev loop (STAGED 2026-08-20, one operator step left)** —
  KVM landed on the VM (host `--cpu host` change confirmed: i7-10700,
  16 vmx flags). Emulator package + `system-images;android-34;google_apis;
  x86_64` installed; AVD `outpost34` (pixel_6) created. **Blocked on:
  `agent` not in `kvm` group** — `/dev/kvm` is root:kvm 660, no passwordless
  sudo in-session. Operator runs on the VM: `sudo usermod -aG kvm agent`;
  then (no re-login needed) boot via `sg kvm -c` wrapping the emulator
  command below. Boot line: `$ANDROID_HOME/emulator/emulator -avd outpost34
  -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim
  -camera-back virtualscene -no-snapshot -memory 3072`; smoke:
  `cd app && flutter test integration_test/mobile_scanner_boundary_test.dart
  -d emulator-5554 --tags e2e`. Complements the CI job (local =
  interactive/dev loop, CI = always-on gate); does not replace it.
- Runbook note: ADB-over-tailnet wireless debugging for real-phone UAT
  (steps 6–7 of docs/release-uat.md) — operator doc, cheap.
- Automating the full pairing e2e (relay + extension + emulator app in one
  job) — separate feature if the emulator job proves stable.

## Verification

YAML parse + zero mutable action refs; first real run on push (expect the
scanner smoke green; emulator flakiness, if any, gets addressed by retry/
boot-hardening, not by tagging the test out).

## Implementation (2026-08-20)

`app-e2e (android emulator)` job added to ci.yml — 10 steps, exactly per
design: needs [changes, app] (serial after unit), KVM gate fails red if
/dev/kvm unwritable (no software-emulation fallback), SDK install + AVD
outpost34 (pixel_6, android-34 google_apis x86_64), headless boot with the
proven local flag set + one retry then red, `scripts/emulator-scanner-smoke.sh`
reused verbatim for the grant-loop harness (no duplication), always() kill,
Gradle heap capped via ORG_GRADLE_PROJECT_org.gradle.jvmargs=3G. All action
pins copied from existing in-repo verified usage (checkout v7.0.1,
setup-java v5.7.0 temurin 17, flutter-action v2.23.0) — zero new mutable refs.

Verification: YAML parses (job/steps/needs introspected); 21 pinned / 0
mutable refs repo-wide; boot-retry run block passes bash -n; emulator-scanner-
smoke.sh is the same script that produced 3 consecutive green local runs on
the identical image+AVD+flags. **First live execution happens on push**
(same honesty boundary as all release workflows); boot flakiness, if any,
gets boot-hardening, never a silent skip.

### Bounded inline review (2026-08-20)
PASS — pins verbatim from verified in-repo usage; recipe is the
locally-proven one (25s boot, 3× green smoke); fail-loud posture matches the
story's "retries-or-fail, never skip" requirement; script reuse over
duplication.
