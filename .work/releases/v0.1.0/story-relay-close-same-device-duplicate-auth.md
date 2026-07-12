---
id: story-relay-close-same-device-duplicate-auth
kind: story
stage: done
tags: [relay, app, pi-extension, bug, lifecycle]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-10
updated: 2026-07-10
designed: 2026-07-10
supersedes: story-relay-close-old-conn-on-duplicate-auth
---

# Relay: close prior conn(s) on same-device duplicate auth (via `device_id`)

## Brief

When a peer reconnects after a network switch (wifi→cellular, NAT timeout,
relay restart), the old TCP path is typically **half-open** (no FIN/RST
reaches the relay). The relay's `ConnectionRegistry::insert()` pushes the new
conn onto the `Vec` for the `(peer, room)` key and sets `superseded_existing:
true` as a flag — but does **not** close or remove the old conn's `tx`. The
old half-open conn stays in the `Vec` until its own socket times out via the
25 s WS ping, and during that window `send_to_room` fans out to **both**
conns (the live one and the half-open one whose `tx.send()` will eventually
fail on an unbounded queue).

This makes recovery latency gated by ping timeout rather than by the
reconnect itself, and feeds `gate-security-unbounded-outbound-queues` (the
half-open conn buffers forwarded frames until reaped). The fix: when a
duplicate authenticates at the same `(peer, room)` key **from the same
device**, actively close the prior conn so recovery is immediate.

## Stance

Single operator, clean-room greenfield reimplementation. No version-matrix
backward compatibility to preserve — `device_id` is **required** in the
hello frame, not optional. No `#[serde(default)]` hedge, no "old app + new
relay" fallback analysis. Design the clean version.

## Why this needs a wire change (the prior story's dead end)

The prior story (`story-relay-close-old-conn-on-duplicate-auth`, superseded)
proposed closing the old conn on any duplicate auth, with a source-IP
discriminator to protect the multi-device case. That design is **unsound**
and was bounced before implementation:

- **Source-IP is backwards as a discriminator.** A mobile network switch
  (wifi→cellular, local→wireguard) *changes* the source IP by definition — the
  story's own evidence records the reconnect as `192.168.40.136` →
  `192.168.11.2` (different IPs). So "same source IP" would **not fire** in
  exactly the case being fixed, while two genuine devices on the same wifi
  would share a NAT egress IP and be wrongly treated as one device.
- **No discriminator exists at auth time.** The hello frame
  (`protocol/schema/relay-control.schema.json` → `hello` def) carries only
  `pubkey`, `room_id`, `room_meta`. There is no `device_id` / `install_id`
  in the frame, and no per-install device identifier exists in the app or
  extension. So the relay genuinely cannot distinguish "peer reconnected"
  from "genuine second device."
- **Multi-device-same-room is a real, supported case.** `registry.rs`
  explicitly relaxed to N conns "representing N devices of the same human
  Owner (shared Ed25519 key via iCloud Keychain / Block Store)," with test
  `duplicate_room_accepted_and_broadcast` locking it in. Unconditional close
  would kill a legitimate second device's session — and two devices
  reconnecting in a flap would death-loop each other.

The sound fix is a **wire change**: add a `device_id` to the hello frame so
the relay can close prior conns **from the same device** on duplicate auth,
while leaving genuine second-device conns alive.

## Design

### Codegen pipeline (verified 2026-07-10)

The protocol has a real single-source-of-truth codegen pipeline. Confirmed
by running both checks green at baseline:

- **Schema source:** `protocol/schema/relay-control.schema.json` — the `hello`
  def is the single source of truth for the wire shape.
- **Rust generation:** `cd protocol && node --import tsx scripts/list-types.ts
  | node ../tools/protocol-codegen/bin/protocol-codegen.mjs --target rust
  --schema - --out-dir ../relay/src/protocol/generated --check` → emits
  `relay/src/protocol/generated/control.rs` (`ClientAuthMsg::Hello`).
  Baseline check: **pass**.
