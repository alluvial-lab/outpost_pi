---
id: feature-owner-message-e2e-authentication
kind: feature
stage: done
tags: [security, app, pi-extension, relay, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-23
---

# End-to-end authentication for relay-routed owner messages

## Brief

The app↔Pi owner data plane wraps JSON as base64 only. Once an owner is
paired, the Pi accepts messages routed with that owner's `peer` id and
dispatches control actions such as `user_message`, `cancel`, `session_new`,
`model_set`, and `thinking_set`. A compromised or malicious relay can
read/alter plaintext frames or inject a forged `ct` under a known owner peer
id, because the Pi verifies relay routing but not end-to-end message
integrity from the owner key.

Add end-to-end integrity for owner data-plane frames: derive a
per-pairing/session key or sign canonical inner messages with
domain-separated context, verify before dispatch, and reject
unsigned/failed frames. Prefer restoring an authenticated encrypted channel
if transcript/tool data should remain hidden from the relay.

## Strategic decisions

- **Fix vs accepted-risk**: **fix** — operator-confirmed 2026-07-23. Build the
  E2E-authenticated owner channel as a paired wire change targeting v0.3.0.
  The fix must be version-paired across app + extension (and relay if
  envelope shape changes), documented in AGENTS.md "Paired wire changes" and
  shipped with a hard-cutover deploy plan like the 0.1.0 rebrand pairs.

## Severity
High (gate-security finding, 2026-07-01; confirmed still live in the
2026-07-23 advisor review)

## Domain
Authentication & Authorization / Cryptography / Data Protection

## Location
`pi-extension/src/transport/peer_channel.ts:72`

## Evidence
```ts
const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
const outer: OuterEnvelope = {
  peer: this.remotePeerId,
  room: APP_DESTINATION_ROOM,
  ct,
};
```

Additional ingress evidence: `pi-extension/src/extension/owner_multiplexer.ts:244`
trusts `outer.peer` for known-owner reattachment, and
`pi-extension/src/transport/peer_channel.ts:111` decodes `outer.ct` without a
message signature or MAC.

## Simplification opportunity

The pairing flow already establishes an ephemeral app key per session; the
design pass should check whether that channel can be extended into the
steady-state data plane rather than introducing a second key-agreement path.
PROTOCOL.md's "relay can see the current envelope contents" assertion rolls
forward in place if encryption lands.

## Origin

Promoted from `.work/backlog/gate-security-relay-owner-messages-unsigned.md`
per advisor review 2026-07-23, recommendation #3.

## Design decisions

- **Protection scope**: full E2E (XChaCha20-Poly1305 encryption + integrity),
  single cutover — operator-confirmed 2026-07-23. Integrity-only signatures
  rejected: leaves relay readability as a second wire change later.
- **Key establishment**: signed ephemeral X25519 ECDH inside the existing
  `pair_request`/`pair_ok` handshake — operator-confirmed 2026-07-23. QR-carried
  channel key rejected: QR capture would yield the long-term key, no PFS.
- **Cutover policy**: hard cutover, app + extension paired only; relay
  untouched (`ct` stays opaque base64). Consistent with the 0.1.0 paired-wire
  precedent. Pre-E2E pairings must re-pair.
- **Cross-PC Pi↔Pi E2E**: out of scope — the owner channel is the High finding;
  Pi↔Pi is a separate future item.
- **Key resumption**: derived channel key persisted per-pairing on both sides;
  no re-handshake on reconnect; re-pair is the recovery path. Defensive
  posture because the upstream E2E rollback rationale is unknown.
- **Prior art risk**: upstream `remote_pi` had a libsodium E2E channel that
  was rolled back (evidence: `qr.ts` comment "only peer ID after E2E
  rollback"); rationale unknown. Mitigation: no session renegotiation
  complexity, fail-closed everywhere, known-answer cross-language vectors.

## Architectural choice

**Protected adapters behind the existing `PeerChannel` port on both sides.**
`PlainPeerChannel` (extension: `pi-extension/src/transport/peer_channel.ts`;
app: `app/lib/data/transport/peer_channel.dart`) is the plaintext adapter
used only for the pre-key `pair_request`/`pair_ok` exchange. A new
`SecurePeerChannel` adapter seals/opens the inner payload; dispatch,
session routing, sync, and transcript logic are untouched. Key material
comes from a per-pairing `ChannelKeyStore`.

Rejected:
- **Encrypt at the WS transport layer** (`WsTransport`/`RelayClient`): wrong
  seam — that layer also carries pre-key pair frames and relay control;
  blurs relay-frame vs payload concerns and forces the relay path to know
  about key state.
- **Integrity-only signatures inside existing frames**: rejected by decision
  above (no confidentiality, second cutover later).

## Cryptographic design

Suite id (domain separator, matches project `outpost-pi-*-v1` convention):

```
SUITE = "outpost-pi-owner-channel-v1"
```

**Handshake** (rides the existing plaintext pair exchange; QR unchanged):

1. App generates an ephemeral X25519 keypair per pairing attempt. Extends
   `pair_request` with `token_id` (base64 SHA-256(token)[:16] — public
   locator), `pair_mac` (base64 HMAC-SHA256 keyed by the RAW token over
   `SUITE ++ "\npair\n" ++ tokenIdBytes ++ ownerEdPk ++ appDhPk ++ piEdPk`),
   `dh_pk` (base64, 32B) and `dh_sig` (base64 Ed25519 signature by Owner-sk
   over: `SUITE ++ "\napp\n" ++ tokenBytes ++ appDhPk ++ piEdPk`). The raw
   token NEVER crosses the wire: a relay observing the exchange cannot race
   its own pairing under an attacker Owner key (review pass-1 correction —
   the original raw-token design left the bearer token relay-visible).
   `piEdPk` is the QR-carried Pi pubkey — out-of-band authentic; binding it
   prevents a malicious relay from redirecting the pairing.
2. Extension receives `pair_request`; relay-authenticated `outer.peer` is
   the Owner pubkey. Resolves the token by `token_id` and verifies
   `pair_mac` (constant-time) FIRST — failure is `pair_error
   `token_unknown`, consumes nothing, reveals no stage detail. Then verifies
   `dh_sig` against the Owner pubkey. On failure: `pair_error`
   (`bad_dh_sig`), no state.
3. Extension generates its ephemeral X25519 keypair, derives keys (below),
   persists the channel record, then extends `pair_ok` with `dh_pk` and
   `dh_sig` (Pi-sk over:
   `SUITE ++ "\npi\n" ++ tokenBytes ++ appDhPk ++ piDhPk ++ ownerEdPk`).
4. App verifies `dh_sig` against the QR `epk`. On failure: abort pairing,
   persist nothing. On success: derives keys and persists.

**Key derivation** (RFC 5869 HKDF-SHA256):

```
shared      = X25519(appDhSk, piDhPk) = X25519(piDhSk, appDhPk)
k_app_to_pi = HKDF(shared, salt=tokenBytes, info=SUITE ++ "\napp->pi")
k_pi_to_app = HKDF(shared, salt=tokenBytes, info=SUITE ++ "\npi->app")
```

Two directional keys prevent reflection. Token as salt binds the channel to
this pairing session.

**Protected frame** (replaces base64(JSON) inside `outer.ct`):

```
outer.ct = base64( 0x01 || seqLE64(8B) || nonce(24B random) || XChaCha20-Poly1305(key, nonce, aad=seqLE64, plaintext=jsonUtf8) )
```

- Random 192-bit nonces — collision-safe, no counter state needed for nonce
  uniqueness across restarts.
- `seq` is a per-direction uint64 little-endian counter, persisted on both
  sides as a high-water mark; receiver rejects `seq <= lastSeen` (replay)
  and AEAD failures. The seq is transmitted in the clear frame header AND
  bound as AEAD associated data — an AAD-only seq is never received, so the
  high-water check would be unimplementable across dropped frames (corrected
  during implementation, wave 2 discovery). WS ordering per connection is
  FIFO; the persisted high-water survives reconnect.

**Enforcement (fail closed)**:
- Plaintext `ct` is accepted only when the inner message is `pair_request`
  AND the peer record has no channel key. All other plaintext → drop +
  audit log (`audit.jsonl`).
- Decrypt/replay failure → drop + audit; N consecutive failures (5) →
  detach the channel subscription; the NEXT frame from the keyed owner
  reattaches with the same persisted channel keys (automatic same-key
  recovery). AEAD remains the security boundary — forged frames never
  dispatch regardless. Strict quarantine-until-re-pair was REJECTED at
  review pass 1: five garbage frames from a malicious relay would then
  permanently kill a pairing (one-shot DoS), buying nothing the relay
  cannot already achieve by dropping frames. Re-pair remains the recovery
  path for key loss / half-established pairings, not transient failures.
  No plaintext fallback, ever.
- Post-cutover, pre-E2E pairings have no channel key → their frames are
  dropped + audited; operator instruction is re-pair (documented in
  AGENTS.md paired-wire notes + release UAT).

## Implementation Units

### Unit 1: Handshake schema + codegen
**File**: `protocol/schema/app-pi-client.schema.json` (`pair_request` +
`dh_pk`, `dh_sig`), `protocol/schema/app-pi-server.schema.json` (`pair_ok`
+ `dh_pk`, `dh_sig`); regenerate TS + Dart; extend fixtures.
**Story**: `feature-owner-message-e2e-authentication-schema-handshake-frames`

**Acceptance Criteria**:
- [ ] Generated `PairRequest`/`PairOk` DTOs carry `dhPk`/`dhSig` in TS + Dart
- [ ] Fixture round-trips pass in `protocol/` checks

### Unit 2: Extension channel crypto
**File**: `pi-extension/src/transport/secure_channel.ts` (new)
**Story**: `feature-owner-message-e2e-authentication-extension-secure-channel`

```ts
export const OWNER_CHANNEL_SUITE = "outpost-pi-owner-channel-v1";
export interface DirectionalKeys { send: Uint8Array; recv: Uint8Array } // 32B
export function generateX25519Keypair(): { pk: Uint8Array; sk: Uint8Array };
export function x25519Shared(sk: Uint8Array, pk: Uint8Array): Uint8Array;
export function deriveDirectionalKeys(shared: Uint8Array, token: string, side: "app" | "pi"): DirectionalKeys;
export function appTranscript(token: string, appDhPk: Uint8Array, piEdPk: Uint8Array): Uint8Array;
export function piTranscript(token: string, appDhPk: Uint8Array, piDhPk: Uint8Array, ownerEdPk: Uint8Array): Uint8Array;
export function seal(key: Uint8Array, seq: bigint, json: string): Uint8Array; // 0x01||seqLE64||nonce24||ct
export function open(key: Uint8Array, frame: Uint8Array, lastSeq: bigint): { seq: bigint; json: string } | null;
```

Deps: add `@noble/curves` (x25519) + `@noble/ciphers` (xchacha20-poly1305);
HKDF via Node `crypto.hkdfSync`; Ed25519 via existing `pairing/crypto.ts`.

**Implementation Notes**:
- Independent X25519 keypairs — NO Ed25519→X25519 birational conversion
  (avoids the conversion pitfall class entirely).
- `open` enforces replay (`seq > lastSeq`) before returning.

**Acceptance Criteria**:
- [ ] Known-answer vector from `protocol/fixtures/` seals/opens identically
- [ ] Tampered frame → `null`; replayed seq → `null`
- [ ] Transcript verification rejects wrong signer / wrong binding fields

### Unit 3: App channel crypto
**File**: `app/lib/data/transport/secure_channel.dart` (new)
**Story**: `feature-owner-message-e2e-authentication-app-secure-channel`

Mirror of Unit 2 with the installed `cryptography` 2.9.0 package (`X25519()`,
`Ed25519().sign`, `Hkdf`/`Hmac.sha256()`, XChaCha20-Poly1305 AEAD). No new
pub dependency.

**Acceptance Criteria**:
- [ ] Same known-answer vector passes (interop proof, not just round-trip)
- [ ] Tamper/replay rejection mirrors extension behavior

### Unit 4: Key persistence
**Files**: `pi-extension/src/pairing/storage.ts` (`PeerRecord` +
`channel_key`, `send_seq`, `recv_seq`; enforce `peers.json` `0600`),
`app/lib/pairing/storage.dart` (`PeerRecord` + channel key in
FlutterSecureStorage, seq counters).
**Stories**: folded into Units 2/3 stories (same write ownership).

**Acceptance Criteria**:
- [ ] Channel key + seq survive process/app restart
- [ ] `peers.json` is written `0600` (verified, not assumed)

### Unit 5: Handshake wiring (extension)
**File**: `pi-extension/src/extension/owner_multiplexer.ts`
(`handlePairRequest`: verify `dh_sig` vs `outer.peer`, generate Pi DH,
derive + persist, emit extended `pair_ok`; known-owner reattachment
requires an established channel key)
**Story**: `feature-owner-message-e2e-authentication-extension-secure-channel`

**Acceptance Criteria**:
- [ ] Bad `dh_sig` → `pair_error bad_dh_sig`, no peer record written
- [ ] Successful pairing stores channel key before `pair_ok` is sent

### Unit 6: Handshake wiring (app)
**File**: `app/lib/pairing/pair_request_flow.dart` (generate ephemeral DH,
sign with Owner key, send via generated `PairRequest` DTO — replaces the
handwritten map; verify `pair_ok.dh_sig` against QR `epk`, derive + persist)
**Story**: `feature-owner-message-e2e-authentication-app-secure-channel`

**Acceptance Criteria**:
- [ ] Forged `pair_ok` (bad Pi sig) aborts pairing, nothing persisted
- [ ] Generated `PairRequest` DTO replaces the handwritten map

### Unit 7: SecurePeerChannel adapters
**Files**: `pi-extension/src/transport/peer_channel.ts` (`SecurePeerChannel`
implements `PeerChannel`; `PlainPeerChannel` retained for pair exchange
only), `app/lib/data/transport/peer_channel.dart` (same), wiring in
`pi-extension/src/extension/owner_multiplexer.ts` attach path and
`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart` adopt path.
**Stories**: folded into Units 2/3 stories.

**Acceptance Criteria**:
- [ ] Post-pairing frames are sealed end-to-end; sync/hydration unaffected
- [ ] Plaintext post-key frame → dropped + audit-logged
- [ ] 5 consecutive decrypt failures → channel detached

### Unit 8: Docs + deploy roll-forward
**Files**: `PROTOCOL.md` (App-key row → real design; "no E2E" statements;
relay-operator threat row), `AGENTS.md` (paired-wire entry + re-pair
cutover note), `docs/SPEC.md` (data-plane description), `qr.ts` stale
"E2E rollback" comment.
**Story**: `feature-owner-message-e2e-authentication-docs-deploy-rollforward`

**Acceptance Criteria**:
- [ ] PROTOCOL.md no longer claims "no E2E" for the owner channel
- [ ] AGENTS.md documents the hard cutover + deploy order (extension
  restart → app sideload) per the paired-wire section pattern

## Implementation Order

1. `…-schema-handshake-frames` (Unit 1)
2. `…-extension-secure-channel` (Units 2, 4-ext, 5, 7-ext) — depends_on 1
3. `…-app-secure-channel` (Units 3, 4-app, 6, 7-app) — depends_on 1
4. `…-e2e-protected-channel` — depends_on 2, 3
5. `…-docs-deploy-rollforward` — depends_on 2, 3

Stories 2 and 3 are independent given 1 and can proceed in either order
(one feature worker baseline; the dependency is declared for correctness,
not parallelism).

## Simplification

- App `pair_request_flow.dart` handwritten `pair_request` map → generated
  `PairRequest` DTO (kills a hand-mirrored island the explorer flagged).
- PROTOCOL.md's aspirational "App-key" row replaced with the real design
  (removes a false doc claim).
- `qr.ts` "after E2E rollback" comment replaced with current-state text.
- Extension gains app-side inbound sender-pubkey authenticity for free:
  AEAD key possession proves the peer; the app's room-only demux check
  (`ws_transport.dart:430-444`) becomes defense-in-depth, not the boundary.

## Testing

- **Known-answer vector** in `protocol/fixtures/` (fixed DH keys, token,
  seq, plaintext → exact sealed frame bytes): the #1 risk is cross-language
  AEAD/HKDF interop; both sides must reproduce the vector byte-for-byte.
- **Interface tests**: handshake accept/reject at
  `owner_multiplexer.handlePairRequest` and `pair_request_flow` (bad sig,
  swapped share, wrong binding).
- **Regression**: existing e2e pairing cases exercise the new handshake
  automatically (they pair through the real flow).
- **New e2e cases** (story 4): pairing establishes a channel; forged `ct`
  injected via the relay is dropped; tampered `dh_sig` rejected; plaintext
  post-key rejected; sealed round-trip survives relay reconnect.
- **No per-branch unit nets** beyond the crypto module — the e2e layer is
  the contract.

## Risks

- **Half-established pairing** (one side persisted, other didn't; e.g.
  `pair_ok` lost after token consumed): token is single-use → re-pair via
  new QR. Accepted: QR rotation exists; fail-closed beats desync recovery
  logic (this class of complexity is the suspected upstream rollback cause).
- **Cross-language AEAD/HKDF interop bug**: mitigated by the known-answer
  vector tested on both sides before e2e runs.
- **Seq desync across restores**: persisted high-water both sides;
  strictly increasing sender seq; worst case is dropped frames → app
  re-syncs via `session_sync` (existing recovery path).
- **Multi-device owner**: each device pairs separately → per-pairing
  channel keys and seq counters; no shared state. Verified as compatible
  with `peers.json` N-owner posture.
- **Relay metadata still visible**: room names, cwd, model, timing remain
  relay-visible (routing needs them). Out of scope; PROTOCOL.md keeps that
  statement.

## Implementation record (implement-orchestrator run, 2026-07-23)

**Scope resolution**: feature + all 5 child stories at `implementing`;
graph validated acyclic with no external dependencies.

**Topology** (justified split of a large cross-subproject feature into
dependency-layered waves with disjoint write sets; per-worker briefs carried
the full design context):

- Wave 1: `…-schema-handshake-frames` — Terra/high. Schema dh fields landed
  schema-optional/behavior-required (orchestrator decision: keeps every
  consumer compiling at the wave boundary; handlers fail closed). KAT
  generator + vector committed. Green: protocol checks, extension tsc+884
  tests, app codegen tests + analyze. Commit `9a9a1e7`.
- **Wave-2 design correction**: the extension worker caught a wire-contract
  flaw before writing code — the original frame format made `seq` AEAD AAD
  without transmitting it, leaving the replay high-water unimplementable
  across dropped frames. Orchestrator corrected the design in place to
  `0x01 || seqLE64(8B) || nonce24 || ct` (seq clear-header + AAD) and
  regenerated the KAT (commit `d9b0d15`); both wave-2 workers implemented to
  the corrected contract.
- Wave 2 (parallel, disjoint write sets): `…-extension-secure-channel`
  (Sol/high, commit `af502dc`) and `…-app-secure-channel` (Sol/high, commit
  `08ff447`). Both reproduce the corrected KAT byte-for-byte. Green:
  extension tsc + 897 tests + build; app analyze + 799 unit tests.
- Wave 3 (parallel): `…-e2e-protected-channel` (Sol/high, commit `ab2fd46`)
  — 5 new e2e cases, full docker stack 13/13 green with redaction canaries,
  existing 8 cases untouched; and `…-docs-deploy-rollforward`
  (Terra/medium, commits `58d32cd` + orchestrator drift follow-ups
  `6f19f64`/`7cf17ce` for stale no-E2E assertions in `pi-extension/CLAUDE.md`
  and `relay/CLAUDE.md`).

**Effective review_weight**: `thorough` (explicit caller override) —
iterative fresh-context cross-model review (openai-codex/gpt-5.6-sol)
until no receiver-confirmed material current-cycle blockers.

**Open question handed to review**: the e2e worker observed a baseline
`plaintext_post_key` audit event on every successful pairing (tests assert
post-injection deltas instead). Hypotheses: (a) an app-side frame sent
plaintext in the pair→adopt window, or (b) an extension-side false positive
from fanout subscription timing in `handlePairRequest`/`attach`. App adopt
path inspected — `SecurePeerChannel` is adopted before any post-pair frame
is sent, favoring (b). Review adjudicates materiality and the fix.

## Review record (thorough, 9 passes, 2026-07-23)

Effective `review_weight: thorough` (explicit caller override). Reviewer:
fresh-context cross-model `openai-codex/gpt-5.6-sol` per pass (cross-class
vs the umans orchestrator), each pass a fresh context. Receiver adjudication
by the orchestrator against repository context.

- **Pass 1** (3 blockers confirmed, 2 important accepted): (B1) raw bearer
  token in `pair_request` let a malicious relay race a pairing under its own
  Owner key → redesigned to `token_id` + `pair_mac` (HMAC keyed by the raw
  token; raw token never crosses the wire; contract commit `9eab8f6`,
  extension `7dd5834`, app+e2e `58f1459` incl. adversarial
  relay-substitution e2e). (B2) extension exposed frames before send-seq was
  durable → serialized persist-then-send. (B3) "5 failures → re-pair
  required" unenforced → REDESIGNED to detach + automatic same-key
  reattachment (strict quarantine rejected as one-shot relay DoS; docs
  aligned `f59367f`). (I1) baseline `plaintext_post_key` false positive →
  consumed-boolean propagated (hypothesis (b) confirmed). (I2) app accepted
  low-order X25519 → all-zero shared-secret rejection + vectors.
- **Pass 2** (2 blockers confirmed, 2 important): (B4) stale app channel
  could overwrite re-paired keys → storage-owned mutation queue (`5306f2c`).
  (B5) unbounded audit growth under hostile ingress → counted buckets,
  capped queues, 256 KiB rotation (`bc236a1`). (I3) actionable
  `token_expired`/`token_consumed` unreachable → restored for valid
  proof-holders, `token_unknown` stays non-oracular. (I4) `relay/CLAUDE.md`
  intro contradiction → fixed inline (`2e113a6`).
- **Pass 3** (1 blocker confirmed, 1 parked, 1 important fixed): (B6) stale
  FULL-RECORD `savePeer` writes could restore superseded keys / recreate
  deleted peers → pairing-privileged key-replacement write, metadata writes
  key-preserving (`c445313`). (I5) token-lookup timing distinction →
  fixed-width constant-time locator + dummy verify (`7068183`). Parked:
  relay dispatch FIFO backpressure (initially misjudged pre-existing).
- **Pass 4** (2 blockers confirmed): (B7) the pass-3 FIFO park was WRONG —
  blame showed `dispatchTail` was feature-introduced → unparked and fixed:
  256-frame/8 MiB data cap, drop-new + coalesced audit (`377c55d`). (B8)
  mesh conflict-restore could undo a concurrent revocation → revision
  predicate moved inside the serialized storage op (`fc1750f`).
- **Pass 5** (2 blockers confirmed, 1 important fixed): (B9) cap-exempt
  control frames + stale reconnect generations re-opened unbounded
  retention → per-class control caps + generation disposal. (B10)
  SecurePeerChannel outbound persistence FIFO unbounded → 512-frame/16 MiB
  cap, overflow → audit + detach (`32eac07`). (I6) stale libsodium guidance
  in `app/CLAUDE.md` → `package:cryptography` canonical (`2331f2b`).
- **Pass 6** (2 blockers confirmed, 1 parked): (B11) overflow-detach +
  immediate reattach could duplicate/regress outbound seq → per-peer drain
  gates + max-merged seq persistence (`c7bed0a`). (B12) app-side unbounded
  `_sendTail`/`_MsgQueue` → symmetric caps + control bypass + close-signal
  preemption (`c6f7619`). Parked: dead-generation single-frame retention
  (`.work/backlog/backlog-relay-transport-stale-generation-active-dispatch.md`).
- **Pass 7** (1 blocker confirmed): (B13) multi-process seq state incoherent
  across room processes sharing `peers.json` (documented multi-room
  topology; hot per-frame writes made a cold race hot; durable high-water
  regression could reopen the replay window) → machine-wide lockfile +
  reserve-before-seal + locked recv max-merge (`0cc2d2d`).
- **Pass 8** (2 blockers confirmed): (B14) recv gated on LOCAL high-water →
  relay replays dispatched in multi-room → authoritative locked
  compare-and-advance (`accepted`/`replay`/`stale_generation`, key-generation
  keyed). (B15) stale-lock reclaim ABA → owner-token release fencing +
  exclusive reclaim marker + post-rename verification with restore
  (`95603ad`).
- **Pass 9** (verdict: ready): all pass-8 fixes confirmed with evidence; no
  material current-cycle blockers. One compound hardening finding parked:
  `.work/backlog/backlog-peers-lock-restore-collision-safety.md`.

**Closure**: converged at pass 9 with zero receiver-confirmed material
current-cycle blockers (thorough policy). Totals: 15 blockers fixed, 7
important fixed, 3 important parked with rationale, across 6 implementation
waves + 8 review-fix waves. Final integrated verification: extension
tsc + 928 vitest + build green; app analyze + 814 unit tests green; protocol
fixture/codegen checks green; docker e2e 14/14 + 20 redaction canaries green
(orchestrator-run).

**Integrated verification at feature roll-up**: pi-extension `tsc --noEmit`
+ 897 vitest + `tsc` build green; app `flutter analyze` + 799 unit tests
green; protocol fixture + codegen checks green; e2e docker stack 13/13
green (worker-run, `OUTPOST_PI_E2E_RELAY_IMAGE=outpost-pi-relay:0.1.0`).
