# Outpost-Pi — Architecture

How the system is organized: components, data flow, the wire protocol shape,
the session/room model, and lifecycle. Current truth. For the security/trust
detail see `PROTOCOL.md`; for locked decisions see `docs/DECISIONS.md`.

## Components

```
                ┌─────────────────────────────────────────────┐
                │                   RELAY (Rust)               │
                │  axum WS + HTTP  ·  SQLite mesh_versions     │
                │  PeerRegistry · PresenceManager · RoomManager │
                │  MeshAuthCache (60s) · FirehoseMetrics        │
                └───┬───────────────────────────────────┬───────┘
        TLS WS (pi_envelope)              TLS WS (ClientMessage/ServerMessage)
                    │                                       │
   ┌────────────────┴──────────────┐         ┌─────────────────┴────────────┐
   │      pi-extension (Node/TS)   │         │        app (Flutter mobile)    │
   │  Pi SDK bridge · daemon/sup.  │◄────────┤  chat · tool req · actions    │
   │  relay_client · mesh_node     │  pair +  │  ConnectionManager · sync     │
   │  UDS broker · pairing · rooms │  WS chat │  Hive cache · mesh_client     │
   └──┬──────────────────────┬─────┘         └────────────────────────────────┘
      │ UDS envelope          │ Pi custom-event RPC (structured control)
      │ {from,to,id,re,body}  │
      ▼                       ▼
   other Pi peers        cockpit (Flutter desktop)
   on same PC            PTY · filesystem · worktrees · session view
```

### pi-extension (`pi-extension/src/`)

The Pi extension plus a standalone daemon. It is the only component that
touches the Pi SDK.

- `index.ts` — composition entrypoint that wires the module-owned command,
  relay, owner, and SDK-session adapters. Lifecycle ownership is registered in
  `extension/composition_root.ts`; session projection and runtime ownership
  live under `session/` and `extension/` rather than in one monolithic entry.
- `session/` — the local agent mesh surface: `broker` (UDS), `broker_remote`,
  `mesh_node` (cross-PC peer), `bridge` (Pi SDK ↔ wire), `cwd_lock`,
  `leader_election`, `peer` / `peer_inventory`, `envelope`, `local_config` /
  `global_config`, `tools`, `setup_wizard` / `wizard`.
- `transport/` — `relay_client` (WS to relay), `peer_channel`,
  `pi_forward_client` (cross-PC forward).
- `mesh/` — `canonical` (envelope canonicalization for signing), `siblings`
  (Pi-pubkey → sibling set), `verify`, `self_revoke` (polling mesh_versions
  and graceful exit), `encoding`, `types`.
- `pairing/` — `crypto` (Ed25519 challenge-response), `qr` (Pi-pubkey + room
  hint + single-use token), `storage` (`peers.json`).
- `daemon/` — `supervisor`, `supervisord` CLI, `cron_registry` / `cron_log`,
  `rpc_child`, `install`, `registry`, `id`, `client`. First-class
  long-running mode (see Open questions §3 in SPEC).
- `protocol/` — `types` (a narrow re-export of the generated protocol from
  `./generated/protocol.generated.ts`), `codec` (app↔Pi inner-message helpers),
  `relay_ingress` (bounded raw/base64 decode plus schema-generated outer,
  control, and cross-PC validation), `session_scope` (the `SESSION_SCOPED_*`
  registries), and `generated/` (canonical schema-derived TS unions,
  validators, parsers, limits, and type sets).
- `actions/` — `registry`, `handlers` (typed app actions → Pi SDK calls).
- `rooms.ts`, `config.ts`, `ui/footer.ts`, `mcp/mesh_server.ts`.

### app (`app/lib/`)

Flutter mobile. Clean architecture: `domain/` (contracts, entities, value
objects, use-cases) has no UI or infra imports; `data/` holds adapters
(transport, sync, mesh, local Hive, repositories); `ui/` is feature pages
with ViewModels + states.

- `protocol/` — `protocol.dart` (exports generated app↔Pi and relay-frame
  DTOs), `control_frames.dart` (adapts generated relay DTOs into app-domain
  control events), `codec.dart`, `uuid7.dart`.
- `data/transport/` — `ws_transport`, `connection_manager` (the app adapter
  over the shared reachability contract), `peer_channel`, `relay_config`,
  `epk_encoding`, `channel`.