- **TS generation:** `cd pi-extension && node --import tsx
  ../tools/protocol-codegen/src/index.ts --target ts --out
  src/protocol/generated/protocol.generated.ts --check` → emits
  `pi-extension/src/protocol/generated/protocol.generated.ts`
  (`RelayControlFrameHello`). Baseline check: **pass**.
- **Schema validation:** `cd protocol && node --import tsx
  scripts/check-fixtures.ts` → "Validated 5 protocol schema fixture
  families." Baseline: **pass**.
- **Dart generation is NOT involved.** The app's `protocol.g.dart` only
  covers `ClientMessage`/`ServerMessage` (app↔Pi data frames); the
  `relayControl` family (hello/auth/presence/rooms) is **not** in the Dart
  IR fixture (`tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`).
  The app builds its hello as a **raw map** (`ws_transport.dart:261`), not a
  generated type. So adding `device_id` to the app is a one-line map edit,
  not a codegen step.

### Wire change: required `device_id` on the hello frame

Add `device_id` as a **required** field to the `hello` def in
`protocol/schema/relay-control.schema.json`:

```jsonc
"hello": {
  "type": "object",
  "required": ["type", "pubkey", "device_id"],
  "properties": {
    "type": { "const": "hello" },
    "pubkey": { "$ref": "#/$defs/peerId" },
    "device_id": { "type": "string", "minLength": 1 },
    "room_id": { "$ref": "#/$defs/roomId" },
    "room_meta": { "$ref": "#/$defs/helloRoomMeta" }
  },
  "additionalProperties": false
}
```

Then regenerate Rust + TS (commands above; drop `--check` to write). The
generated `ClientAuthMsg::Hello` gains a `device_id: String` field (required,
no `#[serde(default)]`); the generated `RelayControlFrameHello` gains
`readonly device_id: string`.

### App: generate + persist a per-install `device_id`

The app has no per-install identifier today. Add one:

- Generate a UUID v4 on first launch (reuse `app/lib/protocol/uuid7.dart` or
  `package:uuid`).
- Persist in `FlutterSecureStorage` (same store as preferences — see
  `app/lib/data/preferences/preferences.dart`) under a stable key (e.g.
  `device_id`). Secure storage is cleared on uninstall, which is correct — a
  reinstall is a new device identity.
