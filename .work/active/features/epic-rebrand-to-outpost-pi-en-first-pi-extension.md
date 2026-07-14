---
id: epic-rebrand-to-outpost-pi-en-first-pi-extension
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, pi-extension]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + JSDoc gap-fill — pi-extension

## Brief

Translate Portuguese → English and adopt the JSDoc documentation framework
in `pi-extension/`. This is the smallest code slice of the EN-first epic
(6 PT-bearing source files), but it is also the **reference implementation**
of the per-language doc convention: it is the first subproject to run the
full translate + gap-fill pass against
`.agents/skills/documentation-conventions/SKILL.md`, so its design pass
establishes the working pattern (Always-tier export audit → translate
comments → gap-fill missing JSDoc → verify) that the larger Dart slices
inherit by reference.

Covers `pi-extension/src/` only. The 6 PT-bearing files are: `index.ts`,
`mesh/siblings.ts`, `mesh/canonical.ts`, `mesh/canonical.test.ts`,
`session/broker_remote.ts`, `session/cwd_lock.ts`. PT here is comment prose
(no user-facing UI strings — the extension has no UI).

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: **foundation / reference slice** — smallest, no UI, no
  cross-subproject types. Establishes the translate+gap-fill working pattern.
  Other subproject features inherit the approach by reference, not by a hard
  `depends_on` (the convention is already landed; this feature just proves it
  end-to-end on one language first).

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — the Always/Recommended/
  Skip tier model and JSDoc format for TypeScript. This feature's gap-fill
  scope is the Always tier: exported functions/types/classes from shared/domain
  layers, service-layer functions, `Result`/discriminated-union-returning
  functions.
- `.agents/skills/scan-documentation/SKILL.md` — the gate that will verify
  coverage; run it as a self-check before advancing to review.
- Parent epic `## Grounded surface measurement` — the 6-file count.
- Parent epic `## Design prerequisite (landed 2026-07-14)` — the convention is
  already in place; this feature consumes it, does not re-derive it.

## What this feature does NOT cover
- Wire-stable identifiers (auth string, control-RPC discriminator) — owned by
  the first rebrand epic's wire-stable migration feature, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — explicitly out of scope (operator glue; locked
  boundary in the parent epic's parent).
- Generated/vendored state (`node_modules/`, `dist/`).

## Verification
```bash
# from pi-extension/
corepack pnpm typecheck && corepack pnpm test && corepack pnpm build
```
Plus a grep confirming zero PT (accented Latin) in `pi-extension/src/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
Always-tier export audit, per-file translate plan, and gap-fill list. -->
