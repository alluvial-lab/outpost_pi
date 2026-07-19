---
id: story-typed-bounded-generated-runtime-validation
kind: story
stage: drafting
tags: [pi-extension, app, relay, protocol, refactor]
parent: feature-typed-bounded-relay-decoding
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-19
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

- [ ] Generated runtime validation predicates for outer + cross-PC frames exist
      (emitted by `tools/protocol-codegen`), enforcing `additionalProperties: false`
      + nonempty constraints, with a compat profile for the room-optional pre-auth
      shape.
- [ ] `relay_ingress.ts` consumes the generated predicates; the hand-written
      `isEnvelope`/`parseCrossPc`/`parseOuter` are removed.
- [ ] `peer_channel.ts` `OuterEnvelope` mirror removed in favor of the generated
      type.
- [ ] `.agents/skills/pi-extension-typescript/SKILL.md` updated to current-state.
- [ ] `PROTOCOL.md` + `docs/ARCHITECTURE.md` + `.agents/skills/flutter-mobile/SKILL.md`
      decode-path descriptions updated.
- [ ] Codegen test pins the generated predicates.
- [ ] All three stacks green: relay `cargo clippy -D warnings` + `cargo test`;
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
