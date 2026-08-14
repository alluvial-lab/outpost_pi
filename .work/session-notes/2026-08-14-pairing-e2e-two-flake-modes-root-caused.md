# 2026-08-14 — CI fully green: the pairing-e2e "flake" was two bugs, both root-caused

Fresh-context entry point: closes the arc started in
`2026-08-12-resume-parked-work.md` (red CI) and continued in
`2026-08-12-pairing-e2e-room-divergence-fix.md`. The full forensics live in
`backlog-pairing-e2e-flaky-auth-handshake-timeout.md` — read that for detail;
this note is the arc, the turns, and the lessons.

## TL;DR
The pairing-e2e "flake" that ate two days was **two independent bugs** stacked:
- **Mode A** (pairing silence: 10s/2min hangs) — double root startup per pi-host
  generation → two blind-minted identities → QR can reference the losing relay
  connection → pair_request swallowed tracelessly by its supersede-close.
- **Mode B** (pi-host wedge at generation ~10-11) — docker restart-policy
  **backoff** doubling on fast sub-10s test generations until it blew the
  tests' 45s `restartForIsolation` window.

Both mechanistically understood, deterministically fixed, validated by
**7 consecutive CI greens** (vs ~3-in-5 Mode-B rate pre-fix). All three
workflows green: `ci.yml`, `e2e-pairing`, `deps-audit`. CI is green for
*understood* reasons for the first time since the v0.4.0 push.

Also this session: deps-audit cleared (protocol fast-uri; site + pi-extension
overrides refreshed — the team's maintained overrides posture), a stale
`relay/Cargo.lock` refreshed, and my earlier "12 greens = flake subsided" call
corrected (it was a streak; the flake was real until 2026-08-14).

## The turning point: fresh eyes + complete logs
Days of dead ends shared one hidden flaw: **every relay log I analyzed came
from the non-blocking-writer era** — the writer that dropped log lines. The
entire "relay auth-handshake stall / task unpolled" theory rested on the
ABSENCE of log lines that were being dropped. Two prerequisites cracked it:
1. A **complete** post-revert failure log (the `c76bafa` run) showing the
   failing app connections DID authenticate — killing the old theory.
2. A **GLM-5.3 fresh-eyes deep-dive** (new capability this session) that
   re-derived the causal chain from scratch and connected fingerprints I'd
   seen but never linked: the **two cwd-lock files** (`e2e-agent` +
   `e2e-agent#2`) from day one, and the **two pi-host relay auths per
   restart** I kept waving off as "transport + mesh bridge".

The deep-dive also caught a blind spot in my own tooling: the failure-time
relay grep didn't match `dropping|disconnected|not found` — so the relay's
dest-drop warn had been invisible in every capture.

## Mode A — double root startup (the pairing silence)
`session_start` auto-start is fire-and-forget (`_startRootInBackground`) and
the e2e harness immediately invokes `/outpost-pi` again
(`e2e_pi_host_runtime.ts:156-157`). Both roots pass the "idle" guards
(`_state` flips only after the first relay connect resolves), double-join the
mesh, and — fatally — **both blind-mint a different file identity** on the
fresh HOME (`getOrCreateEd25519Keypair` was read-then-write). The QR references
the last-RECORDED key; the live relay connection belongs to the last-RESOLVING
start — two independent orderings. On disagreement the app's pair_request
targets the losing connection, whose unbind-then-close supersede
(`relay_transport.ts:514-516`) swallows frames with zero trace (the relay
counts them delivered during the close handshake).

Production-real: any FIRST-RUN machine (no identity file, headless/file path)
with two concurrent starters (auto-start vs typed `/outpost-pi`, daemon timer)
can double-mint and publish a QR referencing a dead identity.

Fix: `O_EXCL` ("wx") create-once mint (EEXIST loser re-reads, brief retry for
the winner-mid-write window) + `_startRelayViaTransport` single-flight. A
root-level single-flight was tried first and **REVERTED** (65b790e): it coupled
the harness's awaited root to the fire-and-forget background root, turning a
(then-unknown) background hang into a full pi-host wedge. Scope matters:
converge the racing *operations*, don't couple independent callers.

Fingerprints after fix: exactly ONE relay auth + ONE identity mint per
generation (was always two), confirmed via E2E_KEEP_STACK locally.

## Mode B — docker restart backoff (the generation-10 wedge)
Found by instrumentation this session added after Mode A's fix still failed
3-of-5 cycles: an entrypoint echo marker, a synchronous boot line, and a
failure-time `docker compose ps -a` + `docker inspect` dump.

The decisive capture: `RestartCount=10, ExitCode=0, OOMKilled=false`, last
process lifetime 3.5s, docker sitting in restart backoff **48 seconds**, and
the restarting processes never printing the entrypoint echo. Docker's
restart-policy backoff doubles per restart (100ms → 51s by #10) and only
resets after a ≥10s container lifetime. Fast pairing tests cycle generations
in 3-9s → backoff compounds → exceeds the tests' 45s window → every subsequent
test fails `restartForIsolation` ("Connection closed before full header" on
/status). Explains deterministically: why it always wedged at generation
10-11, why only the fast `pairing_failures` cluster tripped it (any single
>10s test resets the backoff), why CI (fast runner) hit it and the dev VM
(slow tests) never did.

Fix: the container never exits — the image CMD respawns the node process in a
shell loop (~200ms); restart policy removed from the compose. Process exit
remains the e2e's reset boundary.

## Lesson stack (ordered by how much they cost)
1. **Trust no absence-of-evidence from a lossy channel.** The non-blocking
   stdout writer dropped exactly the log lines my whole theory depended on.
   Before building causal theories on "line X never appeared", confirm the
   channel can't lose line X.
2. **Check your own tooling's blind spots.** The diagnostic grep pattern was
   itself a filter that hid `dropping`/`disconnected`. The observability
   layer is code too — audit it like code.
3. **"Intermittent" is often "two bugs with overlapping symptoms."** Mode A
   and Mode B both presented as "pairing-e2e red"; splitting them by failure
   signature (10s/2min pairing hang vs 45s generation-wait) was the unlock.
4. **A green streak is not a fix.** 12 greens seduced me into "subsided";
   a recurrence corrected it. Mechanistic fingerprints (auth-per-generation
   counts) are the durable validation.
5. **Fresh-eyes re-derivation pays.** GLM-5.3 connected the two-lock-file
   fingerprint from day one. When deep in a hole, dispatch a fresh context
   to re-derive the causal chain rather than incrementally patching a theory.
6. **Container restart policies have backoff semantics that compose badly
   with fast test cycles.** If a test harness restarts a container per test
   and tests are fast, respawn in-process instead.

## State left behind
- All three CI workflows green (`ci.yml`, `e2e-pairing`, `deps-audit`); 7
  consecutive pairing-e2e greens on the final code.
- Permanent forensics kept in `e2e/run-pairing.sh` (failure-gated, redaction-
  safe): relay grep incl. `dropping|disconnected|not found`, pi-host container
  state + `docker inspect` dump, boot line, respawn markers in the CMD.
- Optional follow-ups recorded in the backlog item: best-effort `pair_error`
  on the non-current ingress path (converts future silent drops into fast
  failures); a bounded timeout on `exchangePairingJson`'s bare `receive()`;
  the rare background-root hang (observed once, no longer fatal).
- Next active work per the resume note: canonical-transcript-timestamp-
  ownership arc (5 stories implementing), tiered-gate formalization eval.
