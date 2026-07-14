---
id: epic-rebrand-to-outpost-pi-en-first-relay
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, relay]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + rustdoc gap-fill — relay

## Brief

Translate Portuguese → English and adopt the rustdoc documentation framework
in `relay/`. The smallest code slice alongside pi-extension: 1 PT-bearing
source file (`relay/src/protocol/outer.rs`). PT is comment prose; the relay
has no user-facing UI strings.

Covers `relay/src/` only. Gap-fill scope is the Always tier per the doc
convention: `pub` items (functions, structs, enums, traits) get rustdoc `///`
comments with `# Errors` sections where the function returns a `Result`.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent small slice. No `depends_on` — the relay's
  wire-stable identifiers already migrated in the first rebrand epic; this is
  pure comment/doc work. Can run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — rustdoc `///` format
  and the Always tier (`pub` items). The `# Errors` section convention for
  `Result`-returning functions is shown in the skill's Rust example.
- `.agents/skills/rust-relay/SKILL.md` — relay code reference; read before
  editing `relay/`.
- Parent epic `## Grounded surface measurement` — the 1-file count.

## What this feature does NOT cover
- Wire-stable identifiers (auth domain string) — owned by the first rebrand
  epic's wire-stable migration feature, already shipped.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`target/`).

## Verification
```bash
# from relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build
```
Plus a grep confirming zero PT (accented Latin) in `relay/src/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
`pub`-item audit and per-item rustdoc plan. -->
