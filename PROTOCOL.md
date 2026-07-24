# Outpost-Pi — Protocol & Security

Canonical documentation for the Outpost-Pi protocol and protection model.
Updated 2026-07-23.

---

## 30-second overview

- **Coding-agent mesh** running across multiple PCs belonging to the same user
- **Each PC** runs `pi-extension` (Node.js daemon) with **one Pi-key** Ed25519 key in the system Keychain (macOS/Linux/Windows)
- **The mobile app** is the **initial authenticator** (WhatsApp Web QR style) — after pairing, PCs operate autonomously with one another
- **Owner-key** Ed25519 lives in the mobile Keychain (iOS Keychain / Android Block Store), synced across devices under the same Apple ID / Google Account
- **Relay** WebSocket routes opaque owner-channel envelopes over TLS + stores Owner-signed `mesh_versions` — it never decides membership and always verifies signatures
- **Cross-PC routing** uses the `<pc>:<peer>` prefix in the envelope; a local UDS broker runs on each PC, and the relay forwards Pi-to-Pi traffic over WS

---

## Identities

| Key | Algorithm | Where it lives | Created by | Used by |
|---|---|---|---|---|
| **Owner-key** | Ed25519 | iOS Keychain (iCloud sync) / Android Block Store (Google sync) | Mobile app on first boot | Signs `mesh_versions`; proves authority to pair/revoke PCs |
| **Pi-key** | Ed25519 | `@napi-rs/keyring` on the PC (macOS Keychain / Linux libsecret / Windows Credential Manager). Fallback: `~/.pi/remote/identity.json` (`0600`) with a warning on headless systems | pi-extension on first boot | Authenticates WS to the relay; signs cross-PC envelopes |
| **App-key** | Ephemeral X25519; Owner-key Ed25519 signatures | Mobile app RAM during pairing; derived directional keys in FlutterSecureStorage | App for each pairing | Establishes the owner channel: signed ephemeral X25519 shares in `pair_request`/`pair_ok` bind the suite `outpost-pi-owner-channel-v1`, pair token, and Pi/Owner identities. HKDF-SHA256, salted by the pair token, derives directional keys; the extension persists them in `peers.json` (`0600`) and the app persists them in FlutterSecureStorage. Post-pairing frames use random 24B-nonce XChaCha20-Poly1305 with persisted `seqLE64` replay high-waters. |

**Fixed constraint**: "1 Pi-key per PC; hardware replacement = re-pairing." Pi-keys do not migrate between machines. The Owner-key compensates (the Owner syncs cross-device through the system Keychain).

---

## Protocol layers

