---
id: feature-cruft-consolidated-cleanup-step-3-pi-extension
kind: story
stage: implementing
tags: [refactor, cleanup, pi-extension]
parent: feature-cruft-consolidated-cleanup
depends_on: [feature-cruft-consolidated-cleanup-step-2-relay]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Consolidated cruft cleanup: pi-extension hot-reload expiry coverage

## Scope

Add the missing deterministic boundary test for the existing armed-request
expiry guard in `pi-extension/src/index.ts`. This is a test addition, not a
removal and not a change to the five-minute behavior.

## Current state

`pi-extension/src/index.ts:3006-3012` verifies the process nonce and then
removes an armed request when its timestamp is more than five minutes old:

```ts
if (typeof request.ts === "number" && Date.now() - request.ts > 5 * 60_000) {
  _removeIfOwnerOnlyRegularFile(armedPath);
  return;
}
```

The existing `extension.test.ts` hot-reload tests cover valid claims, non-idle
deferral, nonce mismatch, daemon/toggle gates, disposal, symlink safety, and
startup cleanup, but not the timestamp boundary with a valid nonce.

## Target state

Extend the existing hot-reload integration coverage with a Vitest fake clock:

1. Arm a valid request and set time to just below `5 * 60_000`; an idle
   `agent_settled` event must still claim, write the restart marker, and invoke
   the mocked `SIGTERM` path. This proves the guard is strictly `>` rather than
   prematurely expiring at the boundary.
2. In an isolated case, arm another valid request, advance just above five
   minutes, and emit `agent_settled`. Assert that it does not claim, write a
   marker, set the quiescing fence, or invoke `SIGTERM`; assert the stale armed
   file is removed.
3. Arm a fresh valid request after the expired case and settle it successfully.
   The follow-up claim proves the expired path did not leave `_hotReloading`
   latched. Reset fake timers, environment variables, process spies, and the
   test fence in `finally` blocks.

Use the production arm command to create the request so the test exercises a
real nonce; do not bypass nonce validation with a fabricated process identity.

## Acceptance criteria

- [ ] The test uses `vi.useFakeTimers()`/`vi.setSystemTime()` and no sleeps or
      wall-clock waits.
- [ ] Just-below expiry is accepted; just-above expiry is rejected and cleans
      the armed file.
- [ ] The expired case proves absence of claim, marker, quiescing, and SIGTERM,
      while the fresh follow-up request proves the fence remains usable.
- [ ] Existing hot-reload tests remain unchanged in assertion strength.
- [ ] `corepack pnpm typecheck` passes.
- [ ] `corepack pnpm test` passes.
- [ ] `corepack pnpm build` passes.

## Implementation

Added one deterministic Vitest integration test around the existing armed-request
expiry guard. It arms through the production command, accepts a request one
millisecond below five minutes, rejects and removes one millisecond above five
minutes, and then proves a fresh valid request can claim afterward. Fake timers
and isolated `OUTPOST_PI_HOME` directories keep the boundary test independent;
production expiry code was not changed.

Targeted verification passed:

- `corepack pnpm exec vitest run src/extension.test.ts -t "armed request expiry keeps the strict five-minute boundary"`
- `corepack pnpm typecheck`
- `corepack pnpm build`

## Blocker

The required full `corepack pnpm test` run is blocked by unrelated concurrent
fresh-session work in the same working tree (`src/index.ts` and the adjacent
fresh-session assertions in `src/extension.test.ts`). The run reached 1,096
passing tests and failed only the two fresh-session ordering tests at
`extension.test.ts:2483` and `2594`; an earlier run also exposed the concurrent
worker's in-flight `delivery_retry` expectation update. The new expiry test
passes in isolation, and no production expiry code is part of this story. Do
not waive the full-suite failures or alter the concurrent fresh-session work;
re-run this story's owning suite after that work is complete.

## Risk

Low to medium. The test exercises process-state files and a mocked signal in a
large integration fixture. Fake time and isolated temporary directories keep
it deterministic; no production behavior changes.

## Rollback

Remove the added boundary test only. The existing expiry guard and all other
hot-reload tests remain intact.
