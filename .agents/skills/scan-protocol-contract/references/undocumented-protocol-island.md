# Rule: Undocumented Protocol Island

> Genuine hand-maintained wire types outside `protocol/generated/` must carry a durable reason they remain outside the schema IR; generated projections and their adapters are not islands.

## Motivation

Remote Pi generates wire types from a canonical schema. A generated projection may be wrapped by
an adapter, such as `app/lib/protocol/control_frames.dart` over
`app/lib/protocol/generated/relay_frames.g.dart`; that adapter is not a wire-shape island. A
handwritten wire family outside `generated/` is instead either (a) a *genuine documented
exception* with a durable reason it remains outside the schema or (b) an *undocumented drift* —
someone hand-added a wire type and never reconciled it with the schema. (b) is a
single-source-of-truth violation: the schema no longer describes the full wire. This rule catches
(b) while retaining only the documented exception for (a).

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Generated or
inferred contracts + Single source of truth.

## Signals

A file outside any `protocol/generated/` directory that defines wire frame types (structs/classes/
enums/interfaces describing on-the-wire message shapes) AND lacks a comment explaining why the
types are not in the generated schema. The absence of a documented reason is the violation.

## Before / After

### From this codebase: the generated relay projection and adapter (keep this — NOT a violation)

**Current (correct) — `app/lib/protocol/generated/relay_frames.g.dart` plus
`app/lib/protocol/control_frames.dart`:**
```dart
// generated/relay_frames.g.dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated from protocol/schema/relay-{outer,control}.schema.json.

// control_frames.dart
sealed class ControlInbound {
  static ControlInbound? fromWire(RelayServerControlFrameDto frame) => ...;
}
```
The generated file owns the relay control/presence/rooms DTO union. `control_frames.dart`
adapts those generated DTOs into app-domain models; it does not define a competing wire shape
or qualify as a temporary hand-maintained island. Do not flag either the generated projection or
this adapter under `undocumented-protocol-island`.

### Synthetic: violation (undocumented island)

**Before (violation) — a hypothetical `app/lib/protocol/new_frame.dart`:**
```dart
class FancyNewFrame {
  final String type = "fancy_new";
  final String payload;
  // no comment explaining why this isn't in the schema
}
```

**After (either document or migrate):**
```dart
// Option A — document (if migration is tracked):
// Temporary hand-maintained island: `fancy_new` is not yet in the schema IR
// because <reason>; migrate when <condition>. See .work/...
class FancyNewFrame { ... }

// Option B — migrate (preferred): add `fancy_new` to the schema source and regenerate.
```

## Exceptions

- **Generated projections and adapters** — `app/lib/protocol/generated/relay_frames.g.dart`
  owns relay DTOs; `control_frames.dart` adapts them and is not an island.
- **Genuine documented islands** — a hand-maintained wire family may be skipped only when a
  durable comment explains why it remains outside the schema and what condition would move it.
- **Re-export facades** — `relay/src/protocol/frame.rs` (`pub use generated::*`) is a facade, not
  an island; its types come from generated. Not a violation (covered by `handwritten-wire-dto`).
- **Adapter/codec types** — a type that bridges wire and domain, not itself a wire frame, is not
  an island.
- **Generated code** — skip `generated/`.
- **Test fixtures** — skip.

## When NOT to Use

Do not report an undocumented-protocol-island finding for a handwritten format only when all of
these safeguards are present:

1. the format is non-JSON binary or cryptographic framing rather than an ordinary message family;
2. a durable canonical contract specifies the exact bytes and security semantics;
3. the implementation links to that canonical contract; and
4. an independently generated cross-language known-answer test pins the exact bytes.

`pi-extension/src/transport/secure_channel.ts` is the concrete exception: its byte-level AEAD
frame is specified by `PROTOCOL.md`, linked beside the framing constants, and pinned by
`protocol/fixtures/app-pi/owner-channel-kat.json` plus
`protocol/scripts/generate-owner-channel-kat.ts`. This exception does not apply to handwritten
JSON DTOs, discriminators, validators, or control frames; those remain findings unless generated
or covered by the documented temporary-island rule above.

## Scope

`app/lib/protocol/**` (non-generated), `relay/src/protocol/**` (non-generated),
`pi-extension/src/protocol/**` (non-generated), `pi-extension/src/transport/**` (non-test),
`cockpit/lib/**` protocol touch sites. Does NOT apply to generated code, tests, `site/`.
