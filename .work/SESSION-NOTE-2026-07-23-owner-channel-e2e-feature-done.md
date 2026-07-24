# Session note — 2026-07-23 — owner-channel E2E feature DONE (implement-orchestrator + thorough review)

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## TL;DR

Picked up the previous session's headline (`implement-orchestrator
feature-owner-message-e2e-authentication`, "with thorough review") and ran it
to completion: **the feature and all 5 child stories are `done`** (30 local
commits on `main` since `b60d051`, nothing pushed). The app↔Pi owner channel
is now E2E-encrypted + authenticated end to end: signed ephemeral X25519 in
the pair handshake, `token_id` + `pair_mac` (the raw pair token NEVER crosses
the wire), HKDF directional keys, XChaCha20-Poly1305 sealed frames with
clear-header `seqLE64` replay protection, fail-closed everywhere, every queue
bounded under hostile ingress, seq state coherent across multi-room Pi
processes (machine lockfile + reserve-before-seal + locked recv CAS).
Thorough review converged at **pass 9**: 15 blockers fixed, 7 important
fixed, 3 important parked. Next pickup: **`/release-deploy` for the v0.3.0
paired cutover** (rebuild `dist/`, FULL pi restart — not `/reload` — then app
sideload; pre-E2E pairings must re-pair; relay untouched). AGENTS.md paired-
wire entry and `docs/release-uat.md`-adjacent deploy notes are already in place.

## What happened, in order

### Implementation (3 waves, 5 stories → done)

1. **Schema wave** (Terra/high, `9a9a1e7`): `dh_pk`/`dh_sig` landed
   schema-optional/behavior-required (orchestrator decision — keeps every
   consumer compiling at the wave boundary; handlers fail closed),
   `bad_dh_sig` error code, TS+Dart regen, deterministic KAT generator +
   vector (`protocol/fixtures/app-pi/owner-channel-kat.json`).
2. **Wire-contract correction before wave 2**: the extension worker caught a
   design flaw — `seq` was AEAD AAD but never transmitted, so replay
   protection was unimplementable across dropped frames. Orchestrator
   corrected the design in place to `0x01 || seqLE64 || nonce24 || ct` and
   regenerated the KAT (`d9b0d15`); both wave-2 workers implemented to it.
3. **Crypto waves** (Sol/high ×2 parallel, `af502dc` ext + `08ff447` app):
   `secure_channel.ts` / `secure_channel.dart`, key+seq persistence
   (`peers.json` 0600 verified; FlutterSecureStorage), signed handshake in
   `owner_multiplexer` / `pair_request_flow` (generated DTO killed the
   handwritten pair_request map), `SecurePeerChannel` adapters.
4. **E2E + docs wave** (`ab2fd46`, `58d32cd`): 5 new docker e2e cases
   (13/13 green), PROTOCOL.md/AGENTS.md/SPEC.md rolled forward + 2
   orchestrator drift fixes (`pi-extension/CLAUDE.md`, `relay/CLAUDE.md`).

### Thorough review (9 fresh-context cross-model Sol passes)

Converged per policy (pass 9 = zero receiver-confirmed material blockers).
Headline fixes beyond the original design:

- **P1**: malicious-relay pairing hijack (bearer token was relay-visible) →
  `token_id` + `pair_mac` redesign + adversarial e2e; send-seq
  persist-before-send; 5-failure contract REDESIGNED to detach + automatic
  same-key reattachment (strict quarantine was a one-shot relay DoS);
  `plaintext_post_key` audit false positive; app low-order X25519.
- **P2–P3**: re-pair key-overwrite race (storage mutation queue); bounded
  audit under flood; proof-holder token UX (`token_expired`/`token_consumed`
  back, `token_unknown` stays non-oracular); key-replacement separation;
  token timing equalization.
- **P4–P5**: dispatch FIFO was feature-introduced (a pass-3 park I had to
  reverse on blame evidence) → bounded 256/8 MiB + control caps + generation
  disposal; mesh-restore revocation race; outbound persistence FIFO bounded.
- **P6**: overflow-reattach seq duplication → per-peer drain gates; app
  queue bounds (symmetric with extension).
- **P7–P8**: multi-room processes share `peers.json` — seq state went
  cross-process (machine lockfile, reserve-before-seal, locked recv
  compare-and-advance `accepted`/`replay`/`stale_generation`); stale-lock
  reclaim ABA (owner-token fencing + exclusive reclaim marker).

### Parked (backlog, with rationale)

- `backlog-relay-transport-stale-generation-active-dispatch.md`
- `backlog-peers-lock-restore-collision-safety.md`
- (one pass-3 park was reversed and fixed in pass 4 — audit trail in git)

## Final state

- `feature-owner-message-e2e-authentication` + 5 stories: **done**
  (`647ac6d`). Feature body carries the full implementation + 9-pass review
  record.
- Verification (orchestrator-run): extension tsc + 928 vitest + build; app
  analyze + 814 unit tests; protocol checks; docker e2e **14/14 + 20
  redaction canaries**.
- Working tree clean; 30 local commits, **nothing pushed**.
- NOT yet live: the running pi session still has the old extension loaded —
  the cutover needs `corepack pnpm build` in `pi-extension/` + full pi
  restart, then app sideload, then re-pair (per AGENTS.md paired-wire entry).

## Next session pickups

1. `/release-deploy` v0.3.0 arc (gates: security, tests, cruft, docs,
   patterns, refactor per CONVENTIONS.md; UAT manual checkpoint; operator
   re-pair after cutover).
2. The 2 new parked backlog items (above) when hardening budget allows.
3. Cross-PC Pi↔Pi E2E remains explicitly out of scope (future item) —
   PROTOCOL.md keeps that statement true.