```
┌─────────────────────────────────────────────────────────────────────┐
│  Agent layer       Pi coding agent (future: Claude Code, OpenCode)  │
├─────────────────────────────────────────────────────────────────────┤
│  Envelope          {from, to, id, re, body}  — 5-field JSONL        │
├─────────────────────────────────────────────────────────────────────┤
│  Routing           Local UDS broker  /  Cross-PC via relay forward  │
│                    Prefix <pc>:<peer> distinguishes local/remote    │
├─────────────────────────────────────────────────────────────────────┤
│  ACK protocol      received | denied | timeout                      │
│                    TS wrapper replies without token cost            │
│                    Legacy busy handled defensively; not emitted     │
├─────────────────────────────────────────────────────────────────────┤
│  Transport         UDS (local)  /  WebSocket over TLS (relay)       │
├─────────────────────────────────────────────────────────────────────┤
│  Trust             Ed25519 challenge-response                       │
│                    Owner-sig on mesh_versions                       │
│                    Auth handshake: app signs                        │
│                    `outpost-pi-relay-auth-v1\n` ++ nonce (domain-   │
│                    separated prefix) — prevents the owner-key from  │
│                    becoming a cross-protocol signing oracle. Relay  │
│                    verifies the same prefix. The hello frame carries│
│                    per-install `device_id`; on duplicate auth, the  │
│                    relay closes prior connection(s) for the SAME    │
│                    device (a Wi-Fi→cellular reconnect can leave TCP │
│                    half-open) for immediate recovery rather than    │
│                    waiting for the 25s ping timeout. Different      │
│                    devices for the same Owner (shared Keychain key) │
│                    coexist.                                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Relay ingress validation and bounds

`protocol/schema/` is the relay wire source of truth. Protocol codegen projects
its types, directional registries, ingress limits, and runtime validators into
the extension; Dart and Rust consume their generated typed projections. The
extension checks the raw UTF-8 frame limit before `JSON.parse`, validates the
parsed outer/control/cross-PC object with generated predicates, and only then
base64-decodes an accepted outer `ct`. The resulting typed ingress object is
decoded once and fanned out to owner, peer-channel, and cross-PC consumers.

The canonical outer sender shape is strict: `{peer, room, ct}`, all three
strings non-empty, with `additionalProperties: false`. Codegen also emits an
endpoint `compat` projection for the pre-rewrite receive shape: it may omit
`room`, but a present room must still be non-empty and unknown properties stay
rejected. This compatibility projection does not weaken the canonical
room-required type used for extension→relay sends or the relay's strict Serde
boundary. Generated cross-PC predicates likewise enforce non-empty recipient
arrays, non-empty string reply ids (`re`), and closed object shapes.

The schema-owned endpoint defaults are:

- 4 MiB maximum decoded outer `ct`;
- 64 KiB frame overhead, producing a 5,657,944-byte raw-message ceiling;
- 16 KiB for pre-auth challenge/auth frames;
- bounded device, room, cwd, session, model, and thinking metadata.

Rust applies WebSocket frame/message caps before typed Serde dispatch. The Node
extension also configures `ws.maxPayload`. Flutter checks raw UTF-8 length
before `jsonDecode` and routes generated relay DTOs before base64 decoding, but
its WebSocket API cannot prevent the platform from first allocating the
received message. Raising a relay deployment override does not raise the
endpoints' generated 4 MiB default.

---

## Envelope

A single format for the entire system. It works locally (UDS) and cross-PC (relay forwarding).

```json
{
  "from": "<sender-name>",
  "to": "<recipient-name>" | ["<r1>", "<r2>"] | "broadcast",
  "id": "<UUID v7>",
  "re": "<id-of-message-being-replied-to>" | null,
  "body": <any JSON>
}
```

Naming:
- **Local**: simple name (`sess-3`, `agent-2`, `broker`)
- **Cross-PC**: prefixed with the destination's `pc_label` (`casa:sess-3`, `trab:agent-1`)
- When it enters the destination local broker, the prefix is stripped (the local session does not know its own `pc_label`)

UUID v7 provides temporal ordering without coordination.

---

## ACK protocol

Every `agent_send` call waits for a quick ACK (default: 5s) generated by the destination peer's **TypeScript wrapper** — not by the LLM. Cost: microseconds locally, milliseconds cross-PC.

| Status | Meaning |
|---|---|
| `received` | The peer broker/harness accepted the envelope; if the peer is in the middle of a turn, the message waits for the next turn |
| `denied` | The peer refused (or the destination does not exist); abandon it |
| `busy` | **Legacy/defensive only**. The current broker does not emit `busy` for new work; messages to peers in the middle of a turn are delivered to the harness and processed in the next turn. If an old broker returns `busy`, treat it as obsolete/ambiguous delivery and update the peer rather than designing retry-on-busy. |
| `timeout` | An ACK did not arrive within 5s; treat it as a transport error |
| `transport_error` | Cross-PC only: the relay reported `offline`, `not_authorized`, or `bad_envelope` |

A **content reply** is asynchronous: the peer responds with **another normal send** carrying `re: <send-id-original>`. The sender sees the reply in its inbox on the next turn. There is no `agent_wait`. The synchronous `agent_request` tool remains supported but is deprecated because it blocks the current turn; prefer `agent_send` plus inbox observation. `re` is correlation, not a delivery mechanism.

Details in `plan/25-pc-mesh-bootstrap.md`, section "ACK protocol".

---

## Cross-PC routing

Cross-PC traffic is currently mediated by the relay (not direct P2P — deferred to the future).

### WS wire frame (Pi-A → Relay)

```json
{
  "type": "pi_envelope",
  "to_pc": "<pi-b-pubkey-base64>",
  "to_room": "main",
  "envelope": { "from": "casa:sess-3", "to": "trab:agent-1", ... }
}
```

`to_room` targets delivery only to that destination peer room (room-targeted,
not peer-wide fanout). An empty or absent `to_room` → `transport_error: bad_envelope`.

### Relay-delivered frame (Relay → Pi-B)

```json
{
  "type": "pi_envelope_in",
  "from_pc": "<pi-a-pubkey-base64>",
  "to_room": "main",
  "envelope": { ... }
}
```

### Authorization (relay-side)

Before forwarding, the relay checks `mesh_versions`:
- Are Pi-A and Pi-B in the list for the **same Owner**? Forward.
- Different Owners? `transport_error: not_authorized`
- Pi-B has no active WS? `transport_error: offline`

A 60s-TTL cache maps each Pi-pubkey to its sibling set.

### Anti-spoofing (broker-side)

When Pi-B receives `pi_envelope_in`:
- `from_pc` is the technical ground truth (the relay verified the pubkey)
- `envelope.from` is a human-readable address
- Anti-spoofing: `envelope.from` must start with the prefix matching the `pc_label` for `from_pc` (looked up through the sibling cache). Otherwise, drop + log.

### Transport errors as envelopes

Errors are not custom WS frames — they are normal envelopes with `from: "_relay"` + `body.type: "transport_error"`. The sender correlates them with `re: <envelope-id>`. The same-machine ACK handles them.

---

## Mesh membership

`mesh_versions` is the Owner-signed "registry office."

### Structure

```json
{
  "version": 7,
  "owner_pk": "<base64 standard, 32B>",
  "members": [
    { "pc_pubkey": "<base64>", "nickname": "casa", "paired_at": "2026-05-22T..." },
    { "pc_pubkey": "<base64>", "nickname": "trab", "paired_at": "2026-05-23T..." }
  ],
  "sig": "<Ed25519(canonical_json) by owner_sk>"
}
```

### Storage

The relay stores the entire blob in SQLite, indexed by `owner_pk_hash = SHA256(owner_pk)`.

- **POST /mesh/<hash>**: the client publishes a new version (the relay verifies the signature + monotonic version)
- **GET /mesh/<hash>**: the client reads the latest version and validates the signature locally
- Retained state is capped at 1,024 Owner rows and 64 MiB across the rows' variable fields. A write that would grow beyond either ceiling is rejected with HTTP 507 `mesh_storage_quota_exceeded`; the relay does not evict an Owner implicitly because eviction would revoke live mesh authorization.
- Creation of previously unseen Owner hashes is capped process-wide at 32 per 60 seconds. Excess creation is rejected with HTTP 429 `new_owner_rate_limited`; updates to an existing Owner do not consume that budget.

LWW (last-write-wins) resolves concurrent conflicts. Monotonic versioning prevents rollback.

### Self-revoke

The pi-extension polls periodically. If its Pi-pubkey is no longer in `members`, it self-revokes (leaves the mesh) gracefully.

Details in `plan/24-mesh-membership.md`.

---

## App actions

A curated vocabulary of typed actions that the mobile app invokes on the paired Pi session. This is **not** a generic slash-command picker — every action has a structured payload and maps to a public SDK API. The pi-extension handles it; the app parses nothing.

| Action | ClientMessage | SDK call in pi-extension |
|---|---|---|
| Compact context | `session_compact` | `ctx.compact()` |
| New session | `session_new` | `ctx.newSession()` |
| Set model | `model_set {provider, model_id}` | `ModelRegistry.find(...)` + `pi.setModel(model)` |
| Set thinking | `thinking_set {level}` | `pi.setThinkingLevel(level)` |
| List models | `list_models` | `ModelRegistry.getAvailable()` |

### Wire — examples

```json
// Request
{ "type": "session_compact", "id": "<uuid>" }

