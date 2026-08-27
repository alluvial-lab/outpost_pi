---
id: story-upgrade-pi-sdk-and-node-floor
kind: story
stage: done
tags: [pi-extension, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Pi SDK 0.80.6→0.84.3 adapter migration + Node engine floor correction

Fix declared Node floor (>=20 → >=22.19, required by SDK 0.80.6 TODAY) then the 0.84.3 adapter migration. Full extension suite + build green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` at `xhigh`; selected for a breaking SDK adapter and lifecycle migration with a full-suite verification boundary.
- Review weight: `standard` (project default); independent review is not applicable to a child-story checkpoint.
- Files changed: `pi-extension/package.json`, `pi-extension/pnpm-lock.yaml`, `pi-extension/src/actions/{registry,handlers}.ts`, their handler tests, `pi-extension/src/index.ts`, the SDK lifecycle harnesses, current extension docs/install surfaces, the byte-identical `site/public/install.sh` copy, `.github/dependabot.yml`, and `.agents/skills/pi-extension-typescript/SKILL.md`.
- Tests added/removed: no net test-count change; existing model-registry tests now exercise asynchronous refresh/rejection, the compaction failure test now covers Pi 0.84's `session_compact_failed` convergence path, and real-SDK harness fakes implement the new abort-before-replacement and scoped-model context contracts.
- Simplification: removed the obsolete `AuthStorage`/`ModelRegistry.create` adapter and the Dependabot ignore that deferred this migration.
- Discrepancies from design: none. CI already runs Node 24, so its runtime satisfies the corrected floor without a workflow edit; `message_update`, `sendUserMessage`, command registration, and the used `ExtensionAPI` contracts remained source-compatible after audit.
- Adjacent issues parked: none.

## Closure note

- Corrected the extension's Node engine floor from `>=20.0.0` to `>=22.19.0`, updated both installer copies and current docs/comments, and retained CI's already-compatible Node 24 configuration.
- Upgraded the exact Pi SDK family from 0.80.6 to 0.84.3. The fallback catalog now creates `ModelRuntime` asynchronously and wraps it in `ModelRegistry`; registry reads await `refresh()`. Lifecycle integration now closes compaction working state on `session_compact_failed`, and SDK harnesses model abort-before-replacement plus `ctx.scopedModels`.
- Verification: `corepack pnpm typecheck` green; full Vitest suite green (`60` files, `1103` passed, `3` skipped); `corepack pnpm build` green. Both installer scripts pass `bash -n` and are byte-identical.
- Runtime verification remains pending until the operator's next full Pi process restart. `/reload` cannot re-import this ESM `dist/`, and the running Pi process was intentionally not restarted during this story.
