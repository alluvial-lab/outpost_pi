---
id: gate-refactor-lifecycle-owner-ingress-floating
kind: story
stage: done
tags: [pi-extension]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-28
---

# Observe asynchronous owner-ingress routing failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/index.ts:319`

## Issue
The relay outer-message callback explicitly voids `_handleOwnerOuterFrame(...)` without awaiting, returning, or attaching a rejection handler, so a rejected asynchronous peer lookup can escape as an unhandled promise failure.

## Fix
Return the routing promise through an owned async dispatch boundary or attach an explicit rejection observer that records a payload-free diagnostic while preserving the connection-generation guard.

## Design checkpoint
Current HEAD has already converged on the preferred boundary: the `index.ts` `onOuterMessage` callback implicitly returns `_handleOwnerOuterFrame(...)`, and `extension/relay_transport.ts` awaits handler promises inside the generation-owned retained-dispatch FIFO. Preserve that signature and add/confirm regression evidence rather than adding a second fire-and-forget catch layer.

```ts
function _handleOwnerOuterFrame(
  ingress: Extract<DecodedRelayIngress, { kind: "outer" }>,
  connectionIsCurrent: () => boolean,
): Promise<boolean>;
```

## Acceptance evidence
- An explicit async handler rejection is observed by the dispatch drain, releases accounting, and does not prevent a subsequent healthy frame.
- No process-level unhandled rejection occurs.
- Connection-generation invalidation still prevents a stale lookup from attaching/publishing, and successful attachment still precedes fanout of its triggering protected frame.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent; this finding therefore has reduced review isolation.

## Implementation notes

- Confirmed the production registration already returns `_handleOwnerOuterFrame(...)` and `RelayTransport` awaits it in the generation-owned retained-dispatch FIFO; no duplicate catch layer or source rewrite was needed.
- Added an explicit async-rejection regression proving the failure is observed, pending accounting is released, a later healthy owner frame routes, and no process-level `unhandledRejection` fires.
- Changed `pi-extension/src/extension/relay_transport.test.ts` only.
- Verification: `tsc --noEmit`; targeted relay-transport suite (18 passed); full Vitest suite (945 passed, 3 skipped; 55 files).
