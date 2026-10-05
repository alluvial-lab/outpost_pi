---
id: feature-claude-host-mesh-idle-wake-toggle
kind: story
stage: implementing
tags: [pi-extension, workflow]
parent: feature-claude-host-mesh-idle-wake
depends_on: [feature-claude-host-mesh-idle-wake-qualification]
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Wrapper `--mesh-wake` toggle

Design element: Unit 2 of `feature-claude-host-mesh-idle-wake`.

## Work

`pi-extension/src/extension/command_surface/standalone_cli.ts`:

- `MESH_WAKE_FLAG = "--mesh-wake"`, intercepted at any argv position and
  dropped from passthrough; `splitClaudeCliArgs` returns `meshWake: boolean`.
- `buildClaudeLaunchArgs(mcpConfigPath, skillPath, meshWake)` appends
  `--dangerously-load-development-channels=server:outpost-pi-mesh` when set;
  dedupe against a raw dev-channels flag already present in passthrough
  (both `=` and space variants, targeting `outpost-pi-mesh`).
- Rewrite the safe-default invariant: `--dangerously-skip-permissions` is
  NEVER injected (absolute — authority-widening); the dev-channels wake flag
  only via explicit `--mesh-wake` (starts turns, changes no permission
  policy). JSDoc + the regression-guard test change together, with this
  rationale in both.
- README + `site/src/app/tutorials/claude-mesh/page.tsx`: document the
  toggle; sharpen the "safe defaults" section per the feature's
  Simplification note.

## Acceptance evidence

- `standalone_cli.test.ts`: interception at any position, single expansion,
  dedupe vs raw flag, narrowed regression guard green
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
- README/tutorial updated