// Success reply
{ "type": "action_ok", "in_reply_to": "<uuid>", "action": "session_compact" }

// Failure reply
{ "type": "action_error", "in_reply_to": "<uuid>", "action": "session_compact",
  "error": "compact unavailable (no active session ctx)" }
```

```json
// Model list request → reply
{ "type": "list_models", "id": "<uuid>" }
{
  "type": "models_list",
  "in_reply_to": "<uuid>",
  "models": [
    { "id": "claude-opus-4-7", "name": "Claude Opus 4.7", "provider": "anthropic",
      "reasoning": true, "context_window": 200000 }
  ],
  "current": { "id": "claude-opus-4-7", "name": "Claude Opus 4.7", "...": "..." }
}
```

### Thinking levels (fixed enum)

```
"off" | "minimal" | "low" | "medium" | "high" | "xhigh"
```

`"xhigh"` is honored only by specific model families (Anthropic 4.x reasoning, OpenAI o-series). Pi falls back to a neighboring level when it is unsupported — without an error.

### Side effects

Replies (`action_ok` / `models_list`) only confirm dispatch. Visible effects arrive through the normal channels:
- Completed compaction → `agent_chunk`/`agent_done` in chat
- Changed model → `model_select` event broadcast to all connected owners
- New session → `pair_ok` (or equivalent) with a new `session_started_at`

### Known `error` codes (app↔Pi)

`error.code` is an open string: clients must tolerate new codes. Known codes:

| Code | Meaning |
|---|---|
| `tool_approval_required` | Action blocked while waiting for tool approval |
| `invalid_message` | Malformed or invalid message at the boundary |
| `unsupported_type` | Unsupported message type |
| `too_large` | Payload exceeds the accepted limit |
| `rate_limited` | Sender is temporarily limited |
| `timeout` | Operation exceeded its wait window |
| `internal_error` | Permanent local-processing failure |
| `session_mismatch` | The message belongs to another remote session. Pi rejects it fail-closed and returns its current `session_id`; the app treats the response as a convergence/control signal (not visible transcript content) — canonical rebind and `session_sync` are triggered by room-metadata rotation, never by the error's `session_id` |
| `delivery_pending` | Transient signal: the message arrived during a session transition and was queued for replay; the app keeps the bubble pending and waits for the echo or an extended timeout |

### Why typed actions rather than a generic picker

The `@mariozechner/pi-coding-agent` SDK does not expose a generic API to invoke built-in slash commands (`/compact`, `/model`, `/fork`, `/copy`, etc.) — only some have an equivalent in `ExtensionContextActions`. Mirroring the TUI picker would require manually mirroring the built-in list + invocability matrix + canonicalized chip UX, while several commands are only informational hints. A typed vocabulary is simpler, more honest, and covers 100% of the actions that make sense on mobile. The pattern is validated by the `pi-telegram` adapter (the same approach: curated vocabulary, no generic picker).

Details in `plan/28-pi-commands.md`.

---

## Images (plan/30)

`user_message` accepts an inline image attachment (one per message for now),
optional and backward-compatible — a text-only message is unchanged on the wire.

### Wire
ClientMessage `user_message` adds `images?`:

```jsonc
{ "type": "user_message", "id": "msg-1", "text": "what is this?",
  "images": [{ "data": "<base64>", "mime": "image/jpeg" }] }
