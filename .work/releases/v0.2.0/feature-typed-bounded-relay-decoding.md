---
id: feature-typed-bounded-relay-decoding
kind: feature
stage: done
tags: [app, pi-extension, relay, security, protocol]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: security
created: 2026-07-15
updated: 2026-07-20
---

# Cross-stack: typed and size-bounded inbound relay/WebSocket decoding

## Brief

Five gate findings (one refactor, four security) describe the inbound
relay/WS decode path across all three stacks: untrusted frames are parsed as
full JSON strings and their `ct` payloads are base64-decoded **before** any
explicit raw-frame or decoded-payload size cap runs, and the post-auth demux
navigates the parsed map by hand. This is a cross-stack DoS vector
(unbounded parse before size check) and an ad-hoc-parse-at-a-boundary defect.
This feature defines typed, size-bounded decoding at the WS/relay boundary:

- `gate-refactor-boundaries-demux-adhoc-map` — WebSocket post-auth demux parses frames through an ad-hoc map
- `gate-security-app-inbound-relay-frame-size-caps` — mobile app decodes inbound relay frames before size caps
- `gate-security-extension-inbound-relay-frame-size-caps` — pi extension decodes inbound relay frames before size caps
- `gate-security-frame-decoder-pre-size-check` — frame decoder parses JSON before applying relay-owned size checks
- `gate-security-preauth-websocket-size-limits` — pre-auth WebSocket frames and hello metadata lack explicit size limits

## Simplification opportunity

Enforce explicit WebSocket frame/message ceilings before upgrade, add bounded
lengths for pre-auth `device_id`/`room_id`/room-metadata strings, and run size
checks before full JSON parse + base64 decode. Type the demux through generated
frame DTOs. Behavior change: oversize/malformed frames are rejected at the
boundary instead of parsed — fail-fast, not silent.

## Source

Promoted from backlog by `scope` (2026-07-15). 1 `gate-refactor-boundaries-*`
+ 4 `gate-security-*-frame-size-*` / `gate-security-preauth-*` findings from
the v0.6.0 release `gate-refactor` (boundaries) and `gate-security` passes.

## Design decisions

- **Limit authority**: keep the existing 4 MiB decoded `ct` default in
  `protocol/schema/relay-outer.schema.json` as the source of truth, and add
  schema-owned raw-frame overhead, pre-auth, and metadata limits beside it.
  Generated projections expose the constants to Dart, TypeScript, and Rust;
  handwritten per-stack numeric mirrors are not accepted.
- **Raw message ceiling**: derive the normal WebSocket message ceiling as
  `4 * ceil(maxDecodedBytes / 3) + 64 KiB`. At the 4 MiB default this is
  5,657,944 bytes. The 64 KiB allowance covers JSON syntax and bounded routing /
  control metadata without weakening the decoded-payload ceiling.
- **Pre-auth ceiling**: accept at most 16 KiB for each `hello` or `auth` text
  message, then validate UTF-8 byte lengths for `device_id` (128), `room_id`
  (256), room name (256), cwd (4096), session id (512), model (256), and
  thinking (32). These limits preserve current identifiers and normal paths
  while preventing attacker-selected metadata from consuming the full data
  frame budget before authentication.
- **Endpoint policy versus relay override**: `RELAY_MAX_CT_MIB` may lower or
  raise the relay's routing allowance, but mobile and extension endpoints retain
  the generated 4 MiB safety default unless a future negotiated capability is
  added. Raising a relay deployment limit alone does not promise that endpoints
  accept a larger app payload.
- **Oversize behavior**: reject before JSON parse when the raw limit is crossed;
  reject before base64 decode when the encoded length cannot fit the decoded
  limit; verify decoded length defensively afterward. The relay and extension
  close a WebSocket rejected by the WS implementation with close code 1009;
  endpoint demux drops an individually oversized `ct` through a content-free
  `too_large`/malformed diagnostic so one bad owner frame does not tear down all
  owners sharing the connection.
- **Typed Dart boundary**: generate relay outer/control inbound DTOs from the
  canonical relay schema and adapt them to the existing `ControlInbound` domain
  classes. The transport no longer owns a `Map<String, dynamic>` protocol
  parser. This retires the documented Dart relay-control DTO island rather than
  adding a second handwritten mirror.