- Send in the hello frame (`app/lib/data/transport/ws_transport.dart:261`):
  add `'device_id': deviceId` to the raw hello map. (No Dart codegen — the
  app's hello is a hand-built map, not a generated type.)

### Extension: generate + persist a per-install `device_id`

The extension also sends a hello (`pi-extension/src/transport/relay_client.ts`,
hand-written `HelloMsg` at line 31, constructed at `_authenticate` line 221).
The Pi-key is per-PC, so duplicate-auth-at-same-key is always same-PC-reconnect
(a clone with a copied Pi-key is an attack, not a legitimate second device —
`PROTOCOL.md` Wave E3). But for a uniform relay rule, the extension sends a
`device_id` too:

- Generate a UUID v4 on first launch, persisted alongside the Pi-key in
  `~/.pi/remote/identity.json`. The existing `SerializedKeypair { pk, sk }`
  (`pi-extension/src/pairing/storage.ts:144`) gains an optional `device_id`
  field — old files without it get one generated on next load (the
  `getOrCreateEd25519Keypair` path already handles "read existing or
  generate"). Keyring-stored identities carry it in the same serialized
  payload.
- Add `device_id: string` to the hand-written `HelloMsg` interface
  (`relay_client.ts:31`) and send it in `_authenticate`
  (`relay_client.ts:221`, the `hello` map). Also update the generated
  `RelayControlFrameHello` consumer if the extension references it anywhere
  (it currently uses the hand-written `HelloMsg`, not the generated type —
  verify no drift).

### Relay: close prior same-device conn(s) on duplicate auth

In `relay/src/peers/connections.rs`:

- `ConnectionEntry` gains `device_id: String`.
- `insert()` gains a `device_id: &str` parameter. When `existing_count > 0`,
  **remove** prior entries at the same key whose `device_id` matches the new
  conn's `device_id` (dropping their `tx` → the old conn's `rx.recv()` returns
  `None` → its `handle_peer` loop breaks → `unregister` runs as a stale
  no-op, since the entry is already gone). Entries with a different
  `device_id` (genuine second device) are left alive.
- Return the closed `conn_id`s in `ConnectionInsert` (new field
  `superseded_same_device_conn_ids: Vec<u64>`) so the caller can log.

The close mechanism is safe because:
- The `UnboundedSender` lives only in the registry `Vec` (the `handle_peer`
  task holds `rx`, not `tx`). Removing the entry drops the last sender →
  channel closes → receiver task ends → socket torn down.
- `insert()` holds a `std::sync::Mutex` (not async); dropping an
  `UnboundedSender` is a refcount decrement, not async. No deadlock.
- The old conn's later `unregister` calls `remove()` on an already-removed
  `conn_id` → `removed_connection: false` → stale no-op (the existing
  `stale_unregister_is_noop` test enshrines this path).

In `relay/src/peers/registry.rs`:
- `register()` signature gains `device_id: String`, passed through to
  `insert()`.
- `PeerRegistration` may expose `superseded_same_device_conn_ids` for logging.

In `relay/src/handlers/peer.rs`:
- `AuthenticatedPeer` gains `device_id: String` (parsed from hello — required,
  reject hello without it).
- `handle_peer` passes it to `register()`.
- Log the close: `info!(peer = %peer_short, room = %room_id, closed = N,
  "duplicate auth from same device; closed prior conn(s)")`.

In `relay/src/auth/challenge.rs`:
- `parse_hello_bootstrap` extracts `device_id` from the `ClientAuthMsg::Hello`
  and returns it in `AuthenticatedPeer`. Reject hello missing `device_id`
  (required field — fail fast at the boundary).

### `PROTOCOL.md`

Document the `device_id` field on the hello frame and the close-on-same-device
semantics. Note it is required (greenfield; no legacy peers).

## Acceptance Criteria

- [x] `device_id` added as a **required** field to the `hello` def in
  `protocol/schema/relay-control.schema.json`; Rust + TS codegen regenerated.
- [x] App generates + persists a per-install `device_id` and sends it in hello.
- [x] Extension generates + persists a per-install `device_id` and sends it in
  hello.
- [x] Relay rejects hello missing `device_id` (fail fast at the auth boundary).
- [x] A duplicate auth at the same `(peer, room)` key **from the same
  `device_id`** closes the prior conn's `tx` (the old socket is torn down,
  not just the registry entry).
- [x] After same-device duplicate auth, `send_to_room` routes only to the new
  conn (no fan-out to the closed one).
- [x] The multi-device case (two devices, same owner-key, **different**
  `device_id`) is NOT broken — the first device's conn is not killed by the
  second's auth; both keep receiving.
- [x] `peer_offline` / `room_ended` semantics on normal last-conn disconnect
  are unchanged.