- `data/sync/` — `sync_service` gates server messages by canonical session,
  converts `session_history` snapshots into transcript events, and replays them
  idempotently into the append-only store; it also recovers unconfirmed owner
  submissions from the encrypted room-scoped outbox after authoritative live
  room/session hydration. `sync_events` carries sync deltas.
- `data/mesh/` — `mesh_client`, `mesh_sync_service`, `mesh_blob`,
  `mesh_envelope` (cross-PC app-side state).
- `data/local/` — Hive boxes + records (`message_record`, `runtime_record`,
  `session_index_record`).
- `pairing/` — `qr_scanner`, `pair_request_flow`, `owner_identity_bridge`,
  `storage`.
- `ui/` — `chat`, `home`, `onboarding`, `pairing`, `settings`, `voice`,
  `update`, `sync_required`; each with `states/` + `viewmodels/` + `widgets/`.
- `domain/` — `contracts/` (ports), `entities/`, `value_objects/`,
  `session_state.dart`.

### relay (`relay/src/`)

Rust + axum. One binary, one port: WebSocket upgrade (`GET /`), health
(`GET /health`), mesh membership HTTP (`GET/POST /mesh/:hash`).

- `lib.rs` — `AppState` (registry, presence, rooms, mesh, mesh_auth, metrics)
  + router.
- `peers/registry.rs` — `PeerRegistry` (connected peers by pubkey/room).
- `presence.rs` — `PresenceManager` (subscribe/notify, dedup
  offline→online transitions).
- `rooms.rs` — `RoomManager`, generated `RoomMeta`, `RoomMetaPatch` (per-room
  metadata: schema-owned `model`, `thinking`, `session_id`, and `working` are
  shared by the TS and Dart projections; stack adapters may wrap these values or
  add transport fields such as `room_id`, `name`, `cwd`, and `started_at`).
- `mesh/` — `store` (SQLite `mesh_versions` cartulary, LWW + monotonic
  version anti-rollback), `handler`, `types`, `verify`.
- `auth/` — Ed25519 challenge-response (`challenge.rs`).
- `handlers/` — `peer` (WS upgrade), `pi_forward` (cross-PC
  `pi_envelope` → `pi_envelope_in` forwarding with sibling authorization via
  `MeshAuthCache`).
- `protocol/outer.rs` — serde structs for the outer envelope.
- `metrics.rs` — `FirehoseMetrics` (emit/suppress dedup counters).

### cockpit (`cockpit/lib/`)

Flutter desktop. `flutter_modular` modules/routes/binds, `shadcn_flutter`
UI, and versioned atomic JSON state behind `StateStoreFactory`. A one-shot
marker-last Hive reader preserves installed state but is not a live backend.

- `app/cockpit/data/` — `rpc/` (`pi_rpc_process` + factory + registry — the
  structured-control RPC client), `filesystem/` (file reader/searcher/mutator,
  folder lister, git status, worktree manager, session history, app launcher),
  `terminal/` (PTY gateway), `adapters/` (RPC data/event mappers),
  `repositories/` (state-store-backed project/layout/dismissed-update
  adapters), `update/`, `notifications/`, `setup/`.
- `app/cockpit/domain/` — `contracts/` (ports), `entities/` (agent snapshot,
  transcript message, file node, git info, etc.), `validators/`,
  `value_objects/`.
- `app/cockpit/ui/` — `cockpit_page`, `session/` (agent/file-viewer/terminal
  panes), `states/`, `viewmodels/`.

### site (`site/`)

Next.js App Router. Static/presentational marketing + docs. `src/app/`
(layout, page, opengraph-image), `src/components/` (header, footer, docs-shell,
install-tabs, code-block, callout, pager, tabs), `src/lib/` (`app-release`,
`cockpit-release` — read release manifests from GitHub; rp-s3 is dormant and
not currently deployed).

### rp-s3 (`rp-s3/`)

Dormant and not currently deployed. The source contains the Rust + axum
download-server implementation, but no running deployment or active
publication flow depends on it.

## Wire protocol shape

The wire is the single source of truth, defined once in canonical JSON Schema
and projected into TS, Dart, and Rust by protocol codegen
(`pi-extension/src/protocol/generated/`, `app/lib/protocol/generated/`,
`relay/src/protocol/generated/`). Generated types, validators/parsers,
directional DTOs, registries, and ingress limits replace handwritten wire
mirrors. App-domain control events remain handwritten adapters over generated
relay DTOs; they are not a second wire contract.

