---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-schema-source
kind: story
stage: implementing
tags: [rebrand, protocol, docs]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Protocol schema rename (the source of truth)

## Scope

Unit 1 of the wire-stable migration feature. Rename the wire-discriminator
strings, vendor key, and `$id` URIs in `protocol/schema/`. This is the source
of truth per the generated-contracts principle — Units 2-6 derive from it via
codegen or hand-edit.

## Units implemented
- Unit 1 (schema source)

## Changes
- All 10 schema files: `$id` `https://remote-pi.dev/schemas/...` →
  `https://kevoun.com/schemas/...`
- All 9 schema files: vendor key `x-remote-pi` → `x-outpost-pi`
- `cockpit-control.schema.json`: NUL-prefix pattern `\u0000remote-pi-ctrl:`
  → `\u0000outpost-pi-ctrl:`, `controlVerb` prefix, all five `customType`
  consts (`remote-pi:relay-state` → `outpost-pi:relay-state`, etc.), and the
  `customMessage` `customType` enum list
- `remote-pi.schema.json` `title`/`description` → `Outpost-Pi`
- `protocol/fixtures/cockpit/cockpit-control.jsonl` → new discriminators
- **Do NOT rename the schema filenames** (`remote-pi.schema.json` etc.) —
  that's the mechanical-rename feature; `$ref` paths stay filesystem-relative.

## Acceptance Criteria
- [ ] `corepack pnpm --dir protocol check` passes (fixtures validate)
- [ ] `corepack pnpm --dir protocol list-types` emits new `outpost-pi:` /
      `outpost_pi_control` discriminators
- [ ] `grep -rn 'remote-pi.dev\|x-remote-pi\|remote-pi:relay-state\|remote-pi-ctrl' protocol/schema/` returns nothing