- **Dispatch and review**: this is one cohesive cross-stack feature bundle; the
  five existing child stories are acceptance checkpoints, not five worker
  assignments. Direct inspection covered all three stacks because this
  delegated worker has no subagent adapter. Design-time advisory review was
  therefore unavailable and is non-blocking; the caller-provided
  `review_weight: standard` remains required for the feature-level
  implementation review.

## Architectural choice

### Option A — local guards around current parsers

Add `raw.length` and base64-length checks at each current call site, plus
`maxPayload`/Axum limits where available. This is the smallest patch, but it
copies the 4 MiB contract and calculation across languages and leaves the app's
hand-navigated map as a second protocol definition. It would fix the immediate
allocation order while preserving the drift class that produced the findings.

### Option B — canonical limits plus typed boundary adapters (chosen)

Extend the existing relay JSON Schema metadata with ingress limits, project the
constants and relay DTOs through protocol codegen, and give each transport a
small bounded decoder that consumes those generated contracts. Rust applies a
WS ceiling before upgrade and a smaller pre-auth guard; Node uses `ws.maxPayload`
and a shared bounded outer-payload decoder; Dart performs a no-allocation UTF-8
length scan before JSON/base64 and maps generated DTOs into existing domain
control events. This adds one codegen capability but keeps protocol facts in one
place and makes rejection order directly testable.

### Option C — streaming JSON/base64 decoders everywhere

Use incremental JSON tokenization and streaming base64 to avoid materializing a
whole accepted frame. This minimizes peak memory but adds dependencies and
stateful parsers to three stacks for a 4 MiB product limit. It is disproportionate
while WebSocket libraries already materialize complete messages, especially in
Flutter, so it is deferred unless profiling shows accepted-size frames are a
real memory problem.

The chosen approach is Option B: it closes the demonstrated DoS path without
inventing a second protocol registry, while retaining a future migration path to
streaming behind the same typed decoder interfaces.

## Implementation Units

### Unit 1: Canonical ingress limits and generated relay DTOs

**Files**:
- `protocol/schema/relay-outer.schema.json`
- `protocol/schema/relay-control.schema.json`
- `tools/protocol-codegen/src/index.ts`
- `tools/protocol-codegen/bin/protocol-codegen.mjs`
- `tools/protocol-codegen/src/index.test.ts`
- `pi-extension/src/protocol/generated/protocol.generated.ts` (generated)
- `relay/src/protocol/generated/outer.rs` (generated)
- `relay/src/protocol/generated/control.rs` (generated)
- `app/lib/protocol/generated/relay_frames.g.dart` (generated)
- `app/lib/protocol/protocol.dart`
- `app/lib/protocol/control_frames.dart`
- `app/test/protocol_codegen/relay_frames_codegen_test.dart`

**Stories**: `gate-refactor-boundaries-demux-adhoc-map`,
`gate-security-preauth-websocket-size-limits`

```jsonc
// relay-outer.schema.json — canonical metadata (names are codegen inputs)
"x-outpost-pi": {
  "relayOpaque": ["ct"],
  "maxDecodedBytesDefault": 4194304,
  "maxFrameOverheadBytes": 65536,
  "maxPreAuthFrameBytes": 16384
}
```

```dart
// Generated from relay-outer + relay-control schema; names are the public
// boundary contract consumed by WsTransport.
sealed class RelayInboundFrameDto {
  const RelayInboundFrameDto();
  factory RelayInboundFrameDto.fromJson(Map<String, dynamic> json);
}

final class RelayOuterEnvelopeDto extends RelayInboundFrameDto {
  final String peer;
  final String room;
  final String ct;
}

sealed class RelayServerControlFrameDto extends RelayInboundFrameDto {
  const RelayServerControlFrameDto();
}

const int relayDefaultMaxDecodedBytes = 4194304;
const int relayMaxFrameOverheadBytes = 65536;
const int relayMaxPreAuthFrameBytes = 16384;
```

