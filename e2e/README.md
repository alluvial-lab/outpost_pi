# Pairing lifecycle e2e harness

Run the cross-component headless suite from the repository root:

```bash
e2e/run-pairing.sh
```

The runner builds the relay from the current `relay/Dockerfile`, starts a narrow
HTTP-controlled Pi SDK host and pinned Toxiproxy, then drives the app's production
pairing, transport, connection, sync, generated-codec, and Hive paths. It builds
no APK and needs no emulator, phone, model provider, or secrets.

Set `OUTPOST_PI_E2E_RELAY_IMAGE` to opt out of the source build and exercise an
already-built relay image. Set `E2E_KEEP_STACK=1` to retain the uniquely named
stack after a failed run for local diagnosis; the default always removes
containers and volumes. `E2E_INFRA_ONLY=1` performs only the service/typecheck
smoke.

Each run uses a distinct Compose project and Docker-assigned host ports. Proxy
initialization is idempotent. All readiness checks are bounded. The failure-mode
suite registers real nonce, signature, QR, key, and transcript canaries, captures
Flutter output plus Pi-host and relay service logs, and fails with only a hashed
fingerprint if any canary appears in diagnostics.

## Live device and soak lanes

The live oddities lanes drive the production Android app on the headless
`outpost34` AVD:

```bash
e2e/run-live.sh integration_test/live_golden_test.dart
e2e/run-live.sh integration_test/live_failure_test.dart
e2e/run-live.sh state-shapes
e2e/run-live.sh grid
python3 e2e/live_soak.py --duration 600 --seed 20260821
```

They require `/dev/kvm` access, the `outpost34` AVD, Android SDK emulator/adb
under `/opt/android-sdk`, and the repository Flutter toolchain. These lanes are
serial-only: do not run two live runners or soaks concurrently against the same
AVD/Android serial. Override the default `emulator-5554` only with
`E2E_ANDROID_SERIAL=emulator-<port>` and an otherwise unused serial.

The `state-shapes` selector exercises multi-session projection isolation,
mid-conversation re-pairing, and bounded capture-ring/replay uptime. Full soaks
also schedule the multi-session and replay shapes; shorter soaks omit them to
keep quick scheduler/fault checks bounded. The `grid` selector assigns every
fault class to a representative pairing, hydration, staged-turn, QR-scan, or
cold-open cell without running the unbounded Cartesian product. Its two phases
force-stop the app before the cold-open cells.

The soak writes its schedule, capture triage, and invariant report below
`.work/session-notes/` unless `--artifacts` is supplied. Exit `0` means the
runner and four-invariant oracle were clean. Exit `1` is an unexpected
violation. Exit `3` means a linked expected finding was absent; that is
**suspicious evidence, not success**, because the intended reproducer window
may not have been exercised. A full scheduled soak remains 10 minutes; shorter
seeded runs are useful when validating scheduler/oracle changes.
