---
id: feature-outpost-pi-identifier-convergence-protocol-schema
kind: story
stage: implementing
tags: [rebrand, protocol, docs]
parent: feature-outpost-pi-identifier-convergence
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Converge protocol package, schema, fixtures, and docs

Implements Units 1, 2, and 5-docs of `feature-outpost-pi-identifier-convergence`.

## Scope

- Rename `protocol/package.json` `@remote-pi/protocol-schema` → `@outpost-pi/protocol-schema`; update the description.
- `git mv protocol/schema/remote-pi.schema.json protocol/schema/outpost-pi.schema.json`; update its `$id` and all `$ref`/cross-references across `protocol/schema/*.json`, `manifest.json`, `README.md`, and `tools/protocol-codegen` references.
- Replace "Remote Pi" titles/descriptions with "Outpost-Pi" across every `protocol/schema/*.json` (defs, families, umbrella).
- Update `protocol/fixtures/app-pi/server-messages.jsonl` `session_name` `remote_pi · repo` → `outpost_pi · repo`.
- Update `tools/protocol-codegen/src/index.test.ts` test descriptions ("real Remote Pi schema emits…").
- Replace live-product "Remote Pi" references in maintained docs/comments (`CLAUDE.md`, `AGENTS.md` operational vocabulary, `docs/agent-reference-surface.md`, `protocol/schema/reachability.md`, `pi-extension/src/protocol/session_scope.ts:1`, `app/lib/domain/entities/remote_session_ref.dart:1` doc comment) where they describe the current product, not provenance.

## Preserve

- `relay/src/auth/auth_test.rs:128` legacy `remote-pi-relay-auth-v1\n` literal (rejection test).
- Provenance lines in `AGENTS.md:12`, `docs/DECISIONS.md:40`, `docs/VISION.md:9,66`.
- `kevoun.com` `$id` domain (already migrated).
- PROTOCOL.md trust-model correction is out of scope (separate docs story).

## Verification

```bash
export COREPACK_HOME=/tmp/remote-pi-corepack XDG_CACHE_HOME=/tmp/remote-pi-xdg PNPM_HOME=/tmp/remote-pi-pnpm-home CI=true
corepack pnpm --config.store-dir=/home/agent/projects/remote_pi/.pnpm-store --config.confirmModulesPurge=false --dir protocol check
corepack pnpm --config.store-dir=/home/agent/projects/remote_pi/.pnpm-store --config.confirmModulesPurge=false --dir protocol generate:rust:check
```

If `generate:rust:check` shows the generated file changed (titles/descriptions flowing into generated code), regenerate and commit `relay/src/protocol/generated/*.rs` in this story.

`rg 'remote-pi|Remote Pi|@remote-pi' protocol/ tools/protocol-codegen/` must return only the documented legacy test literal.