### The app↔pi chat wire

`ClientMessage` (app → pi) union: `pair_request`, `user_message` (with
optional `images` and `streaming_behavior`), `queued_message_set` /
`queued_message_clear`, `approve_tool`, `cancel`, `ping`, `session_sync`, and
typed actions `session_new` / `session_compact` / `model_set` /
`thinking_set` / `list_models`, plus the capture-upload sequence
`capture_upload_begin` / `capture_upload_chunk` / `capture_upload_end`.

`ServerMessage` (pi → app) union: `pair_ok` / `pair_error`, `user_input`
(echo) / `user_message`, `queued_message_state`, `agent_chunk` / `agent_done` /
`agent_message`, `tool_request` / `tool_result`, `error`, `cancelled`,
`pong`, `bye`, `session_history` (replay of `SessionHistoryEvent`), plus
`action_ok` / `action_error` / `models_list` /
`compaction` and capture-upload replies `capture_upload_ack` /
`capture_upload_error`. The generated type registries and decoders derive from
the same schema as every listed variant.

### The generic envelope (mesh + cross-PC)

```json
{ "from": "<sender>", "to": "<recipient>|[...]|broadcast",
  "id": "<UUIDv7>", "re": "<replied-id>|null", "body": <any JSON> }
```

Local UDS peers and cross-PC relay forwards use the same envelope shape.
Cross-PC wraps it in `pi_envelope` / `pi_envelope_in` frames carrying the
`to_pc` / `from_pc` Pi-pubkeys. The extension's live relay demux accepts these
frames only through schema-generated predicates, including non-empty recipient
arrays and reply ids plus `additionalProperties: false` at every defined
object boundary.

### Bounded relay ingress

`relay-outer.schema.json` owns the 4 MiB decoded `ct` default, 64 KiB frame
overhead, 5,657,944-byte derived raw ceiling, 16 KiB pre-auth ceiling, and
metadata limits. Its canonical outer type requires non-empty `peer`, `room`,
and `ct`; a generated endpoint `compat` predicate permits only `room` to be
absent for the pre-rewrite receive shape. Both predicates retain
`additionalProperties: false` and reject empty declared strings.

Rust applies WebSocket frame/message caps and typed Serde parsing. The extension
configures `ws.maxPayload`, checks raw size before `JSON.parse`, then uses the
generated outer/control/cross-PC predicates before base64 decoding. The relay
transport owns that decode once and publishes the same typed ingress object to
owner, peer-channel, and cross-PC subscribers. Flutter checks raw UTF-8 length
before `jsonDecode` and routes generated relay DTOs before base64 decoding, but
its WebSocket API cannot cap the platform's initial message allocation. Relay
deployment overrides do not raise the endpoints' generated 4 MiB safety
default.

### Cockpit↔pi control RPC

A separate transport: Pi custom events carrying structured
`outpost_pi_control` JSON envelopes — the canonical control path emitted by
Cockpit. The control methods and structured frames are part of the generated
protocol contract. The NUL-prefixed string form
(`\x00outpost-pi-ctrl:<method>:<args...>`) remains only as an extension-side
compatibility decoder (`CTRL_PREFIX`, `pi-extension/src/index.ts`); both forms
map to one dispatch path and are swallowed before reaching the LLM or
transcript.

## Session and room model

**Current truth.** The protocol carries a canonical `session_id` on every
session-scoped chat-bearing message (`user_input`, `agent_chunk`,
`agent_done`, `tool_result`, `session_history`, and related control traffic).
The pi-extension stamps the opaque `session_id` (resolved by
`RemoteSessionIssuer`) onto every session-scoped server push via
`_withCurrentSession(...)`; the app's `session_gate.dart` rejects scoped
messages missing/foreign session IDs (`missing_session_id`,
`session_mismatch`, `active_session_unknown`). The relay never parses or
routes by `session_id` — it is endpoint-owned opaque data. This is the
restored designed invariant (see DECISIONS → Session identity).

Cross-PC delivery is now room-targeted: `pi_envelope` carries a required
`to_room` and the relay routes via `send_to_room(to_pc, to_room)` (not the
former peer-wide fanout). Empty/missing `to_room` → `bad_envelope`.

