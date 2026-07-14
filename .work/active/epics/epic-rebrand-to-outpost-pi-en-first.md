---
id: epic-rebrand-to-outpost-pi-en-first
kind: epic
stage: drafting
tags: [rebrand, docs, i18n, cockpit, app, pi-extension, relay, site]
parent: null
depends_on: [epic-rebrand-to-outpost-pi]
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-14
---

# EN-first pass + native documentation frameworks

## Brief

A separable workstream from the rebrand: replace Portuguese (PT) with English
(EN) across all shipped product code, docs, comments, and UI strings, **and**
adopt the language-native documentation framework consistently per subproject
so every public API carries an EN doc comment. Promoted from backlog — the
operator confirmed two stances that expand the surface beyond pure
translation.

The first rebrand epic (`epic-rebrand-to-outpost-pi`) explicitly scoped this
out as a separable follow-up: it does not touch wire-stable identifiers or
product-identity strings, and it runs independently of the
external-surfaces epic.

## Strategic decisions (operator-confirmed 2026-07-14)

- **Attribution posture: keep current.** No per-file provenance headers. MIT
  permits modification without per-file attribution, and the root `LICENSE`
  already credits `Copyright (c) 2026 Jacob Moura` + `Copyright (c) 2026 Kevoun`
  for all contributions. The `NOTICE` file credits `remote_pi` / Jacob Moura
  as the foundation. The MIT obligation is met at the license tier; adding
  252 boilerplate headers is churn without legal value. Provenance lives in
  `LICENSE`/`NOTICE` where MIT wants it. (This was chosen after measuring
  that 130 of the 252 PT-bearing files are currently byte-identical to
  upstream — the posture applies uniformly whether a file is being first
  modified or already was.)

- **Documentation framework: adopt the native one per language, consistently,
  AND translate to EN.** Not just translate existing comments — gap-fill so
  every public API has a doc comment in EN using the language-native tool:
  - **Dart (`app/`, `cockpit/`)** — dartdoc `///` comments. 294 dart files
    already carry `///` comments; the pass standardizes on this and fills
    gaps on public APIs that lack them.
  - **TypeScript (`pi-extension/`)** — JSDoc `/** */` on exported functions,
    types, and classes.
  - **Rust (`relay/`)** — rustdoc `///` on `pub` items.
  - **Site (`site/`, Next/React)** — component-level doc comments where
    idiomatic (React components don't have a single canonical framework; use
    JSDoc on exported component functions and hooks).
  The convention is "native tool per language, EN, on every public API."

- **Work structure: defer to `epic-design`.** The decomposition (one feature
  with subproject child stories vs. one feature per subproject) is an
  `epic-design` call, not a scoping call. The surface measurement (below) is
  the input.

## Grounded surface measurement (2026-07-14)

PT-bearing files in shipped product (excluding `scripts/` operator glue per
the locked boundary, and excluding generated/vendored state):

| Subproject | PT-bearing files |
|---|---|
| `cockpit/` | 216 |
| `app/` | 23 |
| `pi-extension/` | 7 |
| `site/` | 2 |
| `relay/` | 2 |
| `docs/` | 1 |
| `branding/` | 1 |
| **Total** | **252** |

(The first rebrand epic's "~186 files" estimate was low; the measured count
is 252. Cockpit remains the bulk, as the epic predicted.)

Of those 252, 130 are currently byte-identical to upstream `remote_pi`; 113
are already modified from upstream; 9 are net-new. This split is recorded for
provenance awareness but does **not** change the attribution posture (above)
— it's a stance, not an obligation, and applies uniformly.

## Scope

1. **Translate PT → EN** in all 252 files: code comments, doc strings,
   user-facing UI text, and docs. Mechanical translation with domain-vocabulary
   review (confirm no PT term is intentional domain vocabulary before bulk
   replacement).
2. **Adopt the native doc framework per language** and gap-fill: every public
   API (exported Dart class/function, TS export, Rust `pub` item, React
   component/hook) gets an EN doc comment in the language-native style.
3. **Write the documentation convention down** in `.agents/skills/` so future
   code follows one style (the convention the pass adopts — not a separate
   design tier, just a durable reference recording the stance).

## What this epic does NOT cover

- `scripts/` shell comments — explicitly out of scope (operator glue; the
  first rebrand epic locked this boundary).
- PT in generated/vendored files (`.pub-cache/`, `node_modules/`,
  `.xdg-cache/`, build output) — not shipped product.
- Product-identity string renames (the mechanical-rename feature owns that).
- Wire-stable identifiers (the wire-and-install-stable-migration feature
  owns that).
- Per-file provenance headers (rejected per the attribution posture above).

## Foundation references
- Parent epic `epic-rebrand-to-outpost-pi` `## EN-first scope` — the boundary
  decision and `scripts/` exclusion.
- `.agents/rules/documentation-discipline.md` — current-state docs, not
  progress logs; the convention reference goes in `.agents/skills/`.
- `LICENSE` / `NOTICE` — the attribution surface (unchanged by this epic).

## Design prerequisite (landed 2026-07-14)

The documentation convention is now in place at
`.agents/skills/documentation-conventions/SKILL.md`, with a matching
`scan-documentation` gate skill (auto-loads via the `scan-*/SKILL.md` glob).
`epic-design` and the child features reference these instead of re-deriving
the doc-framework stance. The convention adapts the SNC/platform three-tier
intent model (Always / Recommended / Skip) to Outpost-Pi's four languages:
JSDoc (TS), dartdoc `///` (Dart), rustdoc `///` (Rust), JSDoc-on-components
(React). It pins the per-language definition of "public API" (the open-ended
risk flagged below) via the Always-tier marker table.

## Decomposition risks (for epic-design)

- **Cockpit is 216/252 files** — the decomposition must handle the cockpit
  slice's size; it may warrant its own feature or sub-slicing.
- **2(b) gap-filling is bounded by the convention's Always tier** — "every
  public API gets a doc comment" is now defined per language in
  `.agents/skills/documentation-conventions/SKILL.md` (exported TS symbol,
  public Dart declaration, Rust `pub`, exported React component with 3+
  props). The Skip tier (schema decls, barrel re-exports, tests, trivial
  helpers, generated code) is explicitly out of scope, so gap-fill is not
  open-ended.
- **User-visible UI text needs review, not just mechanical translation** —
  some PT strings are user-facing and need translation-review, not sed.
- **Tests gate each slice** — `flutter analyze` + `flutter test` (app,
  cockpit), `corepack pnpm typecheck`/`test` (pi-extension), `cargo
  fmt`/`clippy`/`test` (relay), `pnpm lint`/`build` (site). The EN pass must
  not break any.

## Verification

From the owning subproject roots per `.agents/rules/testing-integrity.md`:

```bash
# pi-extension
corepack pnpm typecheck && corepack pnpm test

# app
flutter analyze && flutter test

# cockpit
flutter analyze && flutter test

# relay
cargo fmt --check && cargo clippy -- -D warnings && cargo test

# site
pnpm lint && pnpm build
```

Plus a repo-wide grep confirming zero PT (accented Latin) in shipped product
source, excluding `scripts/` and generated/vendored state.
