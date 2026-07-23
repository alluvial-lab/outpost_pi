# Session note — 2026-07-23 — advisor review → substrate path → CI + e2e warmup

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## TL;DR

Started as an advisor/outside-review request post-0.2.0, ended with the
review's recommendations scoped into the substrate, the backlog groomed
(62 → 39 items), the CI safety net built and reviewed, and the v0.3.0
security arc fully designed. Next session's headline pickup:
**`implement-orchestrator feature-owner-message-e2e-authentication`** —
designed, 5 child stories, ready. All work is local commits on `main`,
**nothing pushed** (CI lanes go live on first push — `ci.yml` self-triggers
all lanes, so the push is their first live verification).

## What happened, in order

### 1. Advisor review of the repo (post-0.2.0)

Verified against live code, not just docs. Top findings:
- 0.2.0 genuinely paid down the repo-eval's #1 debt (generated protocol
  SSOT, `index.ts` 4214→2928 LOC); CI/CD remained the weakest dimension.
- **Stale High-severity backlog items** corrupting signal (signing-oracle
  item was fixed by the 0.1.0 domain separation — code-verified).
- The one serious open security item: unsigned app↔Pi owner data plane
  (relay can read/forge owner messages).
- Session-replacement path had no e2e coverage (the post-0.2.0 bug class).

### 2. Scoped the recommendations (operator-confirmed)

- `feature-ci-verification-matrix` (from `workflow-ci-dependency-audit-gates`)
- `feature-owner-message-e2e-authentication` (from
  `gate-security-relay-owner-messages-unsigned`, keeps gate evidence)
  — **strategic decision locked: fix, paired wire change targeting v0.3.0**
- `story-e2e-session-replacement-case` (depends_on the wake-confirmation
  feature, done)
- Parked: `idea-site-test-baseline`, `idea-cockpit-viewmodel-split`.

### 3. Groom (all dispositions operator-confirmed)

- F1 archived (signing-oracle, superseded, code-verified).
- F2 fixed inline: 4 doc-drift edits grounded in live code
  (formal-rigor mailbox boundedness, AGENTS.md `to_room` shipped,
  SPEC/ARCHITECTURE structured-control truth). 3 items archived.
- F3–F5: 15 cruft/lifecycle findings merged into 3 backlog items
  (`backlog-cruft-removal-batch`, `backlog-cockpit-file-watch-reliability`,
  `backlog-app-lifecycle-owned-operations`); absorbed bodies in `.work/archive/`.
- F6 → `feature-diagnostic-privacy-hardening` + 5 child stories (drafting).
- F7 → `feature-owner-identity-transition` + 2 child stories (drafting),
  `depends_on: feature-owner-message-e2e-authentication`.

### 4. Designed + implemented + reviewed `feature-ci-verification-matrix` → done

- `.github/workflows/ci.yml`: 6 path-gated lanes (protocol, pi-extension,
  rust matrix [relay, rp-s3], app + identity package, cockpit, site) behind
  `dorny/paths-filter`; workflow file self-triggers all lanes.
- `.github/workflows/deps-audit.yml`: weekly + lockfile-push, pnpm audit
  high+ ×3, cargo audit CLI ×2.
- `.github/dependabot.yml`: 9 entries (actions, npm ×3, cargo ×2, pub ×3).
- Cross-model review (`gpt-5.6-sol`) caught a real blocker:
  `rustsec/audit-check@v2` has no `path` input → switched to
  `taiki-e/install-action@cargo-audit` + per-crate CLI. Fixed, verified, done.
- **Operator follow-up**: mark lanes as required checks in branch protection
  (repo setting, can't be done in-repo).

### 5. Implemented `story-e2e-session-replacement-case` → done

- New `app/test/e2e/session_replacement_e2e_test.dart`; full suite 8/8 green
  + redaction canaries pass.
- **Harness limitation discovered (verified live)**: pi-host's stubbed
  `newSession` acks without rotating the SessionManager → no new session id
  in-harness; instant stub turns make the bug's timing symptom unobservable.
  Test gates on post-replacement *wipe* convergence + prompt confirm +
  exact-once instead. Documented in test doc-comment + story body.

## Designed and ready: `feature-owner-message-e2e-authentication`

Stage `implementing`, 5 child stories with depends_on chain:

1. `…-schema-handshake-frames` (no deps) — pair_request/pair_ok + `dh_pk`/`dh_sig`,
   codegen, **KAT vector** (cross-language AEAD/HKDF interop is the #1 risk)
2. `…-extension-secure-channel` (deps 1) — `@noble/curves`+`@noble/ciphers`,
   peers.json channel-key persistence (verify 0600), `SecurePeerChannel`
3. `…-app-secure-channel` (deps 1) — `cryptography` 2.9.0 (no new pub dep),
   FlutterSecureStorage, generated `PairRequest` DTO replaces handwritten map
4. `…-e2e-protected-channel` (deps 2,3) — 5 new e2e cases incl. relay-injected
   forgery
5. `…-docs-deploy-rollforward` (deps 2,3) — PROTOCOL.md drops "no E2E" claim,
   AGENTS.md paired-wire entry (app+extension hard cutover, re-pair required;
   **relay untouched** — protected frames ride inside `outer.ct`)

Crypto design (operator-confirmed): signed ephemeral X25519 ECDH inside the
existing pair handshake (app signs with Owner key, Pi signs with Pi key
verified against QR `epk` — relay-MITM-proof), HKDF-SHA256 directional keys
(salt = single-use token), XChaCha20-Poly1305, random 24B nonces + persisted
high-water seq for replay. Fail closed: no plaintext fallback, 5 consecutive
decrypt failures detaches, recovery = re-pair. Pre-E2E pairings must re-pair.

**Suggested review weight: `thorough`** (wire protocol + crypto + hard
cutover) — operator hasn't confirmed; note on the feature body if agreed.

Watch item: upstream `remote_pi` rolled back a libsodium E2E channel for
unknown reasons (evidence: `qr.ts` "after E2E rollback" comment). Design is
defensive about this (no renegotiation, re-pair recovery, KAT vectors).

## Queue after this session

- **implementing-ready**: the owner-channel feature (above);
  `feature-diagnostic-privacy-hardening`'s 5 stories are technically
  implementing but should wait for their parent's design (shared redaction
  policy is the deliverable).
- **drafting**: `feature-owner-identity-transition` (blocked on owner-channel),
  `feature-diagnostic-privacy-hardening`.
- **in-flight**: `epic-targeting-and-session-lifecycle-contracts` /
  `feature-reconnect-reproduction` (observability workstream, pre-existing).
- Backlog: 39 items, freshly groomed.
