---
id: feature-finish-generated-protocol-adoption
kind: feature
stage: drafting
tags: [pi-extension, relay, cockpit, refactor, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-16
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