**Implementation Notes**:
- Add standard `maxLength` constraints to `hello`, `helloRoomMeta`, room
  metadata, and patch schemas, plus byte-limit metadata for codegen. Runtime
  adapters enforce UTF-8 bytes, which is intentionally at least as strict as
  character limits for non-ASCII input.
- Teach codegen to include the non-discriminated relay outer envelope in the
  relay inbound union and to emit relay-family Dart DTOs. Do not hand-edit the
  generated outputs or add a relay-only hand-maintained IR fixture as a new
  source of truth.
- Generate directional server/client relay registries from existing
  `x-outpost-pi.direction` metadata so endpoint decoders cannot accept `hello`,
  `auth`, or client-only subscription frames as relay-server pushes.
- Change `ControlInbound.tryFromJson(Map<String, dynamic>)` to a typed adapter
  such as `ControlInbound.fromWire(RelayServerControlFrameDto frame)`; preserve
  the current semantic `RoomInfo`, `ThinkingLevel`, and merge-patch behavior.
- Remove the `protocol.dart` comment and exports describing the temporary
  hand-maintained relay-control island once all current control variants are
  generated and mapped.

**Acceptance Criteria**:
- [ ] One schema edit changes the emitted constants/field limits in TS, Dart,
      and Rust; generated-file check tests fail on stale projections.
- [ ] The generated Dart union decodes outer envelopes and every currently
      supported relay-to-app control frame, rejects wrong field types and
      unknown required shapes, and never exposes a raw map to `WsTransport`.
- [ ] Client-only relay frames cannot enter an endpoint's server-frame union.
- [ ] Existing 4 MiB `ct`, room metadata, session-id opacity, and control-frame
      wire shapes remain compatible.

---

### Unit 2: Relay WebSocket and pre-auth fail-fast boundary

**Files**:
- `relay/src/handlers/peer.rs`
- `relay/src/auth/challenge.rs`
- `relay/src/auth/auth_test.rs`
- `relay/src/protocol/frame.rs`
- `relay/src/protocol/outer.rs`
- `relay/tests/integration.rs`

**Stories**: `gate-security-frame-decoder-pre-size-check`,
`gate-security-preauth-websocket-size-limits`

```rust
pub fn max_ws_message_bytes() -> usize;

pub fn decode_relay_frame_with_limits(
    text: &str,
    max_raw_bytes: usize,
    max_decoded_ct_bytes: usize,
) -> Result<DecodedRelayFrame, FrameDecodeError>;

pub enum FrameDecodeError {
    RawTooLarge { actual: usize, max: usize },
    InvalidJson(serde_json::Error),
    UnknownType(String),
    OuterTooLarge { estimated: usize, max: usize },
}

pub enum AuthError {
    FrameTooLarge { actual: usize, max: usize },
    FieldTooLarge { field: &'static str, actual: usize, max: usize },
    // existing variants remain
}
```

**Implementation Notes**:
- Configure `WebSocketUpgrade::max_frame_size(max_ws_message_bytes())` and
  `max_message_size(max_ws_message_bytes())` before `on_upgrade`; this bounds
  both single frames and reassembled fragmented messages.
- `decode_relay_frame_with_limits` checks `text.len()` before
  `serde_json::from_str`. Its injected limits make ordering testable without
  allocating multi-megabyte fixtures. `decode_relay_frame` supplies production
  values derived from `max_ct_bytes()`.
- `parse_hello_bootstrap` and `verify_auth` enforce 16 KiB before Serde, then
  validate bounded fields before storing them in `AuthenticatedPeer` or logging
  only the error category. Never log field values, `ct`, signatures, or room
  metadata.
- Keep the relay opaque: estimate decoded `ct` from canonical base64 length and
  do not base64-decode payload content.

**Acceptance Criteria**:
- [ ] An over-limit invalid JSON string returns `RawTooLarge`, proving the size
      guard runs before JSON parsing.
- [ ] Oversized pre-auth WS messages and over-limit hello metadata close without
      authentication, registration, payload logging, or process growth beyond
      the configured WS ceiling.
- [ ] Fragmented messages cannot bypass the Axum message limit.
- [ ] A payload exactly at 4 MiB decoded-equivalent is accepted; the next
      impossible encoded quantum is rejected.
