# Rule: Frame Discriminator Re-enumerated

> A `switch`/`match`/validator over frame types must derive its cases from the canonical registry, not re-list the type strings.

## Motivation

When a handler does `switch (type) { "presence_check" => ..., "room_meta_update" => ... }` and a
new frame type is added to the schema, the generated registry gains the variant but this switch
silently falls through to `default`/`null` — the new frame is unhandled with no compile error.
The fix is to derive an exhaustive union from the registry (TS: `typeof REGISTRY[number]`; Rust:
a generated enum with a `match` that the compiler checks for exhaustiveness; Dart: a `sealed`
class hierarchy). This is the "derive types, validation, dispatch, and display from one registry"
rule from [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Single source of truth.

## Signals

- A `switch (x) { "peer_online" => ..., "peer_offline" => ... }` (Dart) /
  `match x { "peer_online" => ... }` (Rust) / `switch (x) { case "peer_online": }` (TS) that
  re-lists frame type strings present in a generated registry.
- A validator `isRelayControlFrame(type) { return ["presence_check", ...].includes(type) }` that
  re-enumerates instead of deriving from the generated list.
- Especially: a `default => null` / `_ => ()` arm that silently drops unhandled types, where an
  exhaustive generated enum would force a compile error on addition.

## Before / After

### From this codebase: the generated exhaustive shape (target)

**Current (correct) — `relay/src/protocol/generated/frame.rs`:**
```rust
pub enum RelayInboundFrame {
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}
// generated Deserialize parses the "type" discriminator into the typed enum
```
Handlers `match` on `RelayInboundFrame::Control(c) => ...` and the compiler verifies
exhaustiveness — a new variant added to the schema surfaces as a non-exhaustive match error.

### From this codebase: generated relay DTO adapter (not a violation)

**Current — `app/lib/protocol/control_frames.dart` over
`app/lib/protocol/generated/relay_frames.g.dart`:**
```dart
static ControlInbound? fromWire(RelayServerControlFrameDto frame) => switch (frame) {
  RelayPeerOnlineFrameDto(:final peer) => PeerOnline(peer: peer),
  RelayPeerOfflineFrameDto(:final peer, :final sinceTs) =>
    PeerOffline(peer: peer, sinceTs: sinceTs),
  RelayPresenceFrameDto(:final states) => PresenceSnapshot(states: ...),
  _ => null,
};
```
The generated sealed DTO union owns the wire discriminator and decoding; this switch adapts
already-typed variants into app-domain models. It does not re-enumerate string literals and is
not a `discriminator-reenumerated` finding. A genuinely handwritten switch over raw discriminator
strings remains a finding unless it is a documented temporary island.

## Exceptions

- **Generated code** — the generated `Deserialize`/`tryFromJson` itself switches on literals to
  build the typed value; that is the source of truth, skip `generated/`.
- **Forward-compat boundary decode** — a parser that intentionally returns `null`/`unknown` for
  unrecognized types to tolerate schema evolution *may* legitimately re-list known types, but
  should derive the known set from the registry. Mark medium; needs analysis.
- **Test code** — skip test files.
- **Genuine documented islands** — if a raw-string re-enumeration is inside a genuine documented
  temporary island, do not double-flag it; the island's provenance is the owning concern. This
  exception does not apply to generated relay DTO adapters.

## Scope

`relay/src/handlers/**` (non-test), `relay/src/peers/**` (non-test), `relay/src/protocol/**`
(non-generated), `pi-extension/src/transport/**`, `pi-extension/src/session/**` (non-test),
`app/lib/protocol/**` (non-test, non-generated), `app/lib/data/**` (non-test). Does NOT apply to
generated code, tests, `site/`.