```

`WireImage = { data: string /* base64 */, mime: string }`. The echoed ServerMessage
`user_message` (broadcast to all owners) also carries `images`, so every device
renders the same bubble.

### Mapping to the model
Pi constructs the SDK multimodal content in **image(s) → text** order:
`[{ type:"image", data, mimeType: mime }, { type:"text", text }]` →
`sendUserMessage(content)`. Wire `mime` becomes SDK `mimeType`. Without `images` →
`sendUserMessage(text)` (a string), identical to the prior behavior.

### Model capability
`WireModel` (in `models_list` / `current`) adds `vision: boolean`, derived from
`Model.input.includes("image")`. The app disables attachment when the active model
has `vision:false`.

### Transport
The image travels **inline** in `user_message` (base64), inside the existing
owner-channel plaintext. The protected owner-channel adapter seals that payload
before it becomes `outer.ct`; the relay is unchanged and forwards the opaque
base64 frame without interpreting its contents.
Cost: double-base64 (~+77%), accepted in this slice because it uses a compressed image
(~150–400 KB). History/`session_sync` carries the bytes (decision #8). A binary channel
is deferred to Track 2.

---

## Message queued during an active turn

A short **Pi-side, in-memory** queue: while a turn is active, the app can retain
the next textual prompt. The pi-extension sends it when the current turn ends. This
is not a relay offline queue; a restart loses the state.

### Wire

```jsonc
// app → Pi-extension
{ "type": "queued_message_set", "id": "msg-2", "text": "next prompt" }
{ "type": "queued_message_clear", "id": "clear-1" }

