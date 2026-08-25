---
status: groom-done
id: backlog-pairing-e2e-flaky-auth-handshake-timeout
created: 2026-08-12
updated: 2026-08-12
tags: [app, pi-extension, relay, bug, flaky, testing]
depends_on: []
---

# pairing-e2e flaky 10s auth-handshake timeout (CI-runner-specific)

## Status
**ROOT-CAUSED AND FIXED — TWO INDEPENDENT BUGS (2026-08-14).** What CI
lumped together as "the flake" was Mode A + Mode B co-occurring. Root causes
found via GLM-5.3 fresh-eyes forensics + targeted instrumentation (entrypoint
marker, boot line, docker inspect on failure).

### Mode A (pairing silence) — double root startup → QR/live-identity mismatch
`session_start` auto-start is fire-and-forget and the e2e harness immediately
invokes `/outpost-pi` again; both roots pass the "idle" guards, double-join
the mesh (`e2e-agent#2` — the two lock files seen on day one), and both
blind-mint a DIFFERENT file identity on the fresh HOME. The QR references the
last-RECORDED key while the live relay connection belongs to the
last-RESOLVING start — two independent orderings; on disagreement the
pair_request targets the losing connection, whose unbind-then-close supersede
swallows it tracelessly. One-shot app pairing then hangs (10s, or a bare
`receive()` → 2-min test timeout). Production-real on first-run machines with
concurrent starters.

Fix: `O_EXCL` create-once identity mint (EEXIST loser re-reads, brief retry
for the winner-mid-write window) + `_startRelayViaTransport` single-flight
(one relay connection). A root-level single-flight was tried first and
REVERTED: it coupled the harness to the possibly-hung background root and
turned a benign hang into a full pi-host wedge (Mode C scare, reverted in
65b790e). Fingerprints after fix: one relay auth + one identity per generation.

### Mode B (pi-host wedge at generation ~10-11) — docker restart-policy BACKOFF
`/__restart` exits the process; `restart: unless-stopped` had docker restart
it — but docker's backoff doubles per restart (100ms→51s by #10) and only
resets after a ≥10s container lifetime. Fast pairing tests cycle generations
in 3-9s, so the backoff kept doubling until it blew the tests' 45s
`restartForIsolation` window — every subsequent test failed with "Connection
closed before full header" on /status. Only trips when ENOUGH consecutive
tests are fast (one >10s test resets it) → CI-only (fast runner), never the
slower dev VM. Pinned by forensics: RestartCount=10, ExitCode=0, OOMKilled=false,
last lifetime 3.5s, docker in 48s backoff, restarting processes never printing
the entrypoint echo.

Fix: the container never exits — the image CMD respawns the node process in a
shell loop (~200ms); restart policy removed from the compose. Process exit
remains the reset boundary.

### Validation
Both fixes + full unit suite (974) + local e2e 16/16, then **7 consecutive CI
greens** (vs ~3-in-5 Mode-B rate pre-fix). Improved failure-time forensics kept:
relay grep now matches `dropping|disconnected|not found`; pi-host boot line;
container-state + docker-inspect dump; respawn markers in the CMD.

### Follow-ups (optional)
- Background root's rare hang (observed once pre-revert; no longer fatal) —
  its own hunt if it recurs.
- `owner_multiplexer.handleOuterFrame`'s `isCurrent()` early-return drops
  pair_requests with no `pair_error` — a best-effort error reply would convert
  any future silent drop into a fast failure.
- `exchangePairingJson` (e2e app) awaits a bare `receive()` with no timeout
  (the 2-min variant); bound it.

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
