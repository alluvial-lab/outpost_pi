# 2026-08-12 — pairing-e2e room-ID divergence fix + ci.yml chmod fix (2 of 3 reds green)

Fresh-context entry point: this closed **Priority 1** from
`2026-08-12-resume-parked-work.md` (the red CI). Read together with
`backlog-pairing-e2e-room-id-divergence.md` (room bug, FIXED) and
`backlog-pairing-e2e-flaky-auth-handshake-timeout.md` (residual flakiness, OPEN).

## TL;DR
The red CI had **three** distinct failures. Two are now fixed; one (a
pre-existing flaky timeout) remains open and is characterized below.

1. **Room-ID divergence (FIXED)** — the e2e pi-host status harness re-derived
   the App↔Pi room with a hardcoded name; production derives it from the
   mesh-assigned name (with a `#N` collision suffix). Fixed by reading the
   production `_myRoomId` via a new test accessor. Verified locally 16/16.
2. **ci.yml unhandled chmod ENOENT (FIXED)** — `_tryBind`'s listen callback
   chmod'd the lock socket unguarded; a teardown race threw ENOENT → vitest
   failed the ci.yml unit run. Guarded the chmod. **ci.yml is now GREEN.**
3. **pairing-e2e flaky 10s auth-handshake timeout (OPEN, pre-existing)** — see
   below. My room fix UNMASKED it (tests now reach the pairing path instead of
   failing at the room assertion). It is CI-runner-specific and orthogonal.

## How the diagnosis was pinned (technique worth repeating)
The symptom (status room `wc3B14rFnkrH` ≠ QR room `KzJ3MohnQOvq`) was cryptic.
The decisive move was **hashing candidate derivations** against the observed
room IDs:

| derivation | hash | matches |
|---|---|---|
| `roomIdFor(cwd, "e2e-agent")` | `wc3B14rFnkrH` | status room ✓ |
| `roomIdFor(cwd, "e2e-agent#2")` | `KzJ3MohnQOvq` | QR room ✓ |
| `roomIdForCwd(cwd)` (legacy) | `A1a0RKUXF5K6` | neither |

That instantly localized the bug to the **name** axis (`e2e-agent` vs
`e2e-agent#2`) and identified the status harness's hardcoded re-derivation as
the sole wrong code path. The QR room was production-truth all along.

## The fix (3 files, +32/-2)
- `pi-extension/src/extension/testing.ts` — added `roomId(): string | null` to
  `OutpostPiTestHarness` with a self-defending doc comment.
- `pi-extension/src/index.ts` — added `getRoomIdForTest()` returning `_myRoomId`;
  wired `roomId: () => getRoomIdForTest()` into the harness singleton.
- `pi-extension/test/support/e2e_pi_host_runtime.ts` — `status()` reads
  `outpostPiTestHarness.roomId() ?? roomIdFor(cwd, "e2e-agent")` (the idle
  fallback is the no-mesh derivation, never the asserted state); inline
  `ProductionModule` type updated to match.

**Why this isn't test-gaming:** the status endpoint is a TEST HARNESS whose job
is to report the production extension's actual state. It was reporting a room
the extension never registered. Reading `_myRoomId` makes it report truth.

## Why the collision happens (and why we did NOT "fix" it)
The `#2` suffix arises because `restartForIsolation()` (`process.exit(0)` +
Docker `restart: unless-stopped`) can leave a stale `e2e-agent` mesh
registration that the next generation's broker disambiguates with `#N`. This is
**documented expected production behavior** (`mesh_node.ts`: "broker may add a
#N collision suffix") — the production room derivation is correct under it. The
harness was the only thing guessing. Making the harness report truth is the
complete fix; chasing the collision would be papering over a correct production
path.

## Verification
- `tsc --noEmit` clean; `tsc` build clean.
- `vitest run src/extension.test.ts …` → 226 passed (1 pre-existing unrelated
  teardown ENOENT race on a restart-sweep temp socket).
- `bash e2e/run-pairing.sh` (with prebuilt `outpost-pi-relay:0.4.0` to skip the
  Rust rebuild — relay is room-blind) → **16/16 e2e passed**, redaction canaries
  passed. Logs showed `room=KzJ3MohnQOvq` (= `e2e-agent#2`) — the collision
  occurred and the suite still passed.

## ci.yml chmod fix (separate, landed same session)
The `226 passed (1 Error)` I first dismissed as "pre-existing teardown race"
actually fails ci.yml: vitest exits non-zero on the unhandled error. The error
was `_tryBind` (leader_election.ts) chmod'ing the bound lock socket
unguarded; a concurrent teardown `rmSync` removed it first → ENOENT. Guarded
the chmod (best-effort, like other sites). ci.yml unit job now **GREEN**.

## OPEN: pairing-e2e flaky 10s auth-handshake timeout
After the two fixes above, `bash e2e/run-pairing.sh` is reliably green LOCALLY
(6 consecutive green runs), but the **CI** `pairing-e2e` job still fails
~20-40% of runs with `TimeoutException after 0:00:10` on a **different test
each run** (owner_channel negative tests, session_hydration, cross_room, even
the first test). This is **pre-existing** (ci.yml+pairing-e2e were both red
before this session's push) and **orthogonal** to the room fix (the app pairs
on the QR room, unaffected by status.roomId).

**Symptom localization:** the stall is in the app's relay WS auth handshake
(`WsTransport.connect`, `app/lib/data/transport/ws_transport.dart`). The app
receives the relay's preauth challenge (`[ws-in] bytes=75 stage=preauth`), sends
its signed auth, and sets `authDone=true` **optimistically — without waiting for
relay confirmation**. It then proceeds to `performPairing` (pair_request),
which stalls the full 10s if the relay never accepted the auth. The relay's
`HANDSHAKE_STEP_TIMEOUT = 5s` (`relay/src/resource_limits.rs`); if the app's
auth lands >5s after the challenge the relay closes and the app stalls.

**Could not reproduce locally** (6 green runs on this VM, prebuilt + source) to
capture the failing run's relay logs. The CI runner (faster/different
scheduling) hits it; this VM doesn't.

**Next step to root-cause:** run the e2e on CI with `RUST_LOG=info,relay=debug`
AND surface the relay log on failure (run-pairing.sh currently writes it to a
scrubbed file that isn't in CI stdout). Then check whether the failing run's
relay logged `authenticated … room=main` (app authed → stall is post-auth, e.g.
firehose backpressure from accumulated stale peers) or `warn phase=auth
handshake step failed, closing` (app auth timed out at 5s → the app's auth send
is being starved on the CI runner). Candidate fixes depend on which: tighten /
priority-send the app auth, or relax the relay handshake bound, or make the app
fail-fast on relay close instead of stalling 10s.

**Do NOT bump the e2e 10s timeouts to mask this** — that hides a real race.

## Lesson
The earlier "parallel-contamination flake" diagnosis was wrong; the
"divergence" diagnosis was right but stopped short of the mechanism. Hashing the
observed IDs against the `roomIdFor` formula turned a 1-day mystery into a
5-minute localization. **When two opaque IDs diverge, brute-force the derivation
inputs against the hash function.**