// Pi-extension → app(s)
{ "type": "queued_message_state", "id": "msg-2", "text": "next prompt" }
{ "type": "queued_message_state" } // empty
```

### Semantics

- `queued_message_set`: sets/replaces a textual pending message. Its `id` becomes
  the drained `user_message` id. The app can concatenate multiple prompts with `\n`.
- `queued_message_clear`: cancels the pending message.
- Drain: when `!turnActive && !currentTurnId`, clear the state, broadcast an empty
  `queued_message_state`, and process it as a normal `user_message`
  (`echo user_message` + `sendUserMessage(text)`).
- `session_sync`: sends the current `queued_message_state` before history.
- Text only. `images` are supported only on the immediate `user_message`.
- The relay remains unchanged/opaque.

---

## Pairing

The QR code presents a Pi-pubkey + room hint + single-use token.

### App ↔ Pi targeting invariants

Pairing and routing identify a machine, a room on that machine, and one active
Pi SDK session within that room. These layers are distinct; see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) → "Session and room model" for
the canonical session boundary.

- **Pairing is machine-scoped.** On the Pi side, an Owner public key
  (`owner_pk`, stored as `remote_epk` in `~/.pi/remote/peers.json`) is authorized
  by the machine-global pairing roster, not by one Pi process. Local Pi
  processes share that roster and the machine's Pi-key.
- **A room is scoped by `(realpath(cwd), assigned-name)`.** The extension derives
  `room_id` once through `roomIdFor(cwd, assignedName)`. The default assigned
  name preserves the legacy cwd-only id; custom and broker-assigned `#N` names
  use the name-scoped derivation. The cwd/name lock uses the same id, so two live
  processes claiming the same cwd and assigned name are a lock violation, not a
  supported topology.
- **Relay delivery is room-targeted for the active Owner channel generation.**
  One inner app↔Pi envelope targets `(owner_pk, room_id)`; the extension keeps
  one active secure channel generation per Owner key. Attaching or re-pairing
  that same key replaces the prior channel and peer record, and delivery does
  not preserve simultaneous independently keyed same-key device channels.
- **A `user_message` targets one Pi SDK session.** Its required `session_id`
  selects the session inside the addressed room. The extension rejects a
  missing or non-current id before SDK delivery; the relay carries it opaquely.

1. The app scans the QR code and opens a WebSocket to the relay, authenticating
   with the persisted **Owner-sk** via the relay's Ed25519 challenge-response
   (`outpost-pi-relay-auth-v1\n` ++ nonce).
