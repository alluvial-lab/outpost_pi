---
id: gate-cruft-local-mesh-unused-context-cache
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-20
---

# Remove the unused LocalMeshCommands context cache

## Confidence
High

## Category
dead state

## Location
`pi-extension/src/extension/command_surface/local_mesh_commands.ts:69`

## Evidence
```ts
private lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;

private rememberCtx(ctx: Pick<ExtensionContext, "ui" | "cwd">): void {
  const maybe = ctx as Partial<Pick<ExtensionContext, "ui" | "abort" | "cwd">>;
  this.lastCtx = {
    ui: maybe.ui as ExtensionContext["ui"],
    abort: typeof maybe.abort === "function" ? maybe.abort.bind(ctx) : (() => undefined),
    cwd: typeof maybe.cwd === "string" ? maybe.cwd : process.cwd(),
  };
}
```

`tsc --noUnusedLocals --noUnusedParameters --noEmit` reports `lastCtx` as declared but never read. Repository search finds only this field's assignments and reset; `root`, `setup`, and `join` call `rememberCtx`, but no consumer observes its stored context.

## Removal
Delete `lastCtx`, `rememberCtx`, and the three write-only call sites; retain the command operations' direct use of their current `ctx`.

## Implementation notes

- Execution capability: inline minimal cleanup; the cache is private write-only state in one command adapter.
- Removed `lastCtx`, `rememberCtx`, its three calls from `root`, `setup`, and `join`, and the reset assignment from `pi-extension/src/extension/command_surface/local_mesh_commands.ts`.
- No test was added: the removed cache has no observable consumer; compile and the full extension suite are the appropriate regression evidence.
- Confirmation: `corepack pnpm typecheck`, `corepack pnpm test` (52 files, 881 passed, 3 skipped), and `corepack pnpm build` passed in `pi-extension/`.
- Bounded inline review: direct command-context use and all mesh/relay control flow remain unchanged; removal leaves no stored or stale context path.
