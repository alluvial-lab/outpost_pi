---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
kind: story
stage: implementing
tags: [rebrand, pi-extension, app, relay, protocol]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-schema-source
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Regenerate protocol artifacts from renamed schema

## Scope

Unit 2 of the wire-stable migration feature. Run the protocol codegen so the
generated TS/Dart/Rust files pick up the renamed discriminators from the
schema source (Unit 1). Pure regeneration — no hand-edits to generated files.

## Units implemented
- Unit 2 (generated artifacts)

## Changes
- `pi-extension`: `corepack pnpm --dir pi-extension generate:protocol` →
  updates `src/protocol/generated/protocol.generated.ts`
- Dart generator → updates `app/lib/protocol/generated/protocol.g.dart`
- Rust generator → updates `relay/src/protocol/generated/*.rs`
- If a discriminator didn't update, the schema in Unit 1 was missed, not
  the generator — do NOT hand-patch generated files.

## Acceptance Criteria
- [ ] `corepack pnpm --dir pi-extension check:protocol` passes (generated ==
      schema source, no drift)
- [ ] `grep -rn 'remote-pi:relay-state\|remote_pi_control' pi-extension/src/protocol/generated/ app/lib/protocol/generated/ relay/src/protocol/generated/` returns nothing
