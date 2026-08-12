---
id: backlog-pairing-e2e-flaky-auth-handshake-timeout
created: 2026-08-12
updated: 2026-08-12
tags: [app, pi-extension, relay, bug, flaky, testing]
depends_on: []
---

# pairing-e2e flaky 10s auth-handshake timeout (CI-runner-specific)

## Status
**OPEN — root-cause-elusive after deep investigation (2026-08-12).** See session-note
`2026-08-12-pairing-e2e-room-divergence-fix.md`. The blocking-stdout fix landed
as a correct improvement but did NOT fix this flake. Failing connections'
relay auth still produces NO log line (`authenticated`/`auth failed`/
`phase=auth handshake step failed`) = the `handle_peer` task is intermittently
unpolled. Ruled out: blocking stdout (fixed), `std::thread::sleep` (test-only),
sync `register` (it's fully async), panics (none). Most likely remaining cause:
**runner-level CPU contention** — a 2-CPU GitHub runner runs relay+pi-host+
toxiproxy+flutter, intermittently starving the relay's tokio runtime (never
reproduces on the dev VM, which has more headroom). Diagnostics in place
(e2e/run-pairing.sh surfaces relay+pi-host logs on failure) for the next attempt.

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

## Why the `#N` collision is NOT the cause
Every generation is `e2e-agent#2` (the harness `rmSync(homedir())` mints a fresh
identity each gen → new epk → `self_revoke` can't reclaim → relay doesn't
supersede different-peer_id stale peers). BUT a green run (run3) also had `#2`
throughout, so the collision alone does not cause failure. Stale-peer
accumulation MAY contribute (firehose backpressure delaying app frames) but is
not deterministically causal. Do not chase the `#N` as the fix for THIS bug.

## Next step to root-cause
Capture a FAILING run's relay logs with debug detail:
1. Bump the e2e relay to `RUST_LOG=info,relay=debug`
   (`e2e/docker-compose.test.yml` relay env) — redaction-safe (data plane stays
   opaque; only `env_id_tail` correlation is added).
2. Surface the relay log on failure — `run-pairing.sh` currently writes it to a
   scrubbed `$RELAY_LOG` that is NOT in CI stdout. Add a `cat`/print of the
   failing region (or `E2E_KEEP_STACK` + a follow-up step) so the auth sequence
   is visible.
3. On the next flaky failure, check the relay log around the stall:
   - `authenticated … room=main` present → app DID auth → stall is post-auth
     (likely firehose/presence backpressure from accumulated stale peers, or
     pair_ok forwarding delay). Candidate fix: clean stale peers (preserve
     identity in the harness so relay supersession fires) and/or bound firehose.
   - `warn phase=auth handshake step failed, closing` → app's auth missed the
     5s relay window → the app's auth SEND is being starved on the CI runner.
     Candidate fix: send auth with higher priority / before any other work, or
     make the app fail-fast on relay close instead of stalling 10s.

## Related
- `backlog-pairing-e2e-room-id-divergence` (FIXED — same CI job, different bug).
- App-side `WsTransport.connect` optimistic `authDone` is a latent correctness
  gap worth tightening regardless (app assumes auth succeeded with no confirm).