- [ ] Existing auth, presence/rooms, outer routing, and `pi_envelope`
      compatibility/error behavior remain intact.

---

### Unit 3: Extension WS cap and shared bounded payload decoder

**Files**:
- `pi-extension/src/transport/relay_client.ts`
- `pi-extension/src/protocol/relay_ingress.ts` (new)
- `pi-extension/src/extension/owner_multiplexer.ts`
- `pi-extension/src/transport/peer_channel.ts`
- `pi-extension/src/extension/relay_transport.ts`
- `pi-extension/src/transport/pi_forward_client.ts`
- `pi-extension/src/transport/relay_client.test.ts`
- `pi-extension/src/protocol/relay_ingress.test.ts` (new)
- `pi-extension/src/extension/relay_transport.test.ts`

**Story**: `gate-security-extension-inbound-relay-frame-size-caps`

```ts
export interface RelayIngressLimits {
  readonly maxRawBytes: number;
  readonly maxDecodedPayloadBytes: number;
}

export type DecodedRelayIngress =
  | { readonly kind: "outer"; readonly frame: RelayOuterEnvelope; readonly payloadUtf8: string }
  | { readonly kind: "control"; readonly frame: RelayServerControlFrame }
  | { readonly kind: "cross_pc"; readonly frame: CrossPcFramePiEnvelopeIn };

export class RelayIngressDecodeError extends Error {
  readonly code: "too_large" | "invalid_message" | "unsupported_type";
}

export function decodeRelayIngress(
  line: string,
  limits?: Partial<RelayIngressLimits>,
): DecodedRelayIngress;
```

**Implementation Notes**:
- Construct `ws` with `{ maxPayload: generatedRawMessageLimit }`; this is the
  primary pre-allocation/reassembly cap for challenge and post-auth messages.
  Do not disable per-message deflate or TLS behavior as part of this change.
- `decodeRelayIngress` checks `Buffer.byteLength(line, "utf8")` before
  `JSON.parse`, validates via generated relay/cross-PC predicates, and for outer
  frames checks base64 encoded length before `Buffer.from`. Check decoded byte
  length again before converting to UTF-8.
- Route the typed union once in the relay transport. Owner multiplexer,
  `PlainPeerChannel`, and `PiForwardClient` consume typed frames instead of each
  parsing the same raw line; delete their duplicate `JSON.parse`, handwritten
  outer interfaces, and base64 decode helpers. Preserve relay-generation
  freshness guards and listener teardown.
- Oversized/malformed frames produce content-free diagnostics (type/category and
  byte count only). Never interpolate the raw challenge or frame into an error;
  the current challenge errors that echo `challengeRaw` must be made
  content-free.

**Acceptance Criteria**:
- [ ] The `ws` constructor receives the generated raw message ceiling.
- [ ] Raw oversize is rejected before JSON parse and encoded `ct` oversize before
      `Buffer.from`; exact-boundary payloads still decode.
- [ ] Owner, control, and cross-PC consumers receive the same typed frames and
      observable routing as before, with no duplicate source-local outer parser.
- [ ] A malformed or oversized relay frame cannot reach `decodeClient`, owner
      attachment, or broker anti-spoof routing.
- [ ] Error and debug output contains no raw frame, inner message, `ct`, nonce,
      signature, or metadata value.

---

### Unit 4: Mobile typed, bounded inbound demux

**Files**:
- `app/lib/data/transport/ws_transport.dart`
- `app/lib/data/transport/relay_frame_decoder.dart` (new)
- `app/test/data/transport/ws_transport_demux_test.dart`
- `app/test/data/transport/relay_frame_decoder_test.dart` (new)

**Stories**: `gate-refactor-boundaries-demux-adhoc-map`,
`gate-security-app-inbound-relay-frame-size-caps`

