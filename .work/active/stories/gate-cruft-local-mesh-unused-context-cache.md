---
id: gate-cruft-local-mesh-unused-context-cache
kind: story
stage: implementing
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
