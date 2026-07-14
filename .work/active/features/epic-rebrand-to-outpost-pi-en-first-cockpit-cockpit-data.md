---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + dartdoc gap-fill — cockpit module: data layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **data layer** (`cockpit/lib/app/cockpit/data/`):
adapters, filesystem, notifications, repositories, rpc, setup, terminal.
21 PT-bearing Dart files. This layer holds the infrastructure adapters
(ports-and-adapters edge) — repository implementations, RPC clients, terminal
PTY, filesystem access.

PT is comment prose. Gap-fill scope is the Always tier: service-layer
functions, adapter classes with non-obvious contracts, `Result`-returning
functions. Repository implementations that merely satisfy a domain contract
are Skip tier for gap-fill (the contract is documented at the port, not the
adapter) — the design pass should distinguish adapter-specific behavior worth
documenting from contract restatement.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module. Sibling
  slices: `...-cockpit-domain`, `...-cockpit-cockpit-ui`. No `depends_on`
  between the three layers — disjoint file sets, shared build gate. Can run
  in parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format;
  Always tier (service-layer functions) vs Skip tier (DTOs/contract
  restatement).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- `.agents/rules/code-design.md` — Ports and Adapters; the data layer is the
  adapter edge, so document adapter-specific behavior, not the port contract.

## What this feature does NOT cover
- The cockpit module's `domain/` and `ui/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

10 cockpit data test files carry PT: `cockpit/test/data/`
(`git_status_reader_impl_test.dart`, `lsp_server_pool_test.dart`,
`file_reader_impl_test.dart`, `lsp_formatter_test.dart`,
`lsp_text_edit_test.dart`, `lsp_root_and_offsets_test.dart`,
`file_system_mutator_impl_test.dart`, `worktree_manager_impl_test.dart`,
`auto_updater_self_updater_test.dart`, `lsp_codec_test.dart`). Tests are
Skip-tier for gap-fill (per the doc convention); the only work is PT→EN
translation of comments and test descriptions (the latter are user-facing in
test output and need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/data/` and `cockpit/test/data/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
adapter/service export audit and the gap-fill list. -->