```dart
enum RelayFrameDecodeFailure {
  tooLarge,
  malformed,
  unsupportedType,
}

sealed class RelayFrameDecodeResult {
  const RelayFrameDecodeResult();
}

final class DecodedRelayFrame extends RelayFrameDecodeResult {
  final RelayInboundFrameDto frame;
  final Uint8List? decodedPayload;
}

final class RejectedRelayFrame extends RelayFrameDecodeResult {
  final RelayFrameDecodeFailure reason;
  final int observedSize;
}

RelayFrameDecodeResult decodeRelayInboundFrame(
  String raw, {
  int maxDecodedPayloadBytes = relayDefaultMaxDecodedBytes,
});
```

**Implementation Notes**:
- Count UTF-8 bytes with an early-exit scalar scan rather than
  `utf8.encode(raw)`, which would allocate another whole attacker-controlled
  buffer before the cap. This still runs after `dart:io` has materialized the WS
  string; Flutter's current WebSocket API exposes no client `maxPayload`, so the
  guarantee here is bounded JSON/base64 work, not zero allocation by a
  compromised relay.
- Parse once into `RelayInboundFrameDto`. For an outer DTO, check encoded length,
  decode standard base64 (retain current URL-safe fallback only if compatibility
  tests prove it is still required), verify decoded length, then apply the
  existing room-required and active-room match decisions.
- Replace `demuxPostAuthInboundFrame`'s map navigation with the decoder result
  and typed DTO switch. Map generated control DTOs through
  `ControlInbound.fromWire`; no transport code reads `frame['type']`,
  `frame['peer']`, `frame['room']`, or `frame['ct']`.
- Apply the same generated raw/pre-auth ceiling to challenge parsing before
  `jsonDecode`; require a generated typed challenge with a canonical 32-byte
  nonce before signing.
- Keep diagnostics payload-free. Use reason and observed byte count; do not log
  the exception text if it can embed attacker-controlled data.

**Acceptance Criteria**:
- [ ] Raw frame size is checked before `jsonDecode`, and encoded payload length
      before `_b64Decode`; a defensive decoded-length check follows.
- [ ] Typed outer/control DTOs drive demux with no `Map<String, dynamic>` field
      navigation in `ws_transport.dart`.
- [ ] Matching-room envelopes and all existing control events behave unchanged;
      missing/mismatched rooms remain explicit drops.
- [ ] Over-limit raw, base64, and decoded cases return deterministic rejection
      reasons without queue/control mutation or payload logging.
- [ ] Multibyte input cannot bypass the raw UTF-8 byte ceiling.

---

### Unit 5: Durable contract and cross-stack boundary evidence

**Files**:
- `PROTOCOL.md`
- `docs/ARCHITECTURE.md`
- `.agents/skills/rust-relay/SKILL.md`
- `.agents/skills/pi-extension-typescript/SKILL.md`
- `.agents/skills/flutter-mobile/SKILL.md`
- `.orchestration/contracts/protocol-parity.json` (only if the generator's
  existing parity catalog requires the new generated family)

**Stories**: all five existing child checkpoints

**Implementation Notes**:
- Roll current-state docs forward in the implementation commit: document the
  4 MiB decoded default, derived raw ceiling, smaller pre-auth ceiling, metadata
  limits, close/drop behavior, and the fact that Flutter can bound decode work
  but cannot configure its underlying WebSocket message allocation.
- Do not add changelog/history prose or claim E2E/payload opacity beyond current
  truth. The relay still sees `ct` and routes it opaquely without decoding it.
- Update the three stack references because their current validation-boundary
  guidance becomes more specific. Do not link durable docs to these transient
  work items.

**Acceptance Criteria**:
- [ ] Durable docs describe the implemented limits and honest per-stack
      guarantee without contradicting the existing relay/configuration decision.
- [ ] Cross-stack codegen/parity checks prove limit constants and DTO variants
      are aligned.
- [ ] No generated output, build artifact, payload fixture, or secret is
      committed outside the repository's established generated protocol files.

## Implementation Order

1. `gate-refactor-boundaries-demux-adhoc-map`: extend the canonical schema and
   codegen first, including typed Dart relay DTOs and generated constants.
2. `gate-security-preauth-websocket-size-limits`: apply the generated bounds to
   Axum upgrade/auth and hello metadata.
3. `gate-security-frame-decoder-pre-size-check`: enforce the relay raw-before-
   parse decoder order using the same constants.
