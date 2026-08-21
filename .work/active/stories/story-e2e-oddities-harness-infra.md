---
id: story-e2e-oddities-harness-infra
kind: story
stage: implementing
tags: [app, pi-extension, relay, testing]
parent: feature-e2e-live-oddities-suite
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Device-lane harness infrastructure: emulator app × compose stack

Brings the real app UI (outpost34 emulator) against the existing compose
stack (relay + Toxiproxy + pi-host). Test-integrity rules apply.

## Units

### Unit 1: `e2e/run-live.sh`
One command: compose up (reuse docker-compose.test.yml semantics — unique
project, bounded readiness) → emulator boot (proven flag set; KVM gate) →
`adb reverse` device localhost → host Toxiproxy/relay ports → build+install
debug app (Gradle capped) → CAMERA grant loop (scanner-smoke pattern) → run
device integration tests → pull app capture ring + pi-host/relay logs →
teardown (always). `E2E_KEEP_STACK=1` retained for diagnosis.

### Unit 2: fault helpers (`e2e/lib/faults.sh`)
- `net_fault <class> [ms]` — toxiproxy timeout/slicer/down on the app's
  proxy pair; `net_clear`.
- `relay_pause/resume` — docker pause/unpause.
- `pi_restart` — POST /__restart (fast respawn, documented).
- `app_background/app_foreground`, `app_airplane on/off` — adb.
- `capture_pull` — adb pull the app's outpost_pi_debug.jsonl + timestamp.

### Unit 3: pairing bridge for the device
Verify QR-is-the-config-vector: fetch pi-host `/pair-code`, render QR, feed
via `analyzeImage` (scanner-boundary pattern). If the app needs a
settings-injectable relay URL instead, add the minimal test-only injection
seam and record the deviation.

## Acceptance criteria
- [ ] `e2e/run-live.sh` reaches: app paired to compose relay, pi-host shows
      the paired peer, capture ring recording — end to end on the VM.
- [ ] Fault helpers each demonstrated once in a smoke test.
- [ ] No changes to production relay/extension behavior (adapter/test-support
      additions only, if any).
