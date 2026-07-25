---
id: gate-cruft-client-message-discriminators-unused
kind: story
stage: done
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

## Implementation notes
- Made discriminator registries opt-in in the TypeScript emitter and requested one only for `ServerMessage`; regenerated protocol output no longer exports `CLIENT_MESSAGE_DISCRIMINATORS`.
- Removed the client discriminator declaration from generator test imports and added absence assertions while retaining server-registry coverage.
- Verification: `cd protocol && node --import tsx --test ../tools/protocol-codegen/src/index.test.ts` (6 passed); `cd pi-extension && ./node_modules/.bin/tsc --noEmit`; `cd pi-extension && ./node_modules/.bin/vitest run` (930 passed, 3 skipped).

## Review

Bounded inline review (orchestrator, 2026-07-24): diffs inspected and
verification independently reproduced — direct sendPiMessage-never-called
assertion with duplicate projection removed (parked item closed in-commit);
server-only discriminator emission with regenerated output and consumers
typechecking; brace-expansion@5 5.0.8 + minimatch@3->10.2.5 legacy-path
removal with orchestrator-run audits clean at high in both packages (prod
extension: 2 moderate below threshold; site: none), frozen installs,
extension 930 tests, site lint+build green. Approved -> done.
