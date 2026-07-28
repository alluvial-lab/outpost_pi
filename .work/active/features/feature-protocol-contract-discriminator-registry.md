---
id: feature-protocol-contract-discriminator-registry
kind: feature
stage: implementing
tags: [pi-extension, app, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-28
updated: 2026-07-28
---

# Protocol-contract discriminator single-source-of-truth

## Brief
Five `gate-refactor` findings (scan library `protocol-contract`, rules
`handwritten-type-string` and `undocumented-protocol-island`) identify the same
divergence across three components: handwritten message/control discriminators
that duplicate the generated `relayControlTypes` / server-message registries,
plus one binary owner-channel format maintained by hand outside the schema IR.

- `gate-refactor-protocol-contract-relay-client-hello-auth-literals` —
  `pi-extension/src/transport/relay_client.ts:221` handwrites hello/auth
  discriminators already in the generated registry.
- `gate-refactor-protocol-contract-relay-transport-control-literals` —
  `pi-extension/src/extension/relay_transport.ts:560` handwrites
  `room_meta_update` and `subscribe_presence`.
- `gate-refactor-protocol-contract-session-projection-type-literals` —
  `pi-extension/src/session/sdk_session_projection.ts:515` handwrites
  `user_input`, `agent_message`, `session_history`, `queued_message_state`,
  `user_message`.
- `gate-refactor-protocol-contract-sync-user-input-handwritten` —
  `app/lib/data/sync/sync_service.dart:1030` hardcodes `user_input`,
  duplicating `generatedServerMessageTypes`.
- `gate-refactor-protocol-contract-owner-channel-binary-island` —
  `pi-extension/src/transport/secure_channel.ts:8` maintains the AEAD
  byte format by hand outside the schema IR with no documented rationale.

## Simplification opportunity
Collapse five handwritten discriminator sites onto keyed generated constants
(or, for the binary island, a canonical manifest/codegen source or a
documented "intentionally outside JSON Schema" rationale). Removing the
duplicates eliminates a class of future drift where a wire rename updates the
schema but not the hand-written call sites.

## Design notes
The scan libraries declare `findings-route: none` (fixes are not black-box-
preserving in all cases — the binary-island item may be a documentation-only
change), so this feature routes through normal feature/story design rather
than `refactor-design`. The design pass should:
1. Confirm where generated keyed discriminator constants live today
   (`protocol/generated/protocol.generated.ts` and the app/relay mirrors).
2. Decide whether to add a single `typeOfServerMessage(msg)`-style helper or
   keyed `MESSAGE_TYPES` constants, consumed by all five sites.
3. For the binary-island item, decide: document the intentional exclusion in
   the pattern's "When NOT to Use" + a canonical contract reference, OR add a
   binary-format manifest. The owner-channel AEAD format is genuinely outside
   JSON Schema; a documentation outcome is likely correct.
4. Coordinate with `gate-patterns-inconsistency-pair-request-flow-typed-decoder`
   (same `typed-wire-decoders` concern on the app pairing path) — that story
   is advancing independently but shares the generated-decoder direction.

## Children
- `gate-refactor-protocol-contract-relay-client-hello-auth-literals`
- `gate-refactor-protocol-contract-relay-transport-control-literals`
- `gate-refactor-protocol-contract-session-projection-type-literals`
- `gate-refactor-protocol-contract-sync-user-input-handwritten`
- `gate-refactor-protocol-contract-owner-channel-binary-island`

## Design decisions

- **Discriminator access shape**: Extend the generated TypeScript relay-control family with a keyed `RELAY_CONTROL_DISCRIMINATORS` object; use the already-generated `SERVER_MESSAGE_DISCRIMINATORS` object for session projection and the already-generated Dart `typeOfServerMessage(ServerMessage)` helper for the app. Positional `relayControlTypes[index]` access is rejected because array order is not a meaningful API and would merely replace string drift with index drift.
- **Generated source ownership**: Add the relay-control keyed registry in `tools/protocol-codegen/src/index.ts`, test the emitter, and regenerate `pi-extension/src/protocol/generated/protocol.generated.ts`; do not hand-maintain a facade constant next to consumers.
- **Owner-channel binary island**: Keep the AEAD byte format outside JSON Schema. Document the narrow scanner exception and point `secure_channel.ts` at the canonical byte contract in `PROTOCOL.md` plus the independent cross-language KAT in `protocol/fixtures/app-pi/owner-channel-kat.json` and its generator. A new binary manifest would duplicate a mature, byte-tested contract without any current generator consumer.
- **Wire compatibility**: This is a provenance-only change. Every emitted `type` value and every owner-channel byte remains identical; test expectations may continue to use literal wire strings because contract tests are deliberately independent of production constants.
- **Pairing decoder coordination**: `gate-patterns-inconsistency-pair-request-flow-typed-decoder` is already done and established the generated Dart decoder/helper direction. This feature reuses that surface rather than adding another app-local discriminator abstraction.

## Architectural choice

Use schema-derived keyed constants at construction sites and object-derived type lookup after typed decoding. The TypeScript code generator already emits `SERVER_MESSAGE_DISCRIMINATORS`, while Dart already exposes `typeOfServerMessage`; only relay control lacks a keyed generated projection. Add that missing projection once, consume it in both relay-control senders, and leave the relay's generated Rust Serde types unchanged because no schema or wire shape changes.

Two alternatives were rejected. Indexing `relayControlTypes` would be minimal but brittle and unnamed. Adding a universal discriminator helper or binary-format manifest would introduce new concepts across languages even though the existing generated surfaces already solve each language's actual use case. The bounded source map was clear, so this design used direct reading without an Explore delegation. There is no UI surface.

## Implementation Units

### Unit 1 (trickiest): Generate keyed relay-control discriminators and consume hello/auth

**Story**: `gate-refactor-protocol-contract-relay-client-hello-auth-literals`

**Files**:
- `tools/protocol-codegen/src/index.ts`
- `tools/protocol-codegen/src/index.test-cases.ts`
- `pi-extension/src/protocol/generated/protocol.generated.ts` (regenerated, never hand-edited)
- `pi-extension/src/transport/relay_client.ts`
- `pi-extension/src/transport/relay_client.test.ts`

**Generated interface**:

```ts
export const RELAY_CONTROL_DISCRIMINATORS = {
  hello: "hello",
  auth: "auth",
  challenge: "challenge",
  // ...one keyed entry for every relayControlTypes variant...
  room_meta_updated: "room_meta_updated",
} as const;
```

`renderTypeScriptProtocol(ir: OutpostPiIr): string` remains the emitter boundary. Its relay-control branch must derive the object from `OutpostPiIrFamily.variants` through the existing `emitDiscriminatorRegistry(...)` path, next to `relayControlTypes`; no second handwritten variant list is introduced.

Consumer construction remains typed:

```ts
const hello = {
  type: RELAY_CONTROL_DISCRIMINATORS.hello,
  // existing fields unchanged
} satisfies RelayControlFrameHello;

const auth = {
  type: RELAY_CONTROL_DISCRIMINATORS.auth,
  // existing fields unchanged
} satisfies RelayControlFrameAuth;
```

**Implementation notes**:
- Preserve the existing `relayControlTypes` export and `RelayControlType` union for validators and callers; the keyed object is an additional projection from the same IR variants.
- Extend the codegen test module shape and assertions to prove every emitted key maps to its identical wire value, including `hello`, `auth`, `room_meta_update`, and `subscribe_presence`.
- Keep literal expectations in `relay_client.test.ts`; they independently prove wire equivalence rather than echoing the implementation constant.

**Acceptance criteria**:
- [ ] `RELAY_CONTROL_DISCRIMINATORS` is generated from the relay-control IR and contains exactly the same variants as `relayControlTypes`.
- [ ] Relay hello/auth construction imports `.hello` and `.auth`; no runtime `type: "hello"` or `type: "auth"` remains in `relay_client.ts`.
- [ ] Existing hello/auth tests observe byte-for-byte equivalent parsed frames and the same two-send authentication sequence.
- [ ] `corepack pnpm check:protocol` from `pi-extension/` reports the generated TypeScript artifact is current.

---

### Unit 2: Consume generated server-message discriminators in session projection

**Story**: `gate-refactor-protocol-contract-session-projection-type-literals`

**Files**:
- `pi-extension/src/session/sdk_session_projection.ts`
- `pi-extension/src/session/sdk_session_projection.test.ts`

**Existing generated interface to consume**:

```ts
import { SERVER_MESSAGE_DISCRIMINATORS } from "../protocol/generated/protocol.generated.js";

const type: typeof SERVER_MESSAGE_DISCRIMINATORS.user_input =
  SERVER_MESSAGE_DISCRIMINATORS.user_input;
```

All constructed `type` fields in this projection use the keyed values:
`user_input`, `agent_message`, `session_history`, `queued_message_state`, and
`user_message`. Existing `Extract<...>` return and callback signatures remain
unchanged, for example:

```ts
buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: "session_history" }>;
```

**Implementation notes**:
- Change runtime object construction only; type-level discriminant literals in `Extract` constraints remain legitimate compile-time narrowing and are not competing wire registries.
- `user_message` is present in the generated server registry as the schema-owned shared/alias discriminator, so no separate client-message constant object is needed.
- Cover both non-empty and empty history, both queued-state branches, live user/assistant broadcasts, and queued-message drain construction.

**Acceptance criteria**:
- [ ] The five listed runtime discriminator values are read from `SERVER_MESSAGE_DISCRIMINATORS` everywhere this projection constructs them.
- [ ] Projection tests still observe identical message types, session IDs, replay events, queued state, and live identity behavior.
- [ ] Strict TypeScript inference continues to satisfy every `ServerMessage`/`ClientMessage` `Extract` boundary without casts.

---

### Unit 3: Derive app live-user identity from the matched generated message

**Story**: `gate-refactor-protocol-contract-sync-user-input-handwritten`

**Files**:
- `app/lib/data/sync/sync_service.dart`
- `app/test/data/sync/sync_service_test.dart`

**Existing generated signature to consume**:

```dart
String typeOfServerMessage(ServerMessage message) => message.type;
```

Inside `_onServerMessage(ServerMessage msg, [String? originEpk])`, the `UserInput` case derives the replay identity discriminator from `msg`:

```dart
final messageType = typeOfServerMessage(msg);
final userEventId = ts != null
    ? serverReplayEventId(
        _activeTranscriptSessionId(),
        messageType,
        id,
        ts,
      )
    : 'server:user_confirmed:$id';
```

**Implementation notes**:
- Do not add a `userInputWireType` constant: the generated polymorphic object already carries the canonical discriminator and the helper is used elsewhere in this service/session gate.
- Preserve the legacy `ts == null` fallback exactly; this change only replaces the type argument on the deterministic path.

**Acceptance criteria**:
- [ ] The live `UserInput(ts)` path passes `typeOfServerMessage(msg)` (or a local derived from it) to `serverReplayEventId`; the handwritten `'user_input'` is removed from production code at this site.
- [ ] Live `UserInput(ts)` and replay `UserInputEvt` still collapse to one event-store row with the same deterministic ID.
- [ ] Legacy no-`ts` echo confirmation behavior is unchanged.

---

### Unit 4: Document the owner-channel binary contract exception

**Story**: `gate-refactor-protocol-contract-owner-channel-binary-island`

**Files**:
- `pi-extension/src/transport/secure_channel.ts`
- `.agents/skills/scan-protocol-contract/references/undocumented-protocol-island.md`

**Documentation contract**:

```ts
/**
 * Keep owner-channel framing outside JSON Schema: it is a byte-level AEAD
 * construction, not a JSON message family. `PROTOCOL.md` is the canonical
 * format contract; `protocol/fixtures/app-pi/owner-channel-kat.json` pins the
 * cross-language bytes via its independent generator.
 */
const FRAME_VERSION = 0x01;
```

Add a `## When NOT to Use` rule subsection stating that the undocumented-island finding does not apply when all of these are true: the format is non-JSON binary/cryptographic framing, a durable canonical contract specifies its bytes and security semantics, the implementation links that contract, and an independent cross-language KAT pins exact bytes. The exemption must name this owner-channel site as the concrete example and must not exempt ordinary handwritten JSON DTOs.

**Implementation notes**:
- `PROTOCOL.md` already specifies `0x01 || seqLE64 || nonce24 || ciphertext+tag`, AAD, replay, derivation, and transcripts; link it rather than duplicating the full protocol in the source comment.
- The existing fixture and `protocol/scripts/generate-owner-channel-kat.ts` are the executable canonical byte reference. Do not add a second manifest or alter framing constants.

**Acceptance criteria**:
- [ ] A future scanner can tell why `secure_channel.ts` is intentionally outside the JSON Schema IR and where the canonical byte contract lives.
- [ ] The exception is narrow enough that undocumented JSON wire types remain findings.
- [ ] The TypeScript and Dart owner-channel KAT tests remain byte-for-byte unchanged.
- [ ] No production code or wire byte changes in this unit.

---

### Unit 5: Consume keyed relay-control discriminators in relay transport

**Story**: `gate-refactor-protocol-contract-relay-transport-control-literals`

**Depends on**: `gate-refactor-protocol-contract-relay-client-hello-auth-literals` (Unit 1 generates the keyed registry)

**Files**:
- `pi-extension/src/extension/relay_transport.ts`
- `pi-extension/src/extension/relay_transport.test.ts`

**Typed constructions**:

```ts
const roomMetaFrame = {
  type: RELAY_CONTROL_DISCRIMINATORS.room_meta_update,
  room_id: roomId,
  meta: patch,
} satisfies RelayControlFrameRoomMetaUpdate;

const presenceFrame = {
  type: RELAY_CONTROL_DISCRIMINATORS.subscribe_presence,
  peers: [...peers],
} satisfies RelayControlFrameSubscribePresence;
```

**Implementation notes**:
- Import `RELAY_CONTROL_DISCRIMINATORS` and the generated subscribe-presence frame type from the generated module.
- Retain `sendControl` best-effort behavior and all room/presence lifecycle behavior; only discriminator provenance changes.
- Keep literal expectations in transport tests as independent wire assertions.

**Acceptance criteria**:
- [ ] `sendRoomMeta` uses `.room_meta_update` and `subscribePresence` uses `.subscribe_presence` from the generated keyed registry.
- [ ] Both objects satisfy their generated outbound frame interfaces without casts.
- [ ] Existing transport tests observe the exact same `{type, room_id/meta}` and `{type, peers}` frames.

## Implementation Order

1. `gate-refactor-protocol-contract-relay-client-hello-auth-literals` — add/test/regenerate `RELAY_CONTROL_DISCRIMINATORS`, then migrate hello/auth.
2. `gate-refactor-protocol-contract-session-projection-type-literals` — consume the already-present server keyed registry (independent of Unit 1).
3. `gate-refactor-protocol-contract-sync-user-input-handwritten` — consume the already-present Dart helper (independent of Unit 1).
4. `gate-refactor-protocol-contract-owner-channel-binary-island` — land the narrow documented exception (independent of code units).
5. `gate-refactor-protocol-contract-relay-transport-control-literals` — consume the relay keyed registry after Unit 1.

Units 2-4 may run in parallel with Unit 1 under one feature owner; only Unit 5 has a sibling dependency.

## Simplification

- Remove all identified runtime handwritten discriminator occurrences across the four consumer sites instead of adding source-local constants or wrapper helpers.
- Reuse `SERVER_MESSAGE_DISCRIMINATORS` and `typeOfServerMessage` rather than expanding the API surface.
- Retain `relayControlTypes`, the existing generated wire interfaces, and literal test expectations because each still serves a distinct registry/type or independent-contract role.
- Do not add a binary manifest: `PROTOCOL.md` plus the independently generated cross-language KAT already form the durable/executable owner-channel contract.
- No relay Rust source or foundation-doc assertion needs changing; the schema and wire remain unchanged.

## Testing

- **Codegen contract**: from `protocol/`, run `corepack pnpm check`; extend `tools/protocol-codegen/src/index.test-cases.ts` to compare `RELAY_CONTROL_DISCRIMINATORS` with the generated relay-control variant list and assert representative keyed values. This protects one-source generation rather than a consumer implementation detail.
- **TypeScript wire equivalence**: run targeted Vitest suites for `src/transport/relay_client.test.ts`, `src/extension/relay_transport.test.ts`, `src/session/sdk_session_projection.test.ts`, then `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` from `pi-extension/`. Existing literal frame assertions intentionally prove emitted wire values did not change.
- **Dart identity equivalence**: run `flutter test test/data/sync/sync_service_test.dart --concurrency=2`, then `flutter analyze` and `flutter test --exclude-tags e2e --concurrency=2` from `app/`. The live/replay collapse regression protects deterministic identity, not merely helper invocation.
- **Binary contract**: run `pi-extension/src/transport/secure_channel.test.ts`, `app/test/data/transport/secure_channel_test.dart`, and `corepack pnpm check` in `protocol/`; all must reproduce the existing fixture byte-for-byte with no fixture update.
- **Relay compatibility**: run `cargo test` from `relay/` (and the standard `cargo fmt --check` / `cargo clippy -- -D warnings` checks) to confirm its generated Serde boundary continues to accept the unchanged frame values.
- **Test removal**: none. Existing literal wire assertions and KATs are valuable independent checks, not duplicate implementation-bound tests.

## Risks

- **Riskiest assumption — the keyed relay registry can be added without disturbing generator naming**: `relayControlTypes` currently follows the generic family path while only server messages receive a keyed object. A careless change could rename existing exports or emit duplicate validators. Mitigation: add only `RELAY_CONTROL_DISCRIMINATORS` beside the existing registry, assert exact key/value parity in codegen tests, regenerate, and run `check:protocol` plus TypeScript typecheck.
- **Dart helper availability**: direct mapping confirmed `typeOfServerMessage(ServerMessage)` already exists in generated code and is already consumed by `SyncService`/`SessionGate`; the implementation must reuse it rather than modifying Dart codegen. If promotion inside the `UserInput` switch case causes analyzer trouble, derive `final messageType = typeOfServerMessage(msg)` before the switch and reuse it; no API fallback is needed.
- **Exception becoming a loophole**: a broad “binary is exempt” note could hide future drift. Require all four safeguards (non-JSON format, durable byte spec, source link, independent cross-language KAT) and keep ordinary JSON frame islands in scope.
- **False confidence from constant-based tests**: tests that import the production constant cannot prove wire equivalence. Preserve literal expectations and the independently generated fixture so accidental schema value changes remain visible.

## Open questions

None. The existing generated exports, canonical protocol documentation, and KAT settle the reversible design choices without product-direction changes.