`session_id` is the identity discriminator; `session_started_at` is only
same-session ordering/high-water metadata. Room metadata is the app's authority
for adopting a new canonical session. A `session_mismatch` reply is a
non-transcript convergence signal and never selects app state by itself. See
`docs/DECISIONS.md` → "Session and reachability model."

## Reachability

Reachability is one generated contract in
`protocol/schema/reachability.json`: `Connecting / Online / Degraded / Offline /
Retrying` plus the shared `[1, 2, 5, 10, 30]` backoff policy. The app,
extension, and relay project those values into stack-native state while keeping
transport-resource ownership local to each adapter.

## Lifecycle and convergence

Outpost-Pi's highest-risk defects are lifecycle and state-convergence bugs.
Invariants every surface must hold:

- **Pi SDK context is session-scoped.** It is invalid after session
  replacement (`/new`, `/resume`, `/fork`, `/reload`). Re-capture through
  `session_start` / `withSession` and guard old contexts.
- **`working` state converges false** after success, error, abort, compaction,
  reconnect, and shutdown — not only on success.
- **Reconnect hydration** re-applies state without duplicating or dropping
  messages; stale events from a prior session must not overwrite the current
  view (the contamination vector). Unconfirmed owner submissions remain in the
  app's encrypted outbox until a matching target-session confirmation is
  durable; recovery reuses the stable id and waits for fresh room liveness.
- **Flutter async UI** uses mounted guards after `await`; ViewModels and
  subscriptions close on their lifecycle boundary.
- **WebSockets, timers, spawned processes, and stream subscriptions** have an
  explicit owner and a teardown path.

The turn lifecycle is algebraic (`Idle / Working / AwaitingTool / Streaming /
Done / Error` with explicit transitions), and every UI projects from those
transitions. Transcript history is an append-only event log with derived
projections: snapshot hydration maps to deterministic events and replays them,
rather than replacing the active message box.

## Data flow (send a prompt, end to end)

1. App `chat_viewmodel` → `sync_service`, which records the optimistic
   transcript fact and persists a recoverable outbox intent before constructing
   `ClientMessage.user_message` → `ws_transport` → relay WS. If outbox
   persistence fails, the app fails visibly and does not create an untracked
   channel send.
2. Relay forwards by room to the paired pi-extension's WS.
3. Extension `session/bridge` maps to a Pi SDK `sendUserMessage` call
   (multimodal: images → text order). A restart fence instead returns
   `delivery_retry` before SDK handoff; after successor-room hydration the app
   retargets the durable entry and retries the original id. This is
   at-least-once recovery and may repeat intent across a hard crash boundary.
4. Pi streams `agent_chunk`s; bridge emits `ServerMessage.agent_chunk` → relay
   → app `sync_service` → `chat_viewmodel` → streaming bubble.
5. Tool calls emit `tool_request`; `tool_result` follows. (Approval is
   dormant in the app — tool calls execute directly per
   `plan/00-decisions.md`.)
6. `agent_done` terminates the turn; `working` must converge false.

Cross-PC: the same envelope flows as `pi_envelope` (Pi-A → relay) /
`pi_envelope_in` (relay → Pi-B), authorized via `MeshAuthCache` sibling lookup
and anti-spoof-checked at the receiving broker (`envelope.from` prefix must
match the `from_pc` pubkey's `pc_label`).

## Canonical architecture boundaries

The system now follows these stable boundaries:

- The JSON Schema is the wire source of truth; generated TS, Dart, and Rust
  types, validators, and registries consume it.
- `RemoteSession` identity is endpoint-owned, required on session-scoped
  traffic, and opaque to the relay; cross-PC routing targets a room.
- Reachability and turn lifecycle are named state contracts with stack-native
  projections rather than duplicated boolean conventions.
- Transcript state is an append-only event log. Live and replay paths use one
  deterministic event identity, and snapshot hydration is replay, not replace.
- Relay connection delivery, room state, presence transitions, and event
  publication have separate typed owners behind the `PeerRegistry` facade.
- The pi-extension entrypoint composes command, relay, owner, and SDK-session
  modules; runtime coordination prevents child session factories from taking
  ownership of the phone-facing SDK binding.
- Cockpit projects agent sessions and workspace documents through domain
  adapters instead of binding its UI directly to RPC/process payloads.
