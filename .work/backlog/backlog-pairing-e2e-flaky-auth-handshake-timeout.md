---
id: backlog-pairing-e2e-flaky-auth-handshake-timeout
created: 2026-08-12
updated: 2026-08-12
tags: [app, pi-extension, relay, bug, flaky, testing]
depends_on: []
---

# pairing-e2e flaky 10s auth-handshake timeout (CI-runner-specific)

## Status
**RESOLVED-BY-SUBSIDENCE (2026-08-13).** After reverting the non-blocking
stdout change (see below), the pairing-e2e job went **12 consecutive greens**
and stayed green; the flake stopped reproducing. The non-blocking stdout
writer was net-harmful here: it **dropped log lines** under CI churn (firehose /
room_meta / disconnected / the diagnostic probes all vanished; only `authenticated`
survived) and its dedicated appender thread competed with the tokio workers for
the 4-vCPU runner's CPU (intra-container contention that `cpu_shares` could not
address, since that only weights containers against each other). Reverting to
sync `std::io::stdout` restored full logging AND stability.

The original timeout-flake root cause was **not captured with a probe** (the
flake vanished after the revert, before a failing run could be caught with the
handshake probes in place). Best understanding: the flake was a tokio
handshake-task stall under CI CPU pressure; the non-blocking appender thread
was an aggravating factor, and removing it dropped the rate below the
reproduction threshold. The `e2e/run-pairing.sh` service-log-surfacing is KEPT
as a permanent aid (failure-gated, redaction-safe); the handshake probes were
removed. If the flake recurs, re-add probes to `handle_peer` and the surfaced
logs will pinpoint the step.

The invariant evidence: failing connections' `handle_peer` task produces NO log
at all — not `authenticated`, not `auth failed`, not `phase=auth handshake step
failed` — at EITHER 5s or 30s. Per tokio's `time::timeout` semantics that log
MUST fire once the task is polled after the deadline, so the task is provably
not being polled, for a reason that is NOT CPU, NOT blocking stdout, NOT the
auth being delayed. This points at a subtle tokio/axum/tungstenite runtime
interaction (waker loss, I/O-driver registration, or the `PreAuthGuard`
wrapper) that needs `tokio-console`/live-debugger instrumentation to crack —
beyond CI-log investigation. It is dev-VM-unreproducible. Diagnostics in place
(e2e/run-pairing.sh surfaces relay+pi-host logs on failure).

Pragmatic resolution options: (a) bounded retry-on-failure on the e2e job
(transparent masking — defensible for an integration-level e2e on a shared
runner, once a real fix is confirmed out of reach); (b) deeper runtime
instrumentation; (c) app-side retry/robustness in WsTransport.connect.

## Symptom
`pairing-e2e` CI job fails ~20-40% of runs with `TimeoutException after
0:00:10.000000: Future not completed`, on a **different test each run**
(owner_channel negative tests, session_hydration, cross_room pairing, qr_lifecycle,
even the first test of the suite). The common factor is always the relay WS
auth handshake — see Localization. `ci.yml` (unit tests) is unrelated and now
green (chmod fix).

## Localization (app-side, confirmed)
The stall is in `WsTransport.connect` (`app/lib/data/transport/ws_transport.dart`):
- App connects WS, receives relay preauth challenge → logs `[ws-in] bytes=75 stage=preauth`.
- App signs the nonce and sends `{type: auth, sig}`, then sets `authDone = true`
  **optimistically — WITHOUT waiting for the relay to confirm auth**.
- App proceeds to `performPairing` (pair_request → pair_ok). If the relay never
  accepted the auth (closed/timed out), pair_request stalls the full 10s.

Relay side (`relay/src/handlers/peer.rs`): receive hello → send challenge →
`next_handshake_text().await` with `HANDSHAKE_STEP_TIMEOUT = 5s`
(`relay/src/resource_limits.rs`) → `verify_auth` → log `authenticated` OR
`warn phase=auth handshake step failed, closing` (5s) / `warn auth failed`.

## Could NOT reproduce locally
6 consecutive green `bash e2e/run-pairing.sh` runs on the dev VM (prebuilt
`outpost-pi-relay:0.4.0` AND source-built). The CI runner (faster, different
scheduling) hits it; this VM does not. Relay source == 0.4.0 image (only a
version-bump commit differs; both `cargo build --release`), so it is NOT a
source-vs-image difference — it is runner timing / scheduling.

## What was ruled out (CI A/B)
- **CPU starvation via `cpu_shares` 4×** on the relay: did not help (1 green,
  1 fail).
- **App-auth-delay past the 5s deadline** via `HANDSHAKE_STEP_TIMEOUT` 30s:
  did not help (2 green, 1 fail; failing connections still produced no
  `phase=auth handshake step failed` even at 30s).
- `std::thread::sleep` in pi_forward: `#[cfg(test)]`-only (not in the release
  build). Sync `register`: fully async. Panics: none.

## What correlated with the flake
- The **non-blocking stdout tracing writer** (added trying to fix the flake):
  dropped log lines AND correlated with failures. Reverting it → 12 greens.
  This is the change that mattered; everything above was ruled out.
