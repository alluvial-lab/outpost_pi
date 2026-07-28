# Rule: Undocumented Protocol Island

> Hand-maintained wire types outside `protocol/generated/` must carry a documented reason they are not yet in the schema IR.

## Motivation

Remote Pi generates wire types from a canonical schema. When a wire type lives in a handwritten
file outside `generated/` (e.g. `app/lib/protocol/control_frames.dart`, `relay/src/protocol/frame.rs`),
it is either (a) a *documented temporary island* — "not yet in the schema IR, will migrate" —
or (b) an *undocumented drift* — someone hand-added a wire type and never reconciled it with the
schema. (b) is a single-source-of-truth violation: the schema no longer describes the full wire.
This rule catches (b) while exempting (a).

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Generated or
inferred contracts + Single source of truth.

## Signals

A file outside any `protocol/generated/` directory that defines wire frame types (structs/classes/
enums/interfaces describing on-the-wire message shapes) AND lacks a comment explaining why the
types are not in the generated schema. The absence of a documented reason is the violation.

## Before / After

### From this codebase: the documented island (keep this — NOT a violation)

**Current (correct) — `app/lib/protocol/protocol.dart:3-6` (the facade that documents the island):**
```dart
// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
//
// Relay control/presence/rooms frames are not yet in the schema IR, so they
// remain in the temporary hand-maintained island exported below.
```
`control_frames.dart` (exported by `protocol.dart`) carries those hand-maintained types and
expands on why: "These travel raw over the WS (no outer envelope) and are routed by the relay
itself... They never enter the inner-message switch." The island is **documented** at the facade
(`protocol.dart`) — a future agent knows why it exists and that migration is the intended end
state. Do not flag documented islands. Note: the documenting comment lives in `protocol.dart`,
not `control_frames.dart` itself; treat the facade + island file as a pair.

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

- **Documented islands** — files with a comment stating the types are not yet in the schema IR
  and why (the `protocol.dart` / `control_frames.dart` pattern). Do not flag.
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
