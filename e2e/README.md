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
under `/opt/android-sdk`, and the repository Flutter toolchain. These lanes take
an exclusive per-serial lock and record the run/emulator PID before startup. A
second live runner fails without touching an occupied serial; override the
default `emulator-5554` only with `E2E_ANDROID_SERIAL=emulator-<port>` and an
otherwise unused serial.

The `state-shapes` selector exercises multi-session projection isolation,
mid-conversation re-pairing, and bounded capture-ring/replay uptime. Full soaks
also schedule the multi-session and replay shapes; shorter soaks omit them to
keep quick scheduler/fault checks bounded. The `grid` selector assigns every
fault class to a representative pairing, hydration, staged-turn, QR-scan, or
cold-open cell without running the unbounded Cartesian product. Its two phases
force-stop the app before the cold-open cells.

The soak writes its schedule, capture triage, machine-readable findings
inventory, and invariant report below `.work/session-notes/` unless
`--artifacts` is supplied. Exit `0` means the runner and four-invariant oracle
were clean. Exit `1` is an unexpected violation. Exit `3` means a linked,
deterministically targeted finding was absent; that is **suspicious evidence,
not success**, because the intended reproducer window may not have been
exercised. A full interactive soak remains 10 minutes; shorter seeded runs are
useful when validating scheduler/oracle changes.

## Nightly cadence and skew drills

The VM runs the bounded nightly entry point at 02:30 local time:

```cron
30 2 * * * cd /home/agent/projects/outpost_pi && /home/agent/projects/outpost_pi/scripts/nightly_soak.sh >>/home/agent/projects/outpost_pi/.work/session-notes/nightly-soak/cron.log 2>&1 # outpost-pi-nightly-soak
```

`scripts/nightly_soak.sh` chooses a fresh seed, runs 15 minutes by default,
keeps the newest 14 run directories under
`.work/session-notes/nightly-soak/`, and writes `summary.md` plus `ALERT.md`
when the known-open inventory drifts or the soak fails. The canonical six-id
inventory is `e2e/expected-soak-findings.txt`; `live_soak.py` loads that manifest
directly. A known bug is reported without failing the soak, while either adding
an unreviewed finding id or removing an expected id is drift. Scheduled fault
windows reconcile expected reconnect churn; a churn cluster outside all such
windows is unexpected and fails the run. `E2E_NIGHTLY_SOAK_DURATION_SECONDS`,
`E2E_NIGHTLY_SOAK_KEEP`, `E2E_NIGHTLY_SOAK_HARD_TIMEOUT_SECONDS`,
`E2E_NIGHTLY_LANE_WAIT_SECONDS`, and `E2E_NIGHTLY_SOAK_REPORT_ROOT` override the
operational defaults.

The nightly wrapper has a 40-minute outer hard cap, waits for the exclusive
Android lane or alerts and skips, and runs disk hygiene from its EXIT trap.
Hygiene removes `app/build` and the Gradle build cache and resets the disposable
`outpost34` AVD writable userdata only after the owned emulator is confirmed
down; it never kills or resets a foreign occupied serial. Cron output is
retained in `cron.log`. `LATEST_ALERT.md` keeps recent alert history across later
successes, while `LAST_STATUS` records the timestamp and outcome of every run.

The exploratory skew entry points are host/container-only and do not consume
the Android device lane:

```bash
scripts/clock_skew_drill.sh
scripts/version_skew_drill.sh
```

The clock drill layers libfaketime onto the test relay and Pi-host images,
keeps monotonic time real, and crosses the first heartbeat while the peers'
wall clocks differ by four hours. The version drill builds the relay from the
previous unified release tag and runs it against the current app and extension
pairing suite. Both write bounded evidence below `.work/session-notes/` and
tear down their Compose projects.
