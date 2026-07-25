---
id: gate-cruft-client-message-discriminators-unused
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: cruft
created: 2026-07-24
updated: 2026-07-24
---

# Generated CLIENT_MESSAGE_DISCRIMINATORS has no consumer

## Confidence
High (whole-repo grep, drain-delta re-scan 2026-07-24)

## Category
unused export

## Location
`tools/protocol-codegen/src/index.ts:889` (emitter);
`pi-extension/src/protocol/generated/protocol.generated.ts:143` (output)

## Evidence
The drain's discriminator-registry work emits both
`CLIENT_MESSAGE_DISCRIMINATORS` and `SERVER_MESSAGE_DISCRIMINATORS`. Only
the server family has a production consumer (owner_multiplexer.ts); the
client family is referenced only by the generator's own test-module type
declaration.

## Removal
Emit discriminator registries only for the server-message family (or only
on schema demand), regenerate `protocol.generated.ts`, and remove the
client family from generated output and test declarations. Fix the
generator, not the output.
