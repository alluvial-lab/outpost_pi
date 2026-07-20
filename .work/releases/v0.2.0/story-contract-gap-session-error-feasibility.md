---
id: story-contract-gap-session-error-feasibility
kind: story
stage: done
tags: [pi-extension, app, docs]
parent: feature-contract-gap-audit
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-07-19
updated: 2026-07-20
---

# Determine whether session lineage can support typed mismatch errors

## Checkpoint

Complete Track B as a feasibility spike, not a wire-design pass. Trace the
installed Pi SDK's session lineage exposed to `ExtensionContext`, the
Outpost-Pi `session_new` call, and relay fanout. Then verify that the already
shipped app-side behavior protects both required cases:

1. a mismatch response from a foreign/duplicate Pi does not render an error;
2. a canonical room-metadata session rotation still triggers `session_sync`.

## Acceptance evidence

- [x] State whether the current extension can reliably classify a received
      `session_id` as the predecessor of its active session.
- [x] State whether that classification would distinguish cross-process
      duplicate fanout.
- [x] Cite the tests protecting foreign-error suppression and legitimate
      stale-session resync.
- [x] Do not add `session_superseded` / `not_my_session` wire codes unless both
      cases are distinguishable at the extension boundary.

## Feasibility result

**Verdict: do not add typed mismatch subcodes.** The installed Pi SDK exposes
`ExtensionContext.sessionManager` as a `ReadonlySessionManager`. Its
`getHeader()` can carry an optional `parentSession`, but that value is a parent
*file path*, not a retained set of predecessor session ids.

More importantly, ordinary Outpost-Pi `session_new` calls
`ctx.newSession({withSession})` without `parentSession`
(`pi-extension/src/actions/handlers.ts`). Pi's
`AgentSessionRuntime.newSession()` only writes lineage when the caller supplies
that option, so the ordinary successor has no predecessor fact to classify.
Forked sessions may carry a parent path, but resolving that path would require a
filesystem read and still says nothing about another Pi process receiving the
same relay fanout. No extension-local lineage can distinguish a wrong-process
copy from a genuinely stale phone in the general case.

The least irreversible behavior is therefore the already-shipped app-side
rule from `story-foreign-session-user-message-tolerance`: keep the extension's
single fail-closed `session_mismatch`; let the app's session gate discard a
foreign Pi's reply; treat an accepted mismatch as non-transcript control; and
request `session_sync` only after canonical room metadata rotates the active
session.

## Regression evidence

- `pi-extension/src/session/session_gate.test.ts` proves stale and missing
  session ids are rejected before SDK delivery.
- `app/test/data/sync/sync_service_test.dart` → `session_mismatch tolerance`
  proves a duplicate Pi's foreign reply renders no warning, an accepted
  current-session mismatch also renders no warning, and canonical metadata
  rotation syncs the new session.
- `PROTOCOL.md` already pins the app-side convergence rule; no schema or wire
  code changed in this spike.