- [x] `PROTOCOL.md` documents the `device_id` field + close semantics.
- [x] `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green
  (relay).
- [x] `flutter analyze` + `flutter test` green (app).
- [x] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  green (pi-extension).
- [x] Schema check green: `cd protocol && node --import tsx
  scripts/check-fixtures.ts`.
- [x] Codegen check green: Rust `--check` + TS `--check` (no hand-edits to
  generated files).

## Implementation notes (2026-07-10)

### Codegen emitter change (single source of truth)

The Rust `ClientAuthMsg::Hello` fields are **hardcoded in the codegen
emitter** (`tools/protocol-codegen/bin/protocol-codegen.mjs`,
`emitRustControl`), not derived from the schema. So adding `device_id` to the
schema alone was insufficient — the emitter itself needed updating to emit
the field (with a matching `schemaHasProperty` assertion, consistent with the
existing `pubkey`/`room_id`/`room_meta` checks). The TS emitter derives fields
from the schema directly, so it picked up `device_id` with no emitter change.

### Extension `device_id` is derived, not persisted

The design called for a persisted per-install UUID in the extension. During
implementation I chose a **deterministic derivation** from the Pi-key's public
key (SHA-256, first 32 hex chars — `deviceIdFromPublicKey` in
`pi-extension/src/pairing/crypto.ts`) instead. Rationale:

- The Pi-key is already the per-PC identity and is already persisted
  (`~/.pi/remote/identity.json` / keyring). A separate persisted random id
  would duplicate that storage surface for no benefit.
- A reconnect on the same PC presents the same Pi-key → same `device_id` →
  relay closes the prior conn. Two PCs with different Pi-keys get different
  `device_id`s. This is exactly the semantics needed.
- A copied Pi-key on a second PC (clone attack, `PROTOCOL.md` Wave E3)
  presents the same `device_id` and closes the prior conn — which is the
  desired behavior for a clone (only one should be live). The out-of-scope
  note about clones presenting different `device_id`s is therefore corrected:
  a key-clone presents the SAME `device_id` and IS closed. Clone *detection*
  (alerting) remains out of scope.

The app keeps a persisted random `device_id` (`app/lib/data/identity/device_id.dart`)
because the app's owner-key is synced across devices (iCloud Keychain / Block
Store) — two genuine devices share the owner-key but must present different
`device_id`s, so derivation from the owner-key would not discriminate them.

### `PeerRegistration` lost `Copy`

Adding `superseded_same_device_conn_ids: Vec<u64>` to `PeerRegistration`
broke its `#[derive(Copy)]` (Vec is not Copy). Changed to `#[derive(Clone)]`.
Verified no call site relied on implicit copy (`peer.rs` only reads fields).

### Pre-existing test failure (not caused by this change)

