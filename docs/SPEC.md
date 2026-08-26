# Outpost-Pi — Specification

Technical boundaries, hard constraints, external interfaces, and the trust
model. Current truth, not history. Cross-check any version-sensitive fact
against the package files in the relevant subproject before relying on it.

## Stack

| Component | Language / runtime | Entry manifest | Builds to |
|---|---|---|---|
| `pi-extension/` | Node.js + TypeScript (ESM) | `pi-extension/package.json` | `dist/` — Pi extension + `outpost-pi` + `pi-supervisord` CLIs |
| `app/` | Flutter / Dart (mobile) | `app/pubspec.yaml` | Android APK (primary); iOS buildable |
| `relay/` | Rust (edition 2024), axum 0.7, tokio, rusqlite | `relay/Cargo.toml` | single Rust binary |
| `cockpit/` | Flutter / Dart (desktop) | `cockpit/pubspec.yaml` | macOS / Windows / Linux desktop |
| `site/` | Next.js (App Router) + React + Tailwind | `site/package.json` | static / standalone Docker |
| `rp-s3/` | Rust + axum (download server) | `rp-s3/Cargo.toml` | dormant download-server implementation; not currently deployed |

Key dependencies: Pi SDK (`@earendil-works/pi-coding-agent`) consumed by the
extension; `ws` (WebSocket) in the extension; `@napi-rs/keyring` for Pi-key
storage; `ed25519-dalek` and `sha2` in Rust; `cryptography` (dint.dev) for
Ed25519 in the app; Hive for local cache in Flutter; `flutter_modular` +
`shadcn_flutter` in cockpit.

## Hard constraints

- **Pi-only.** No abstraction layer for other coding agents. The extension
  consumes the Pi SDK directly.
- **One Pi-key per PC.** Hardware change = re-pairing. There is no Pi-key
  migration between machines; the Owner-key (mobile, synced via system
  Keychain) compensates.
- **Ed25519 identities.** Owner-key signs `mesh_versions`; Pi-key
  authenticates to the relay and signs cross-PC envelopes. Each pairing also
  uses an ephemeral X25519 App-key for the owner-channel handshake.
- **Relay never decides membership.** It forwards between Pi-siblings of the
  same Owner (verified via Owner signature on `mesh_versions`) and verifies
  signatures, but it never adjudicates who is in the mesh — the Owner does.
- **App ↔ Pi owner-channel E2E.** Pairing uses signed ephemeral X25519 ECDH
  under `outpost-pi-owner-channel-v1`; HKDF-SHA256 derives directional keys
  salted by the pair token. Post-pairing `outer.ct` is a sealed
  XChaCha20-Poly1305 frame with a random 24-byte nonce and persisted `seqLE64`
  replay protection, so the relay cannot read or alter owner-channel payloads.
  Cross-PC Pi↔Pi traffic remains relay-mediated and is not E2E-protected.
- **Bounded offline replay for known app peers.** When the relay marks an
  attached app peer offline, the extension keeps a per-peer, in-memory outbound
  buffer for the active turn and most recently completed turn, subject to frame
  and payload caps, then flushes it best-effort when that peer returns online.
  The buffer is lost on extension restart and is neither a protocol guarantee
  nor a durable message queue. Unobserved app disconnects and cross-PC relay
  targets have no such queue and report offline normally (`transport_error:
  offline` for cross-PC relay forwarding).
- **Durable app-owned owner-prompt recovery.** Before sending a
  `user_message`, the app persists its stable id and payload in an encrypted,
  room-scoped outbox. Recovery waits for authoritative live-room and canonical
  session identity, retargets durably, and removes an entry only after a
  matching-session confirmation is recorded. An extension restart fence emits
  `delivery_retry` before SDK handoff. This app↔extension paired contract is
  at-least-once, not exactly-once; the relay remains opaque and has no queue.
- **Cross-PC is relay-mediated.** Direct PC-to-PC (WebRTC/QUIC) is long-term
  roadmap; the relay becomes the fallback then.

## External interfaces

### Wire protocol (the single source of truth — generated from one schema)

The wire is the contract that every surface speaks. It is defined once in a
canonical JSON Schema and projected into each language by the generated-
protocol codegen:

- **TS** — `pi-extension/src/protocol/generated/protocol.generated.ts`
  (unions, validators, `decodeClient`/`decodeServer`, type-set registries
  `clientTypes`/`serverTypes`/`sessionScopedClientTypes`/
  `sessionScopedServerTypes`/`relayControlTypes`/`crossPcTypes`).
  `types.ts` is now a narrow re-export of these; `codec.ts` dispatches over
  the generated helpers.
- **Dart** — `app/lib/protocol/generated/protocol.g.dart` (sealed classes +
  `fromJson`) and `app/lib/protocol/generated/relay_frames.g.dart` (generated
  relay control/presence/rooms DTOs). `control_frames.dart` is an app-domain
  adapter over those generated relay DTOs, not a competing wire contract.
- **Rust** — `relay/src/protocol/generated/` (serde structs for the relay
  outer envelope, cross-PC frames, and room metadata).
- **Cockpit↔pi control RPC** — folded into the generated schema
  (`cockpit-control-rpc`), retiring the former private NUL-prefix string RPC.

Treat the schema (`protocol/schema/`) as the source of truth; the generated
artifacts are the cross-language contract test. Any genuinely hand-maintained
wire island must document its durable reason for remaining outside the schema.

### Transports

