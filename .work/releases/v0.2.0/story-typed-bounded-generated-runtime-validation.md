---
id: story-typed-bounded-generated-runtime-validation
kind: story
stage: done
tags: [pi-extension, app, relay, protocol, refactor]
parent: feature-typed-bounded-relay-decoding
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-07-19
updated: 2026-07-20
---

# Finish generated runtime validation for relay ingress (SSOT completion)

## Source

Phase-8 final completion review of the `--all` autopilot run (2026-07-19). The
review correctly flagged that `feature-typed-bounded-relay-decoding`'s
generated-contract/SSOT acceptance is incomplete: the codegen emits generated
*constants* + directional DTOs, but the RUNTIME VALIDATION path still uses
hand-written type guards rather than schema-generated predicates. The feature
was returned to `done` on its verified-correct work (typed DTOs + size checks +
decode-once fanout are all in place and green); this story carries the residual
SSOT-completion debt.

## The gap

1. `pi-extension/src/protocol/relay_ingress.ts` — `isEnvelope`, `parseCrossPc`,
   `parseOuter` are hand-written type guards. They should be GENERATED predicates
   from `protocol/schema/relay-outer.schema.json` (via `tools/protocol-codegen`),
   enforcing `additionalProperties: false` + nonempty recipient arrays + nonempty
   `re`.
2. `pi-extension/src/transport/peer_channel.ts:42-45` — retains a handwritten
   `OuterEnvelope` interface (a local mirror of the schema-owned type). Derive/use
   the generated type.
3. `.agents/skills/pi-extension-typescript/SKILL.md:129` — falsely says "runtime
   inbound dispatch still uses source-local parsing/dispatch logic". Update to
   current-state once the generated predicates land.
4. Cross-stack references — `PROTOCOL.md`, `docs/ARCHITECTURE.md`,
   `.agents/skills/flutter-mobile/SKILL.md` — describe the decode path; update to
   reflect the generated/typed boundary (only `.agents/skills/rust-relay/SKILL.md`
   was updated by the feature).

## Known complexity

Two prior fix-worker attempts hit their turn limit mid-refactor. The genuine
intricacy is the schema `compat` profile for room-optional inbound outer
envelopes (the relay overwrites `room` with the sender's auth room for
anti-spoof, so inbound outer frames may lack `room` pre-auth). The codegen must
emit predicates that accept this compat shape without weakening the
`additionalProperties: false` strictness for the post-auth typed path. A schema
`compat` profile (or a two-shape validation: strict post-auth vs lenient
pre-auth) is the likely approach — design it explicitly rather than ad-hoc.

## Acceptance criteria

- [x] Generated runtime validation predicates for outer + cross-PC frames exist
      (emitted by `tools/protocol-codegen`), enforcing `additionalProperties: false`
      + nonempty constraints, with a compat profile for the room-optional pre-auth
      shape.
- [x] `relay_ingress.ts` consumes the generated predicates; the hand-written
      `isEnvelope`/`parseCrossPc`/`parseOuter` are removed.
- [x] `peer_channel.ts` `OuterEnvelope` mirror removed in favor of the generated
      type.
- [x] `.agents/skills/pi-extension-typescript/SKILL.md` updated to current-state.
- [x] `PROTOCOL.md` + `docs/ARCHITECTURE.md` + `.agents/skills/flutter-mobile/SKILL.md`
      decode-path descriptions updated.
- [x] Codegen test pins the generated predicates.
- [x] All three stacks green: relay `cargo clippy -D warnings` + `cargo test`;
      pi-ext `tsc --noEmit` + `vitest run`; app `PUB_CACHE=<repo>/.pub-cache flutter test --no-pub test/data/transport/ test/protocol_codegen/ test/data/debug/debug_capture_routing_test.dart`.

## Verification

```
cd tools/protocol-codegen && ./node_modules/.bin/vitest run
cd ../.. && cd pi-extension && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vitest run
cd ../relay && cargo clippy -- -D warnings && cargo test
cd ../app && PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache flutter test --no-pub test/data/transport/ test/protocol_codegen/ test/data/debug/debug_capture_routing_test.dart
```

## Why this is a story, not left in the feature

The feature's correctness is verified green; this is SSOT-completion hardening
(scan-protocol-contract single-source-of-truth). Tracking it as an active story
keeps the debt visible and pickable rather than burying it in a "blocked" feature.

## Implementation

Implemented as one direct-read worker pass with no nested delegation, per the
caller boundary. The story advanced `drafting → implementing → done`; as a child
story it skips an independent review after green verification.

### Generated-validation and compatibility design

The canonical JSON Schema remains strict: `relay-outer.schema.json` still
requires non-empty `peer`, `room`, and `ct` and declares
`additionalProperties: false`. Its `x-outpost-pi.profileOptional.compat`
metadata names `room` as the sole compatibility relaxation. Protocol codegen
now derives two TypeScript projections from that one schema:

- `RelayOuterEnvelope` / `isRelayOuterEnvelope` preserve the strict,
  room-required canonical sender shape.
- `RelayOuterEnvelopeCompat` / `isRelayOuterEnvelopeCompat` accept the
  room-optional pre-rewrite receive shape, while still rejecting an empty
  present room, empty peer/ct, and unknown properties.

This keeps compatibility explicit rather than weakening the schema or the
strict outbound path. `PlainPeerChannel` now constructs its outbound frame as
the generated strict `RelayOuterEnvelope`; the live relay ingress uses the
generated compatibility predicate at its endpoint boundary.

The same generator now emits `isCrossPcFrame` from `cross-pc.schema.json` and
its referenced generic-envelope schema. Array generation honors `minItems` and
`maxItems`, so recipient arrays cannot be empty; `re` inherits its schema
`minLength: 1`; and `additionalProperties: false` applies at top-level and
nested object boundaries. `relay_ingress.ts` removed `isEnvelope`,
`parseCrossPc`, and `parseOuter`, uses generated predicates for outer,
cross-PC, post-auth control, and challenge frames, and retains the existing
single-decode typed fanout. The local `OuterEnvelope` mirror in
`peer_channel.ts` is gone.

Commits:

- `8a28ef1` — generated strict/compat outer predicates, cross-PC predicate,
  array cardinality validation, regenerated TypeScript, and codegen tests.
- `c476bb9` — live extension consumption, handwritten guard/mirror removal,
  and ingress regressions.
- `671fb70` — current-state protocol, architecture, and stack references.

### Verification

- `tools/protocol-codegen`: authoritative Vitest command passed 1 file / 5
  tests; the existing protocol-package Node test entry also passed all 5, and
  the generated TypeScript stale check passed.
- `pi-extension`: `tsc --noEmit` passed with zero errors; full Vitest passed 52
  files, 880 tests passed, 3 skipped.
- `relay`: `cargo clippy -- -D warnings` passed; `cargo test` passed 208 tests
  across unit/integration suites, with zero failures.
- `app`: focused authoritative Flutter command passed all 64 tests.
