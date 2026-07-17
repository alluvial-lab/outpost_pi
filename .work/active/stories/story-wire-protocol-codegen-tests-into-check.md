---
id: story-wire-protocol-codegen-tests-into-check
kind: story
stage: done
tags: [protocol, testing]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-16
---

# Run protocol-codegen unit tests from canonical verification

## Review origin

Important finding from the deep review of `feature-outpost-pi-identifier-convergence`.

## Problem

`tools/protocol-codegen/src/index.test.ts` is not executed by `protocol`'s `check` or `generate:rust:check`, by `pi-extension`'s Vitest suite, or by a discovered CI command. The auth-contract implementation added assertions to this file, but the repository's recorded green verification never ran it. A direct review invocation exposed a stale `KnownErrorCode` assertion that had been broken since `delivery_pending` joined the generated union; the reviewer fixed that immediate test drift inline, but the systemic verification gap remains.

## Scope

- Add a canonical script that runs `tools/protocol-codegen/src/index.test.ts` using the `protocol` package's installed `tsx` dependency.
- Include it in the normal protocol verification path (preferably `corepack pnpm --dir protocol check`) so codegen unit-test failures cannot be skipped while fixture and generated-file checks remain green.
- Update `protocol/README.md` with the canonical command if the existing `check` command is not made aggregate.
- Keep dependency resolution rooted in `protocol/`; do not require an undeclared root `tsx` install.

## Acceptance criteria

- [ ] The normal documented protocol verification executes all protocol-codegen unit tests.
- [ ] A failing assertion in `tools/protocol-codegen/src/index.test.ts` makes that verification exit non-zero.
- [ ] `corepack pnpm --dir protocol check`, `corepack pnpm --dir protocol generate:rust:check`, and `corepack pnpm --dir pi-extension check:protocol` pass.