1. **App ↔ pi-extension** — WebSocket over TLS (relay-mediated) carrying
   newline-delimited JSON `ClientMessage` / `ServerMessage`. After signed-DH
   pairing, `outer.ct` is an E2E-encrypted and authenticated sealed frame;
   only the pre-key pairing exchange remains plaintext inside TLS. Chat-bearing
   `ServerMessage`s (`user_message`, `agent_chunk`, `agent_done`,
   `session_history`, tool surfaces) carry a canonical `session_id`
   (endpoint-owned, opaque to the relay); the app's `session_gate.dart`
   rejects missing/foreign session IDs before mutation.
2. **Cross-PC pi-to-pi** — relay `pi_envelope` / `pi_envelope_in` frames
   wrapping the generic agent envelope `{from, to, id, re, body}`. The relay
   forwards them without parsing their bodies, but this traffic is not
   E2E-protected.
3. **Cockpit ↔ pi-extension** — Pi custom events carrying structured
   `outpost_pi_control` JSON envelopes (the active transport; separate from
   the relay). The NUL-prefix string form (`\x00outpost-pi-ctrl:`) survives
   only as an extension-side compatibility decoder — Cockpit never emits it.
4. **Local agent mesh** — Unix Domain Socket broker per PC; local peers
   exchange the same `{from, to, id, re, body}` envelope without crossing the
   relay.

### Identity and trust

| Key | Algorithm | Where it lives | Who creates it | Used for |
|---|---|---|---|---|
| Owner-key | Ed25519 | Mobile Keychain (iOS Keychain / Android Block Store), synced via iCloud / Google account | App on first boot | Signs `mesh_versions`; proves authority to pair/revoke PCs |
| Pi-key | Ed25519 | PC keyring via `@napi-rs/keyring` (macOS Keychain / libsecret / Credential Manager). Fallback `~/.pi/remote/identity.json` (`0600`) with a warning on headless Linux | pi-extension on first boot | Authenticates WS to the relay; signs cross-PC envelopes |
| App-key | X25519, ephemeral; Owner-key signs the transcript | App RAM during pairing; derived channel keys in FlutterSecureStorage | App per pairing | Establishes directional E2E owner-channel keys through signed ephemeral-DH pairing |

Detailed trust model, threat table, and "what is NOT protected" live in
`PROTOCOL.md` → "Protection model (Trust Model)." Owner-channel payloads are
E2E-encrypted and authenticated, but the relay still sees routing metadata and
cross-PC Pi↔Pi traffic is not E2E-protected. Headless Linux falls back to a
`0600` file on disk; full encrypted backups can carry the Keychain; clone
detection (two PCs with the same Pi-key) is not yet implemented.

## Verification commands

Run from the owning subproject root:

```bash
# pi-extension/
corepack pnpm typecheck && corepack pnpm test && corepack pnpm build

# app/
flutter analyze && flutter test --exclude-tags e2e

# Dedicated cross-component E2E pairing harness (from repository root):
e2e/run-pairing.sh

# relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build

# cockpit/
flutter analyze && flutter test

# site/
pnpm lint && pnpm build
```

If a command is unavailable or too expensive in the current environment, state
what was skipped and why, and run the nearest meaningful smaller check.

## Open questions

Genuine ambiguities surfaced while authoring. None blocks the docs; each has a
recommended resolution and is flagged for operator confirmation so the
foundation stays clean rather than baking in a guess.

1. **Relay "stateless" framing has drifted.** The absorbed project's
   `plan/00-decisions.md` recorded "Relay stateless / No persistence." The
   relay now has a SQLite-backed `MeshStore` (the signed `mesh_versions`
   cartulary) plus in-memory `PeerRegistry`, `PresenceManager`, `RoomManager`,
   and `FirehoseMetrics`. Accurate framing: the relay is **stateless for
   message routing** (no per-session state, no offline queue) **with a narrow
   persistence layer for mesh membership** and ephemeral presence/rooms.
   Resolved — `docs/DECISIONS.md` records the current truth; the MVP-era
   "stateless" line is superseded.

2. **Daemon as first-class component.** The absorbed project's
   `plan/00-decisions.md` recorded "No daemon in the MVP." A substantial
   `pi-extension/src/daemon/` module has shipped (supervisord, cron registry,
   RPC child, install, registry). The daemon is GA, first-class — the
   MVP-scoping decision was explicitly revisited and shipped. Resolved —
   `docs/DECISIONS.md` records current truth.

3. **Fork product direction.** Resolved — fully private-carry; no upstream
   PRs. The bold refactor is fork-local with no upstream-compat constraints.
   Patchbay is the long-term successor direction. `docs/DECISIONS.md` →
   "Fork posture" records this.

5. **Multi-session vs. 1:1 pairing.** The absorbed project's
   `plan/00-decisions.md` had a complex reverted-and-re-added history around
   "1 pairing = 1 session" vs. N sessions per pairing. Current code: the app
   home page lists multiple peers/sessions; the extension's `OwnerMultiplexer`
   owns a channel registry keyed by Owner peer id. `attach` detaches and
   replaces the existing channel for the same Owner before installing a fresh
   one, and `OwnerMultiplexer.broadcast` fans out server messages across active
   owner channels. The relay forwards envelopes but does not own this
   owner-channel fanout. Resolved — the extension supports one active channel
   per Owner peer, with same-owner replacement on reattach.
   `docs/DECISIONS.md` records this.

All five resolved ambiguities are locked in `docs/DECISIONS.md`. The open
questions section above is retained for future ambiguities surfaced during
the bold refactor.