2. The app generates an ephemeral X25519 keypair and sends `pair_request` with
   `token_id`, `pair_mac`, `dh_pk` and `dh_sig` — the raw pair token NEVER
   crosses the wire (a relay observing the exchange learns nothing it can
   reuse). `token_id` is `base64(SHA-256(token)[:16])`, a public locator.
   `pair_mac` is `HMAC-SHA256(key=token, msg=
   outpost-pi-owner-channel-v1 ++ "\npair\n" ++ tokenIdBytes ++ ownerEdPk ++
   appDhPk ++ piEdPk)`, proving QR-token knowledge over exactly the fields a
   malicious relay could otherwise substitute. `dh_sig` is an Owner-key
   signature over
   `outpost-pi-owner-channel-v1 ++ "\napp\n" ++ tokenBytes ++ appDhPk ++ piEdPk`.
   The QR Pi public key binds the request to the scanned Pi.
3. The pi-extension resolves the token by `token_id` and verifies `pair_mac`
   (constant-time) BEFORE anything else — failure is `pair_error
   token_unknown`, consumes nothing, and reveals no stage detail. It then
   verifies `dh_sig` against the relay-authenticated Owner public key,
   rejecting a failure with `pair_error bad_dh_sig`, generates its ephemeral
   X25519 keypair, derives and persists the directional channel keys, then
   returns `pair_ok` with its DH public key and Pi-key signature.
   That signature covers the suite, token, app and Pi DH public keys, and Owner
   public key.
4. The app verifies the Pi signature against the QR Pi public key, derives the
   same keys, and persists them in FlutterSecureStorage. Both sides retain
   per-direction `seqLE64` high-water marks for replay protection.
5. The app adds the Pi-pubkey to its local `mesh_versions` and publishes a new
   version to the relay. The pi-extension then accepts only protected
   post-pairing frames from that Owner.

Multiple Owners can pair with the same PC (concurrency — `peers.json` accepts
N entries).

Details in `plan/04-pairing.md`.

---

## Protection model (Trust Model)

### What is protected

- **Authenticated pairing and owner channel**: the app reaches the relay through
  Owner-key challenge-response (`outpost-pi-relay-auth-v1`), and the signed
  ephemeral X25519 `pair_request`/`pair_ok` transcript establishes directional
  owner-channel keys. The raw pair token never crosses the wire: `pair_mac`
  (HMAC keyed by the token) proves QR-token knowledge before token
  consumption, so a relay that observes a pairing cannot race its own pairing
  under an attacker Owner key. Proof-holders still receive actionable
  `token_expired`/`token_consumed` errors; unknown locators and bad proofs
  are indistinguishable `token_unknown`. The pair token salts HKDF-SHA256
  derivation; signed transcripts bind both identities and the QR Pi key.
- **App ↔ Pi owner-channel E2E**: post-pairing `outer.ct` is
  `base64(0x01 || seqLE64(8B) || nonce(24B random) ||
  XChaCha20-Poly1305(key, nonce, aad=seqLE64, plaintext=jsonUtf8))`. The
  random 24-byte nonce and authenticated sequence protect confidentiality,
  integrity, and replay; sequence high-waters and derived keys persist across
  reconnects (`peers.json` mode `0600` on the extension, FlutterSecureStorage
  on the app).
- **WS to the relay over TLS**: no one on the route (ISP, NAT, classic MITM) sees transport plaintext.
- **Cross-PC cryptographic authorization**: the relay forwards only between sibling Pis of the same Owner (verified through the Owner-sig in `mesh_versions`).
- **Anti-spoofing between Pis**: the broker rejects envelopes whose `envelope.from` prefix does not match authenticated `from_pc`.
- **Membership anti-rollback**: monotonic versioning + signature prevents a relay/attacker from rolling back the mesh.
- **Pi secret protected**: system Keychain (macOS Keychain / desktop Linux libsecret / Windows Credential Manager). An attacker needs the logged-in user context AND Keychain unlock.
- **Owner secret protected**: iOS Keychain / Android Block Store, synced through the iCloud/Google account; recoverable when changing devices.

### What is NOT protected (stated honestly)

