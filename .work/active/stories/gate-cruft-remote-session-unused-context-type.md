---
id: gate-cruft-remote-session-unused-context-type
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
