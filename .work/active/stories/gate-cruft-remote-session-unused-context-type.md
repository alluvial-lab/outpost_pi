---
id: gate-cruft-remote-session-unused-context-type
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

# Remove the unused remote-session context type alias

## Confidence
High

## Category
dead type alias

## Location
`pi-extension/src/session/remote_session.ts:21`

## Evidence
```ts
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

export type { RemoteSessionId };

// ...

type SessionIdContext = Pick<ExtensionContext, "sessionManager">;
```

`tsc --noUnusedLocals --noUnusedParameters --noEmit` reports `SessionIdContext` as declared but never used. Repository search finds no reference beyond this declaration.

## Removal
Delete `SessionIdContext` and the now-unneeded `ExtensionContext` type import. Keep the runtime `safeSessionManager` narrowing, which does not depend on this alias.

## Implementation notes

- Execution capability: inline minimal cleanup; this is an isolated unused TypeScript alias and import.
- Removed `SessionIdContext` and the now-unused `ExtensionContext` type import from `pi-extension/src/session/remote_session.ts`; `safeSessionManager` remains unchanged.
- No test was added: the removed alias has no runtime representation or consumer; compile and the full extension suite are the appropriate regression evidence.
- Confirmation: `corepack pnpm typecheck`, `corepack pnpm test` (52 files, 881 passed, 3 skipped), and `corepack pnpm build` passed in `pi-extension/`.
- Bounded inline review: the runtime stale-context narrowing and UUID fallback code were not modified.
