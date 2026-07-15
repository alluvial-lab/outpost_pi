---
id: epic-rebrand-to-outpost-pi-en-first
kind: epic
stage: review
tags: [rebrand, docs, i18n, cockpit, app, pi-extension, relay, site]
parent: null
depends_on: [epic-rebrand-to-outpost-pi]
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-15
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

## Decomposition

Split by subproject, with the cockpit module sub-sliced by layer because it
is 216/252 files — too large for one feature-design→implement pass. The
operator-confirmed strategic decisions (attribution posture, native doc
framework + gap-fill, `scripts/` exclusion) are inherited by every child;
the only thing deferred to this decomposition was the *shape*, and the
measured surface (PT is ~2,100 comment-lines vs ~18 user-facing string
literals in cockpit) confirmed the bulk is mechanical comment translation,
with a small bounded translate-review surface for UI strings and test
descriptions.

All 10 child features are independent (no `depends_on` between them): the
wire-stable identifiers already migrated in the first rebrand epic, so no
child shares a type or contract with another. They can all run in parallel.
The four cockpit features share the `flutter analyze` + `flutter test` build
gate but own disjoint file sets (separate flutter_modular modules / layers +
their mapped test dirs).

### Child features

- `epic-rebrand-to-outpost-pi-en-first-pi-extension` — TS/JSDoc; 6 files;
  reference slice (first to prove the convention end-to-end) — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-relay` — Rust/rustdoc; 1 file —
  depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-app` — Dart/dartdoc; 21 files;
  onboarding + update-banner UI strings need review — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-site` — React/JSDoc; 2 files;
  tutorial page is translate-review prose — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-cockpit-core` — Dart/dartdoc; 54 lib
  files + 4 root tests; owns the generated `file_icon_map.g.dart` header
  edge case — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain` —
  Dart/dartdoc; 43 lib files + 4 tests; contract-bearing gap-fill heart —
  depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui` —
  Dart/dartdoc; 38 lib files + 1 test; user-facing widget/viewmodel strings
  need review — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data` —
  Dart/dartdoc; 21 lib files + 10 tests; adapter edge (document
  adapter-specific behavior, not port contracts) — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-cockpit-settings` —
  Dart/dartdoc; 25 lib files; settings-panel UI strings need review —
  depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first-prose-surfaces` — cross-cutting
  prose/config (branding SVG comments + README, `docs/`, per-subproject
  `CLAUDE.md` files, cockpit non-Dart config/packaging); no gap-fill (Skip
  tier); owns the seam files between the code slices — depends on: `[]`

### Decomposition risks

- **Cockpit is 216/252 files** — resolved by sub-slicing the cockpit module
  by layer (domain/ui/data) plus separate `core` and `settings` module
  features. Each cockpit feature is 21–58 files, within the one
  feature-design→implement pass range. The four cockpit features share the
  build gate but own disjoint file sets.
- **2(b) gap-filling is bounded by the convention's Always tier** — "every
  public API gets a doc comment" is defined per language in
  `.agents/skills/documentation-conventions/SKILL.md` (exported TS symbol,
  public Dart declaration, Rust `pub`, exported React component with 3+
  props). The Skip tier (schema decls, barrel re-exports, tests, trivial
  helpers, generated code) is explicitly out of scope, so gap-fill is not
  open-ended.
- **User-visible UI text needs review, not just mechanical translation** —
  the measured surface is small (~18 PT string literals cockpit-wide, plus
  PT test descriptions in cockpit tests). The app, site, cockpit-ui, and
  cockpit-settings features flag this in their briefs; their design passes
  must split comment-translation (sed-safe) from UI-string/test-description
  translation (review).
- **Generated file edge case** — `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart`
  is generated and shipped; its header comment carries PT. Translate the
  header (one-time edit; the generator source is a script, out of scope per
  the `scripts/` exclusion, so it won't regenerate in this epic), skip
  gap-fill on the generated body. Owned by the cockpit-core feature.
- **Branding boundary with the external-surfaces epic** — that epic (at
  `review`) already migrated the wordmark/URL text in `branding/banner.svg`.
  This epic's prose-surfaces feature owns only the *remaining* PT in branding
  (SVG comment prose + README), not the already-migrated text nodes. The
  feature brief records this boundary explicitly.
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

## Follow-up scope (2026-07-14)

A post-epic scan found Portuguese still present in maintained CI/release
workflows, dormant `rp-s3` product tooling, Claude scout definitions, and the
identity package documentation. The epic is reopened for
`story-en-first-residual-maintained-surfaces`; intentional multilingual codec
fixtures and the existing `scripts/` exclusion remain out of scope.

## Child features reviewed and complete (2026-07-15)

All child features are `stage: done` with cross-model fresh-context reviews
recorded. Epic advanced `implementing → review` for the deeper aggregate
review per the review skill's roll-up rule.