- **Cross-PC Pi↔Pi traffic is not E2E-protected**. The relay can read its generic
  envelope bodies as well as routing metadata. The app↔Pi owner channel is
  E2E-encrypted and authenticated; its `outer.ct` payload is opaque to the
  relay.
- **Relay routing metadata remains visible** for owner-channel traffic,
  including who communicates, room names, cwd, model, and timing. Mitigation:
  **self-host** the relay (open source).
- **Headless Linux** (Docker, a VPS without a D-Bus session): the Pi-key falls back to a `0600` file on disk with a loud warning. An attacker with user access can read it. GNOME Keyring / KWallet is recommended for real hardening.
- A **full encrypted backup** (Time Machine, encrypted iCloud Drive, etc.) can carry the Keychain. An attacker needs the backup user passphrase.
- **Clone detection is not implemented yet**: two PCs with the same Pi-key (through a copied headless file or compromise) can coexist on the relay without an alert. On the roadmap (plan/27 Wave E3).

### Summary threat model

| Adversary | Capability | Protected? |
|---|---|---|
| Network passive | Sniff TLS | ✅ Yes (TLS cipher) |
| Network active (MITM) | Sniff + inject | ✅ Yes (TLS + Ed25519 pairing) |
| Public relay operator | Sees routing metadata (who talks to whom, room names, cwd, model, timing); can read unprotected cross-PC envelopes | ⚠️ Partial — owner-channel payload contents are E2E-protected; mitigation: self-host |
| Other user on the target PC | Reads target filesystem | ✅ Yes (user-bound Keychain) |
| Attacker with root on target PC | Memory dump, process injection | ❌ No (acceptable threat model: root = game over) |
| Attacker with a disk backup | Restores disk to another Mac | ✅ Yes on macOS with FileVault enabled (recommended) |
| Attacker who steals only `peers.json` | Obtains Owner metadata and persisted directional channel keys | ❌ No for the affected owner channel; re-pair to replace the keys |

---

## Failure modes

| Failure | Behavior |
|---|---|
| Relay disconnects | pi-extension reconnects with backoff; local agents continue communicating through the UDS broker |
| Pi-B is offline during cross-PC send | Sender immediately receives `transport_error: offline`. There is no offline queue in the relay. |
| Pi-B belongs to another Owner | Sender receives `transport_error: not_authorized` |
| Owner revokes Pi-A from the mesh | Pi-A detects it at the next `mesh_versions` poll, self-revokes, and exits gracefully |
| Pi WS reconnects frequently (NAT timeout) | Relay deduplicates `peer_online` emission (offline→online transition only); client deduplicates identical snapshots |
| Relay crashes | All cross-PC traffic stops; local agents continue operating (UDS) |

---

## Public architectural roadmap

Short term:
- Wave E3: server-side clone detection (alert when two WS connections for the same Pi-pubkey come from different IPs)

Medium term:
- **Harness wrappers** (`outpost-pi claude`, `outpost-pi opencode`): other coding agents connect to the local UDS broker through a wrapper, gaining mesh capability without reimplementing the protocol
- E2E protection for cross-PC Pi↔Pi payloads

Long term:
- Direct PC-to-PC communication through WebRTC/QUIC (the relay becomes a fallback)
- Optional hardware-bound Pi-key through Secure Enclave (Apple Silicon) / TPM (Linux/Windows)

---

## Reference implementations

- **Relay** (Rust, axum): [`relay/src/`](relay/src/)
- **Pi-extension** (Node/TS): [`pi-extension/src/`](pi-extension/src/)
- **Mobile app** (Flutter): [`app/lib/`](app/lib/)
- **Architectural plans**: [`plan/`](plan/) (especially `plan/03-protocol.md`, `plan/23-owner-key-sync.md`, `plan/24-mesh-membership.md`, `plan/25-pc-mesh-bootstrap.md`)

---

## Report security issues

[Define channel] — for now, open an issue marked `security` or contact the maintainers directly.