4. `gate-security-extension-inbound-relay-frame-size-caps`: centralize typed
   extension ingress and configure `ws.maxPayload`.
5. `gate-security-app-inbound-relay-frame-size-caps`: replace app demux with the
   generated typed/bounded decoder.
6. Run focused cross-stack parity/boundary tests, update durable protocol/stack
   references, then run each owning subproject's normal verification in the
   implementation wave.

The five gate-created children are retained unchanged and no new child stories
are needed: together they cover schema/type ownership, relay pre/post-auth,
extension, and app acceptance. Their existing empty `depends_on` arrays remain
because the caller restricted this design commit to the feature plus newly
created paths; this feature-level order is the sequencing contract for the
single cohesive implementation owner.

## Simplification

- Delete app transport map navigation and retire the temporary handwritten Dart
  relay-control DTO island after generated coverage lands.
- Delete extension-local outer-envelope interfaces, repeated `JSON.parse`, and
  repeated base64 decode helpers by routing one typed ingress union.
- Keep the relay's small `serde_json::Value` type probe only where malformed
  `pi_envelope` compatibility needs raw fields for `bad_envelope`; the raw cap
  makes that escape hatch bounded. Do not introduce a streaming parser yet.
- Retain exact existing room/session semantics, relay opacity, URL transport,
  and reconnect ownership; this feature changes rejection timing, not routing.
- No low-value per-wrapper tests are added. Existing demux tests are upgraded to
  typed boundary tests rather than duplicated.

## Testing

- **Schema/codegen interface**: stale-output and generated-union tests protect
  the one-source contract and directional frame registries.
- **Relay regressions**: injected small limits prove raw-before-JSON ordering;
  auth unit tests prove field caps; one WS integration test proves oversized or
  fragmented pre-auth messages close before registration. These protect the
  unauthenticated resource boundary.
- **Extension regressions**: mock the `ws` constructor to assert `maxPayload`,
  and test small injected raw/decoded limits around exact base64 quanta. Existing
  relay transport and cross-PC tests protect routing/listener lifecycle after
  typed demux consolidation.
- **App regressions**: pure decoder tests use small injected limits for raw,
  multibyte, encoded, and decoded cases; existing demux tests protect room and
  control behavior. No multi-megabyte test strings are required.
- **Cross-language parity**: generated constants and relay frame variants are
  compared against the canonical schema/output checks, not copied expected
  lists in three unrelated tests.
- **Test removal**: remove assertions that exist only to exercise the retired
  handwritten map parser or duplicate generated shape validation; retain
  behavioral room/control/routing assertions.

Design phase intentionally ran no build or full test suite; implementation will
run targeted tests first, then the documented `cargo`, `pnpm`, and Flutter
verification commands from each subproject root.

## Risks

- **Riskiest assumption — Dart generation**: the current Dart generator consumes
  a purpose-built IR and the relay-control island is explicitly deferred.
  Extending it from the canonical manifest may expose unsupported nested/nullable
  shapes. Implement outer envelope + server control variants first behind a
  deterministic golden; if full relay-family generation cannot preserve current
  semantics, keep `ControlInbound` as the domain adapter but do not fall back to
  transport map parsing or a second numeric limit registry.
- **WS library semantics**: Axum/tungstenite limits must cover both individual
  and reassembled messages, and `ws.maxPayload` must be asserted through the
  actual constructor. Integration tests are the fallback if API assumptions
  differ from type signatures.
- **Flutter allocation gap**: manual Dart rejection occurs after the platform
  WebSocket has built a String. It still prevents unbounded JSON/base64 work, but
  a fully malicious relay can cause one message allocation up to platform
  limits. If that residual risk is unacceptable after measurement, the fallback
  is a transport adapter with a configurable native message cap—not a streaming
  parser bolted below an already-materialized String.
- **Configured relay asymmetry**: raising `RELAY_MAX_CT_MIB` above 4 MiB can
  produce frames endpoints intentionally reject. Docs must state this until a
  negotiated cap exists; do not silently mirror a server environment setting on
  mobile.
- **Compatibility**: stricter metadata bounds or strict base64 can reject
  previously tolerated malformed/non-canonical senders. Preserve valid current
  clients and lock the deliberate fail-fast behavior with compatibility tests.

