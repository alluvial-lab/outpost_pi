---
id: story-e2e-oddities-harness-infra
kind: story
stage: done
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
- [x] `e2e/run-live.sh` reaches: app paired to compose relay, pi-host shows
      the paired peer, capture ring recording — end to end on the VM.
- [x] Fault helpers each demonstrated once in a smoke test.
- [x] No changes to production relay/extension behavior (adapter/test-support
      additions only, if any).

## Implementation

- Execution capability: `sol/high` — cross-component harness implementation and real VM/emulator verification.
- Review weight: standard (project default); review is not applicable to this child-story checkpoint.
- Landed `e2e/run-live.sh`, the sourceable `e2e/lib/faults.sh`, and the e2e-tagged `app/integration_test/live_infra_smoke_test.dart`.
- The runner creates a unique Compose project, discovers published ports, configures the existing `app-relay`/`pi-host` proxies, boots `outpost34` under `sg kvm`, installs the debug APK, grants CAMERA, drives each requested fault through test/runner phase markers, requires a non-empty debug-ring pull, and always tears down the emulator plus Compose volumes unless `E2E_KEEP_STACK=1` retains the stack for diagnosis.
- Added an adapter-only preserving restart mode: `POST /__restart?preserve=1` writes a one-shot marker so the next pi-host process generation retains machine identity and owner-channel state. The default `/__restart` remains reset-for-isolation for the existing pairing suite.
- QR/config-vector deviation: the canonical production QR deliberately omits relay URL (`QrPairPayload.relayUrl == null`; Plan 14 behavior). The device smoke therefore writes the adb-reversed localhost relay URL through the production `Preferences.setRelayUrl` boundary before scanning. No production app seam, Gradle change, or pubspec change was required.
- The hard-down network smoke quiesces the pending retry while Toxiproxy is restored, then invokes the app's normal explicit reconnect entry point after five bounded successful health probes. This avoids racing a WebSocket handshake against the proxy's enable transition while still proving disconnect and recovery.
- Pi restart verification uses generation change, relay readiness, app `StatusOnline`, and observed room control updates. The test adapter's status enum remains `started` after loading an existing pairing because `paired` is an in-generation handshake marker, not a persisted-peer count.
- Files changed: `e2e/run-live.sh`, `e2e/lib/faults.sh`, `app/integration_test/live_infra_smoke_test.dart`, `pi-extension/test/support/e2e_pi_host_server.ts`, `pi-extension/test/support/e2e_pi_host_runtime.ts`, and this item.
- Tests added: one real-device integration smoke covering native QR decode/pairing, Toxiproxy down/clear, relay pause/resume, preserving pi-host restart, app background/foreground, airplane on/off, and debug capture export/pull.
- Simplification: reused the existing Compose topology, proxy names, production pairing components, and scanner boundary; no second stack, mock transport, app URL override, or new dependency was added.
- Adjacent issues parked: none.

Verification (2026-08-21):

```text
OUTPOST_LIVE_FAULT_REQUEST app_airplane off
[live] applied app_airplane off
00:19 +1: (tearDownAll)
00:20 +1: All tests passed!
live device e2e passed: pairing + network + relay + pi restart + lifecycle + airplane + capture
```

Additional checks: `corepack pnpm typecheck` passed, `bash -n e2e/run-live.sh e2e/lib/faults.sh` passed, and every live run compiled the pi-host TypeScript adapter before Compose startup.