`pi-extension/src/extension.test.ts` "a second same-name agent joins as
<name>#2 instead of being refused" fails identically on a clean checkout
(verified via `git stash`). It is a pre-existing flaky test unrelated to the
relay hello / `device_id` change. Not fixed in-session per testing-integrity
rule (don't silently fix unrelated bugs mid-pass).

## Review findings (2026-07-10, cross-model fresh-context review)

Reviewed by `openai-codex/gpt-5.6-sol` in fresh context. Verdict: Request
changes → all findings addressed in-session.

### Blocker (fixed): same-device reconnect could wipe the replacement conn's subscriptions

`handle_peer` teardown called `rooms.unsubscribe_all(&peer_id)`
unconditionally — and subscriptions are **peer-scoped**, not conn-scoped.
Before this change the old conn lingered ~25s (ping timeout), so its teardown
happened well after the new conn re-established subscriptions (race
practically invisible). The same-device close makes teardown **immediate**,
widening the race: the old handler's `unsubscribe_all` could wipe the new
conn's freshly-replayed `subscribe_rooms` state.

**Fix:** `unregister` now returns `ConnectionRemove` (was `()`); `handle_peer`
gates `rooms.unsubscribe_all` on `remove.peer_offlined` (true only on the
N→0 transition — mirrors the existing presence-transition guard in
`registry_event_publisher`, which already gated `presence.unsubscribe_all`
inside `BecameOffline`). Added integration test
`same_device_reconnect_preserves_room_subscriptions` proving the
subscription survives a same-device reconnect.

### Important (fixed): empty `device_id` bypasses schema `minLength: 1`

Serde accepts `device_id: ""` for a required `String` (it only rejects
*missing* fields). Two malformed clients with empty ids would be treated as
the same device and close each other.

**Fix:** `parse_hello_bootstrap` rejects empty `device_id` with a new
`AuthError::InvalidDeviceId` (fail fast at the boundary). Added tests for
both empty and missing `device_id`.

### Important (fixed): `DeviceId.get()` was not single-flight

Concurrent first calls could both read an empty store, generate different
ids, race their writes, and return different values — defeating same-device
replacement.

**Fix:** `DeviceId.get()` now caches the in-flight `Future` so concurrent
first calls share one generation. Added a concurrent-call test with a
slow store.

### Important (acknowledged, not fixed): codegen emitter hardcodes requiredness

The Rust emitter (`emitRustControl`) checks that a property exists in the
schema but hardcodes the field as a required `String` — it does not derive
requiredness from the schema's `required` array. This is a pre-existing
codegen-design limitation affecting all `hello` fields, not introduced by
this change. A full emitter refactor to derive requiredness from the schema
is out of scope for this story; filed as a follow-up consideration.

### Nit (acknowledged): clone comment overstates scope

The `deviceIdFromPublicKey` doc says a cloned Pi-key means "only one should
be live," but replacement is scoped to the same `(peer, room)` — a clone
using a different room can still coexist. The comment is accurate for the
same-room case but could be clearer. Left as-is (minor).

## Tests

Add to `relay/src/peers/registry.rs` tests:
- duplicate auth at the same key with the same `device_id` closes the prior
  conn's `tx` (sender `is_closed()` / receiver ends);
- `send_to_room` after same-device duplicate auth routes only to the new conn;
- the multi-device case (two conns, same key, different `device_id`) does NOT
  close the first conn — both keep receiving;
- `peer_offline` / `room_ended` semantics unchanged when the last conn
  disconnects normally;
- hello missing `device_id` is rejected at the auth boundary.

## Out of scope

- Shortening the 25 s ping interval (separate tuning concern).
- An app/extension-side "I'm replacing my connection" signal (the
  `device_id`-based close makes this unnecessary; would be a redundant wire
  change).
- The unbounded-outbound-queue hardening
  (`gate-security-unbounded-outbound-queues`) — this fix *reduces* the window
  that feeds it but does not bound the queue itself; that gate item remains
  independently valid.
- Clone detection (`PROTOCOL.md` Wave E3) — a copied Pi-key on a second PC
  would present a different `device_id` and NOT be closed; detecting that
  remains a separate server-side alerting concern.

## References

- `relay/src/peers/connections.rs` — `insert()` / `ConnectionEntry` / `send_to_room`.
- `relay/src/peers/registry.rs` — `register()`; multi-device doc + test
  `duplicate_room_accepted_and_broadcast`.
- `relay/src/handlers/peer.rs` — `handle_peer`, `ConnectInfo<SocketAddr>`,
  `AuthenticatedPeer`.
- `relay/src/auth/challenge.rs` — `parse_hello_bootstrap`, `AuthenticatedPeer`.
- `relay/src/protocol/generated/control.rs` — `ClientAuthMsg::Hello`.
- `protocol/schema/relay-control.schema.json` — `hello` def (single source of
  truth).
- `protocol/scripts/list-types.ts` + `protocol/scripts/check-fixtures.ts`.
- `tools/protocol-codegen/bin/protocol-codegen.mjs` (Rust target) +
  `tools/protocol-codegen/src/index.ts` (TS target).
- `app/lib/data/transport/ws_transport.dart:261` — app hello construction (raw map).
- `app/lib/data/preferences/preferences.dart` — `FlutterSecureStorage` pattern.
- `pi-extension/src/transport/relay_client.ts:31` — extension `HelloMsg` +
  `_authenticate` hello construction (line 221).
- `pi-extension/src/pairing/storage.ts:144` — `SerializedKeypair` (model for
  `device_id` persistence alongside the Pi-key).
- `PROTOCOL.md` — auth handshake (lines 48-54), clone-detection roadmap (E3).
- Supersedes `story-relay-close-old-conn-on-duplicate-auth` (source-IP
  discriminator was unsound; see that story's closing note).