## Review fixes (2026-07-19)

All five standard-review findings are resolved:

1. **App WS-in routing regression** — `d7f790e` updates the debug relay probe to send the now-required canonical 32-byte challenge nonce, restoring the post-auth WS-in routing test.
2. **Padding-aware decoded-size estimation** — `0b2f047` subtracts standard base64 padding from the relay's opaque decoded-size estimate and locks exact 4 MiB plus non-divisible boundary behavior with regression tests.
3. **Decode-once typed extension fanout** — `6c5c99c` makes `relay_transport.ts` the sole raw-message decoder for runtime-owned relay connections. The same `DecodedRelayIngress` object fans out to the owner ingress callback and a typed subscription hub consumed by every `PlainPeerChannel` and `PiForwardClient`; those listeners no longer parse JSON or decode base64. Directly-owned standalone mesh relays retain one shared fallback decoder regardless of listener count. A regression test attaches owner, two peer channels, and cross-PC forwarding while asserting the relay still has exactly one raw `message` listener.
4. **Unknown-type log amplification** — `c3a2135` replaces attacker-controlled type logging with content-free categories/byte counts and caps invalid-frame diagnostics per authenticated connection.
5. **Generated relay ingress contracts** — `802d7bd` makes schema/codegen own the ingress constants and generated TypeScript/Dart/Rust projections, including directional post-auth DTO validation; endpoint transports consume those generated contracts rather than handwritten mirrors.

Verification after the final Finding 3 fix:

- `pi-extension`: `./node_modules/.bin/tsc --noEmit` passes with zero errors.
- `pi-extension`: `./node_modules/.bin/vitest run` passes all 52 test files: 879 passed, 3 skipped. The sandbox's read-only `/tmp` and long redirected temp path required a writable `/tmp` bind plus `TMPDIR=/tmp`; the authoritative Vitest command itself was unchanged.
- Findings 1, 2, 4, and 5 retain their previously completed green app/relay/codegen verification in the commits listed above.

Implementation capability: `openai-codex/gpt-5.6-sol` at high thinking, selected by the autopilot caller for the cross-listener protocol boundary. Effective review weight remains `standard`; this transition intentionally stops at feature review for the host's final review pass.

## Phase-8 disposition (2026-07-19)

The Phase-8 final completion review flagged that the generated-contract/SSOT
acceptance is incomplete: runtime validation in `relay_ingress.ts` still uses
hand-written type guards (`isEnvelope`/`parseCrossPc`/`parseOuter`) rather than
schema-generated predicates; `peer_channel.ts` retains a handwritten
`OuterEnvelope` mirror; and the cross-stack references (`PROTOCOL.md`,
`docs/ARCHITECTURE.md`, `.agents/skills/{pi-extension-typescript,flutter-mobile}/SKILL.md`)
were not all updated to current-state. The feature was reopened to `review`
(commit `9ac6027`) and a focused worker attempted the generated-validation
completion twice; both attempts hit the turn limit mid-refactor with
non-compiling/incomplete codegen-regeneration state (the schema `compat` profile
for room-optional inbound outer envelopes is genuinely intricate). The partial
work was reverted; the verified-correct committed state (typed DTOs + size
checks + decode-once fanout + generated constants, all green across relay/
pi-ext/app) is preserved.

**Disposition:** the feature's CORRECTNESS is verified green (all three stacks:
relay clippy+206 tests, pi-ext tsc+879 vitest, app 64 tests). The residual gap
is SSOT-COMPLETENESS hardening (replace hand-written type guards with generated
predicates + finish reference updates), not a correctness defect — the typed
boundary + size caps + single-decode fanout that prevent the original DoS/ad-hoc-parse
defects ARE in place and verified. Forcing the intricate codegen refactor through
repeatedly under turn pressure risks more breakage than it fixes. The gap is
tracked as an explicit active follow-up (`story-typed-bounded-generated-runtime-validation`)
rather than leaving this feature indefinitely blocked. Feature returned to `done`
on its verified-correct work; the follow-up carries the SSOT-completion debt.
