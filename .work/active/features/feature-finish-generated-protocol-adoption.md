---
id: feature-finish-generated-protocol-adoption
kind: feature
stage: implementing
tags: [pi-extension, relay, cockpit, refactor, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-17
---

# Finish generated-protocol adoption and remove handwritten islands

## Brief

The `epic-bold-generated-protocol` arc shipped a schema source + TS/Dart/Rust
codegen pipeline and the generated `RelayControlFrame*` / `SERVER_MESSAGE_TYPES`
/ `CLIENT_MESSAGE_TYPES` registries. Adoption is incomplete: several surfaces
still hand-declare wire frames, hand-build discriminators, or re-enumerate
types the generated modules already export. These handwritten islands are a
second protocol definition that will drift from the schema. This feature removes
them by routing through the generated types:

- `gate-refactor-protocol-contract-relay-client-island` — reconcile handwritten `RelayClient` control-frame DTOs with generated schema (absorbed `gate-refactor-protocol-relay-client-control-dtos`, which named `RelayControlFrameHello/Auth/Challenge/RoomMetaUpdate`)
- `gate-refactor-protocol-room-meta-literal` — relay transport handwrites the `room_meta_update` discriminator
- `gate-refactor-protocol-outbound-frames-undocumented-island` — outbound control frames are an undocumented hand-maintained island
- `gate-refactor-protocol-handwritten-control-type-strings` — control handler repeats generated frame type strings for labels/limits
- `gate-refactor-protocol-session-scope-reenumeration` — session scope helpers re-enumerate generated message type strings

## Simplification opportunity

Delete the handwritten mirrors; import/derive from
`protocol.generated.ts` (TS), the generated Dart codegen, and the Rust Serde
types. One protocol source, derived everywhere — the single-source-of-truth rule
in `.agents/rules/code-design.md`. No observable wire change (generated types
are wire-equivalent).

## Source

Promoted from backlog by `scope` (2026-07-15). 5 `gate-refactor-protocol-*`
findings (one absorbed its duplicate during the groom dup pass) from the
v0.6.0 release `gate-refactor` (protocol-contract library). Continues the
shipped `epic-bold-generated-protocol` arc.

## Refactor Overview

Refactor-design pass (2026-07-16). All 5 findings current; 2 cited relay paths
moved (`connection_actor.rs` snapshots now `:217-243`; outbound registry events
at `registry_event_publisher.rs:41-154`). Generated Dart does NOT cover
cockpit-control, and there is no generated runtime discriminator/validator
suitable for drop-in — cockpit adoption is a separately-designed compatibility
decision, NOT folded into these child stories.

## Wire-equivalence verdicts (verified against schema + generated output)

| Replacement | Verdict |
|---|---|
| `AuthMsg` → `RelayControlFrameAuth` | ✅ equivalent (both `type:"auth"`+`sig:string`) |
| `ChallengeMsg` → `RelayControlFrameChallenge` | ✅ equivalent for successful challenges; relay pre-auth `{type:"error"}` is NOT generated — keep narrowed separately |
| `HelloMsg` → `RelayControlFrameHello` | ⚠️ NOT strictly equivalent — generated `room_meta` permits optional `name`/`cwd`, local `RoomMeta` requires them. Pure-refactor path: keep narrower `ConnectOptions.roomMeta` adapter contract + `satisfies RelayControlFrameHello` on the constructed frame. Broadening `RoomMeta` → feature-design. |
| `RoomMetaUpdateFrame` → generated | ⚠️ NOT strictly equivalent — local `room_id` required + patch non-null; generated `room_id` optional + patch nullable. Local type is UNUSED → delete. Emission stays equivalent by always supplying `room_id` + non-null patch. Widening port → feature-design. |
| Session-scope registries | ✅ membership-equivalent (schema `x-outpost-pi.profileRequired.canonical-session`; TS generator drops the metadata — fix the generator, not re-enumerate). |
| Relay handler label strings | ✅ equivalent (7 labels match generated variants + `RELAY_CONTROL_FRAME_TYPES`). |
| Schema-covered relay outbound frames | ✅ wire-equivalence preservable for `presence`/`peer_online`/`peer_offline`/`rooms`/`room_announced`/`room_ended` (preserve current null/omission behavior, esp. always-present `presence.states[].since_ts`). |
| `room_meta_updated` outbound frame | ❌ NO generated counterpart (absent from schema `oneOf` + relay fixture). Do NOT silently add under this refactor. Split/retag schema definition + codegen adoption for feature-design. |

## Behavior-changing findings to retag (NOT in this refactor)

- `room_meta_updated` schema definition + codegen adoption (no generated counterpart exists; feature-design must define the schema, generate codegen, verify exact current shape at `registry_event_publisher.rs:107-149`).
- Broadening `RoomMeta` optionality, widening the room-meta port to nullable patches.
- Cockpit control-string adoption (no generated runtime discriminator/validator; generated validation would reject extra properties the current permissive parser accepts — needs a separately-designed compatibility decision).
- Do not mark "generated-protocol adoption finished" until these explicitly non-equivalent gaps are resolved or durably declared out of scope.

## Refactor Steps

### Step 1: Replace relay-client auth DTO mirrors with generated contracts
**Priority:** High | **Risk:** Medium | **Source Lens:** elimination / pattern drift
**Files:** `pi-extension/src/transport/relay_client.ts`, `pi-extension/src/transport/relay_client.test.ts`
**Story:** `gate-refactor-protocol-contract-relay-client-island`

**Current State:** `relay_client.ts:35-63` declares private `HelloMsg`/`ChallengeMsg`/`AuthMsg`; constructs `hello`/`challenge`/`auth` literals typed against them. Also exports unused `RoomMetaUpdateFrame` (`:58-63`).

**Target State:**
```ts
import type { RelayControlFrameAuth, RelayControlFrameChallenge, RelayControlFrameHello } from "../protocol/generated/protocol.generated.js";

const hello = { type: "hello", pubkey: pubkeyB64, device_id: this.deviceId,
  ...(opts.roomId ? { room_id: opts.roomId } : {}),
  ...(opts.roomMeta ? { room_meta: opts.roomMeta } : {}),
} satisfies RelayControlFrameHello;

const parsedChallenge: unknown = JSON.parse(challengeRaw);  // preserve pre-auth {type:"error"} path
const challenge: RelayControlFrameChallenge = { type: "challenge", nonce: parsedChallenge.nonce };

const auth = { type: "auth", sig: Buffer.from(sig).toString("base64") } satisfies RelayControlFrameAuth;
```

**Implementation Notes:**
- Remove the 3 private DTO declarations.
- Retain `RoomMeta` + `ConnectOptions` as narrower transport-adapter input contract; do NOT broaden `name`/`cwd`/patch nullability.
- Parse challenge JSON as `unknown`; preserve existing `{type:"error", code?, message?}` handling (pre-auth response absent from generated union).
- Do NOT switch to generated strict validator unless unknown-property handling proven identical.
- Preserve exactly 2 auth sends + existing error messages.

**Acceptance Criteria:**
- [ ] `corepack pnpm typecheck` + `corepack pnpm exec vitest run src/transport/relay_client.test.ts` + `corepack pnpm build` pass.
- [ ] No `HelloMsg`/`ChallengeMsg`/`AuthMsg` declaration remains.
- [ ] Tests `relay_client.test.ts:86-126` prove same hello/auth JSON + challenge consumption.
- [ ] Emitted hello/auth frames byte-shape equivalent after JSON parse.
- [ ] Narrower `ConnectOptions.roomMeta` contract unchanged.

**Rollback:** Restore the 3 private interfaces + annotations; no schema/runtime migration.

### Step 2: Type room metadata emission through the generated frame and remove dead DTO code
**Priority:** High | **Risk:** Low | **Source Lens:** elimination / pattern drift
**Files:** `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/extension/relay_transport.test.ts`, `pi-extension/src/transport/relay_client.ts`
**Story:** `gate-refactor-protocol-room-meta-literal`

**Current State:** `relay_client.ts:58-63` exports unused `RoomMetaUpdateFrame`; `relay_transport.ts:315-320` sends untyped inline `{ type: "room_meta_update", room_id, meta: patch }`.

**Target State:**
```ts
import type { RelayControlFrameRoomMetaUpdate } from "../protocol/generated/protocol.generated.js";
const frame = { type: "room_meta_update", room_id: roomId, meta: patch } satisfies RelayControlFrameRoomMetaUpdate;
relay?.sendControl(frame);
```

**Implementation Notes:**
- Delete unused `RoomMetaUpdateFrame` export (`relay_client.ts:58-63`).
- Keep existing `sendRoomMeta` parameter (`relay_transport.ts:315-317`) — intentionally accepts narrower patch than generated schema.
- Always include `room_id` (generated permits omission; local requires it).
- Do NOT introduce `null` clearing.
- Add assertion to existing transport test that `sendControl` receives the exact current object.

**Acceptance Criteria:**
- [ ] Typecheck + targeted transport tests + build pass.
- [ ] `relay_transport.ts:320` has no untyped inline frame.
- [ ] No handwritten `RoomMetaUpdateFrame` remains.
- [ ] Sent JSON still contains exactly `type`+`room_id`+`meta`, unchanged omission inside `meta`.
- [ ] No caller gains nullable patch semantics.

**Rollback:** Restore deleted interface + inline literal; relay wire stays compatible.

### Step 3: Generate session-scope registries from schema metadata
**Priority:** High | **Risk:** Medium | **Source Lens:** missing abstraction / pattern drift
**Files:** `tools/protocol-codegen/src/index.ts`, `tools/protocol-codegen/src/index.test.ts`, `pi-extension/src/protocol/generated/protocol.generated.ts`, `pi-extension/src/protocol/session_scope.ts`, `pi-extension/src/protocol/session_scope.test.ts`
**Story:** `gate-refactor-protocol-session-scope-reenumeration`

**Current State:** `session_scope.ts:4-55` hand-maintains `SESSION_SCOPED_SERVER_TYPES`, `NON_SESSION_SCOPED_SERVER_TYPES`, `SERVER_MESSAGE_TYPES`, `SESSION_SCOPED_CLIENT_TYPES`. Generator retains fields/discriminator in `OutpostPiIrVariant` (`tools/protocol-codegen/src/index.ts:34-42`) but drops session-scope metadata when building variants (`:561-568`).

**Target State:** Extend TS IR variant with `sessionScoped` fact (derived from `x-outpost-pi.profileRequired["canonical-session"]` containing `session_id`); emit `SESSION_SCOPED_CLIENT_MESSAGE_TYPES` + `SESSION_SCOPED_SERVER_MESSAGE_TYPES` adjacent to generated `CLIENT_MESSAGE_TYPES`/`SERVER_MESSAGE_TYPES`. Facade re-exports; derive `NON_SESSION_SCOPED_SERVER_TYPES` from the generated full registry (no second handwritten list).

**Implementation Notes:**
- Preserve current predicate behavior; treat array order as non-contractual in tests (assert membership, disjointness, exhaustive union).
- `pair_ok` remains non-session-gated despite carrying session identity (lacks profile metadata; convergence/bootstrap response).

**Acceptance Criteria:**
- [ ] Protocol codegen tests pass; fresh TS generation produces no diff.
- [ ] `session_scope.ts` contains no protocol discriminator literals.
- [ ] Scoped + non-scoped sets disjoint; union = generated `SERVER_MESSAGE_TYPES`.
- [ ] Generated scoped client/server membership = current arrays asserted at `session_scope.test.ts:12-46`.
- [ ] `session_gate.dart` behavior unchanged for `pair_request`/`ping`/`session_sync`/stale-session commands.
- [ ] Pi-extension typecheck + targeted tests + build pass.

**Rollback:** Revert generator metadata/output + restore local arrays. No persisted/transmitted data changes.

### Step 4: Generate relay-control wire labels and remove handler literals
**Priority:** High | **Risk:** Low | **Source Lens:** missing abstraction / pattern drift
**Files:** `tools/protocol-codegen/bin/protocol-codegen.mjs`, `relay/src/protocol/generated/control.rs`, `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`
**Story:** `gate-refactor-protocol-handwritten-control-type-strings`

**Current State:** `relay/src/handlers/control.rs:74-143` repeats the 7 generated inbound variant labels as string literals ("subscribe_presence", etc.) for limit/rate-limit helpers.

**Target State:** Generate `wire_type()` method on `RelayControlFrame` in `emitRustControl` (beside `RELAY_CONTROL_FRAME_TYPES`, emitter at `protocol-codegen.mjs:831-940`); pass the generated label through helpers.
```rust
impl RelayControlFrame {
  pub const fn wire_type(&self) -> &'static str {
    match self {
      Self::SubscribePresence { .. } => "subscribe_presence",
      // ... 7 variants ...
    }
  }
}
// handler: let frame_type = frame.wire_type();
```

**Implementation Notes:**
- Preserve log fields + `ControlFrameError` text exactly.
- Do NOT use positional indexing into `RELAY_CONTROL_FRAME_TYPES`.
- Keep generated dispatch-coverage test `connection_actor.rs:383-404`; add assertion each variant's `wire_type()` ∈ generated registry.

**Acceptance Criteria:**
- [ ] `node --check tools/protocol-codegen/bin/protocol-codegen.mjs` passes.
- [ ] `corepack pnpm --dir protocol generate:rust:check` passes.
- [ ] `cargo fmt --check` + `cargo clippy -- -D warnings` + `cargo test` pass from `relay/`.
- [ ] No inbound relay-control discriminator literal remains in production `handlers/control.rs`.
- [ ] Oversized-frame errors + control-check logs retain previous frame labels.
- [ ] Every generated inbound variant has one generated wire label.

**Rollback:** Revert generated method + restore local string arguments. No wire frame changed.

### Step 5: Generate and adopt schema-covered relay outbound frames
**Priority:** High | **Risk:** Medium | **Source Lens:** code smell / missing abstraction / pattern drift
**Files:** `protocol/schema/relay-control.schema.json`, `tools/protocol-codegen/bin/protocol-codegen.mjs`, `relay/src/protocol/generated/control.rs`, `relay/src/peers/registry_event_publisher.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/presence.rs`, `relay/tests/protocol_parity_test.rs`
**Story:** `gate-refactor-protocol-outbound-frames-undocumented-island`

**Current State:** `connection_actor.rs:217-243` + `registry_event_publisher.rs:41-154` construct outbound frames via `serde_json::json!({...})` maps; `room_announced` built by serializing `RoomMeta` + mutating `type`/`peer` (`registry_event_publisher.rs:47-50`).

**Target State:** Generate `RelayServerControlFrame` Serialize enum for schema-defined relay-to-client variants (`presence`/`peer_online`/`peer_offline`/`rooms`/`room_announced`/`room_ended`); replace `serde_json::json!` with `serde_json::to_string(&RelayServerControlFrame::PeerOffline { peer, since_ts })`.

**Implementation Notes:**
- Add schema metadata identifying client-to-relay vs relay-to-client variants (NOT a second hardcoded direction list in the generator).
- Keep inbound deserialization restricted to existing 7 client frames (a single all-variant deserializer would let clients submit server-only frames → boundary behavior change).
- Preserve current serialization details: `presence.states[].since_ts` present as number-or-null; optional `RoomMeta` strings omitted when absent; `working`+`started_at` required; no extra keys.
- Replace production `serde_json::json!`/map mutation ONLY after fixture round-trip tests prove equality as `serde_json::Value`.
- Leave `room_meta_updated` handwritten + add concise local comment (outside canonical schema; migrates only after its schema/codegen feature lands). Split/retag that for feature-design.

**Acceptance Criteria:**
- [ ] Fresh Rust generation deterministic + matches committed generated output.
- [ ] Relay-control fixtures round-trip through every newly generated outbound DTO.
- [ ] Existing registry behavior tests `registry.rs:612-716` green.
- [ ] Snapshot outputs `connection_actor.rs:217-243` JSON-value equivalent before/after.
- [ ] `room_announced`/`room_ended`/`peer_online`/`peer_offline`/`presence`/`rooms` production construction uses generated serializers.
- [ ] `room_meta_updated` unchanged on wire + explicitly documented as the one excluded schema gap.
- [ ] Full relay fmt/lint/tests/build pass.

**Rollback:** Restore handwritten serializers (generated outbound types independently retained or reverted). No schema-required field/wire-shape change → no deployment migration.

## Implementation Order

1. **Step 3** — generated session-scope registries (establish missing TS generator projection before deleting local registries).
2. **Step 1** — relay-client auth DTO adoption (consume already-generated auth contracts; preserve narrower adapter contract).
3. **Step 2** — room metadata emission (build on generated relay-client typing; remove unused DTO).
4. **Step 4** — generated Rust wire labels (small, independently verifiable Rust generator enhancement).
5. **Step 5** — schema-covered outbound Rust frames (largest/highest-risk; land after Rust generator's discriminator API stable).
6. **Feature-design follow-up (NOT this refactor):** define/generate `room_meta_updated` + decide compatibility-preserving cockpit/Dart adoption. Do not mark "generated-protocol adoption finished" until these explicitly non-equivalent gaps are resolved or durably declared out of scope.
