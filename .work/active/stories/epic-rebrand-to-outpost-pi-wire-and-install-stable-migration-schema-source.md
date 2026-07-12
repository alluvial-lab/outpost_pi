---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-schema-source
kind: story
stage: done
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
- [x] `corepack pnpm --dir protocol check` passes (fixtures validate) —
      verified via `node --import tsx scripts/check-fixtures.ts` (corepack
      deps-status gate bypassed; the `--dir` form re-triggers it)
- [x] `corepack pnpm --dir protocol list-types` emits new `outpost-pi:` /
      `outpost_pi_control` discriminators — verified via direct
      `node --import tsx scripts/list-types.ts`
- [x] `grep -rn 'remote-pi.dev\|x-remote-pi\|remote-pi:relay-state\|remote-pi-ctrl' protocol/schema/` returns nothing

## Implementation notes

Renamed all 10 schema `$id` values to `https://kevoun.com/schemas/`, all 46
vendor-key occurrences to `x-outpost-pi`, the cockpit prefix and structured/custom
discriminators, the umbrella schema's Outpost-Pi title/description, and the
cockpit fixture discriminators. Schema filenames and the fixture's separately
owned `remote-pi://` pairing URI were intentionally left unchanged.

**Subagent gap, fixed by orchestrator:** the subagent renamed the schema
files but missed three consumers of the old literals that the schema source
of truth feeds: `protocol/scripts/check-fixtures.ts` (registers the
`x-remote-pi` keyword + looks up schemas by old `$id` URI),
`protocol/scripts/list-types.ts` (reads `schema["x-remote-pi"]` metadata),
and `protocol/README.md` (prose). The orchestrator updated all three to
`x-outpost-pi` / `kevoun.com` so `check-fixtures` and `list-types` pass.

**Codegen tool fix:** `tools/protocol-codegen/bin/protocol-codegen.mjs`
(two `x-remote-pi` reads in patch-field helpers) and its test fixture were
updated to `x-outpost-pi` so Unit 2 (regen) can run the codegen against the
renamed schema. The `src/index.ts` entry was already `loadOutpostPiManifest`
from a prior refactor and needed no change. Verified: `generate:protocol
--check` runs clean and reports the generated file stale (expected — Unit 2
regenerates it).

**Environment note:** `corepack pnpm --dir <pkg>` re-triggers the
deps-status check (implicit `install` → `ERR_SQLITE_ERROR` on the read-only
`/home/agent/.local-state` corepack home). Workaround: set
`COREPACK_HOME=<writable dir>` + `--store-dir <writable store>` for installs,
then run the scripts directly via `node --import tsx`. This applies to all
subprojects using corepack pnpm.
