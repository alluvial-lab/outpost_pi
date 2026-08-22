---
id: story-fix-app-reconnect-churn-timeout-lifecycle-failures
kind: story
stage: done
tags: [app, relay, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-22
updated: 2026-08-22
---

# Attribute reconnect churn timeout lifecycle failures

## Symptom

Operator capture `debug/cad-11f1-b349-a5efddf14d8d.bin` contains 336
connection-status transitions, 46 current-channel losses, and 100 reconnect
failures over 2026-08-16 through 2026-08-20: 89 `TimeoutException` and 11
`WebSocketChannelException`. Short online periods carried envelopes between
losses.

## Root cause

The 89 `TimeoutException` rows are not heartbeat expirations. They are the
app's explicit 10-second WebSocket connect/auth deadline in
`app/lib/config/dependencies.dart` surfacing through
`ConnectionManager._connect` as `retryConnect`. Heartbeat mismatch is falsified:
the deployed app interval had already been raised from 20 seconds to 45 seconds
in `3075edfb`, looser than the relay's 25-second ping, and the relay's first tick
waits one full 25-second interval (`a04a4405`). Several captured channels drop
less than 25 seconds after recent inbound frames, so neither heartbeat can have
expired; 46 unattributed channel-loss rows precede the reconnect failures.

The source capture predates cause attribution and therefore cannot distinguish
wire close from socket error for those 46 initiating drops. Its retry intervals
also show Android scheduling suspension: although the deadline is ten seconds,
many `connecting`→`TimeoutException` spans are minutes long (up to about seven
minutes in the overnight cluster). Those timeout counts measure unsuccessful
reconnect attempts while the relay/network/device was unavailable, not 89
independent connection-lifecycle defects.

No timestamp-matched production relay log exists for the 2026-08-16→20 ring.
The nearest live-soak relay captures on 2026-08-21 show wire-side disconnects
and scheduled duplicate-device takeover churn, including
`superseded_existing=true`; they do not implicate relay heartbeat timing.

## Fix approach

Do not change keepalive math speculatively. The required observability hardening
already landed in `1a43ac80` after this ring was captured:
`ConnChannelLostEvent.cause` now records the closed category `channelError`,
`channelDone`, `pingSendFailure`, or `simulated`, and the triage tool groups the
cause. A fresh capture can therefore attribute the initiating drop rather than
misreading its later connect deadline as the cause.

This story closes the stale known-open finding on diagnosis plus verified
already-landed hardening. A future fresh ring showing repeated
`pingSendFailure` would justify reopening keepalive code; `channelDone` or
`channelError` should instead be correlated with relay/proxy/device logs.

## Regression test

`scripts/debug_capture_triage.py --selftest` uses the checked-in minimal capture
fixture and asserts all 89 failures are `retryConnect/TimeoutException`, while
also requiring a churn cluster. This is the closest deterministic regression
for the historical environment-dependent incident. The current app debug
contract tests additionally require the closed `cause` field on
`connChannelLost` events.

## Failing-before / passing-after evidence

- Before `1a43ac80`, all 46 source-ring `connChannelLost` rows lacked `cause`, so
  the initiating disconnect was unclassifiable.
- After `1a43ac80`, `app/test/domain/contracts/debug_log_test.dart` requires the
  cause field and `scripts/debug_capture_triage.py` reports cause distributions;
  its self-test deterministically confirms the 89 connect-timeout attribution.
- No real-time sleeps or wall-clock-sensitive timing assertion was added.

## Implementation notes

- **Execution capability:** `sol/high`, selected for cross-checking a four-day
  mobile capture against Flutter WebSocket semantics, app lifecycle timing, and
  relay heartbeat history without forcing an ungrounded code change.
- **Files changed:** substrate story and `e2e/expected-soak-findings.txt` only;
  the stale backlog item was promoted/removed.
- **Confirmation:** capture triage reproduced 89
  `retryConnect/TimeoutException`, 11 `WebSocketChannelException`, 46 channel
  losses, and ten churn clusters; the deterministic self-test passed. App
  analyze and focused connection/debug-contract tests passed; relay
  fmt/clippy/tests passed. The full Flutter suite exposed unrelated
  load-sensitive sync-test drift parked as
  `idea-app-sync-service-suite-flakes` rather than bundled.
- **Original reproduction:** the historical ring remains reproducible by the
  triage fixture; the initiating loss now has cause attribution in current
  builds, so the original "unknown" observability failure is resolved.
- **Nightly manifest:** removed
  `backlog-app-reconnect-churn-timeout-lifecycle-failures`; no partial residue
  remains because timeout attribution and future disconnect attribution are
  both covered.
- **Adjacent issues:** none bundled.

## Verification

- `python3 scripts/debug_capture_triage.py --selftest`: PASS.
- `flutter analyze`: PASS, no issues.
- Focused debug-contract + connection-manager tests: PASS, 31/31.
- `flutter test --exclude-tags e2e --concurrency=2`: 884/886 then 885/886;
  different `sync_service_test.dart` assertions failed under suite load, while
  that complete file passed 96/96 alone. Parked as
  `idea-app-sync-service-suite-flakes`; unrelated to this diagnosis-only
  closure.
- `cargo fmt --check && cargo clippy -- -D warnings && cargo test`: PASS (234
  Rust tests across unit/integration suites).
- Live soak not required because this closure changes no runtime code; existing
  2026-08-21 live-soak logs supplied the nearest wire-side cross-check.

## Bounded inline review

**Verdict: PASS.** The diagnosis follows each `TimeoutException` to the only
production constructor, separates initiating channel loss from downstream
connect failure, checks both heartbeat intervals and relay first-tick behavior,
and explicitly marks the unavailable timestamp-matched relay evidence. The
closure relies only on already-tested cause hardening and removes no active
runtime protection. No speculative timing change or unrelated fix is bundled.
Per standalone-story policy, this was an inline self-review with no independent
or cross-model reviewer.
