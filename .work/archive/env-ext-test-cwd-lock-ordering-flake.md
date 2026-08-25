---
status: groom-done
id: env-ext-test-cwd-lock-ordering-flake
created: 2026-07-12
updated: 2026-07-11
tags: [env, testing, pi-extension, flaky]
---

# pi-extension cwd-lock test fails under full-suite ordering (exposed by rebrand)

## Problem

`extension.test.ts` > `same-folder same-name → #N suffix` > "a second same-name
agent joins as <name>#2" fails in the **full suite** (828 pass, 1 fail) but
**passes in isolation** (`vitest run -t "a second same-name agent"`).

## Root cause

The mechanical-rename changed `makeMockCtx`'s default cwd from
`/home/user/projects/remote_pi` → `/home/user/projects/outpost_pi`. Since
`defaultAgentName(cwd) = basename(cwd)`, the default agent name changed from
`remote_pi` → `outpost_pi`, which changes `roomIdFor(cwd, name)` hash, which
changes which `.sock` lock file a prior test in the suite leaves behind.

A prior test (likely the "rename" describe block) acquires a cwd-lock for the
default `(outpost_pi, outpost_pi)` combo. Its cleanup calls
`_resetCwdLockForTest()` (in-memory registry reset) + `stop()`, but if the
Node process / socket isn't fully torn down, a stale `.sock` file remains in
`~/.pi/remote/locks/` and blocks the next `acquireCwdLock` bind.

## This is a pre-existing test-isolation fragility

The rename didn't introduce a product bug — it changed *which* cwd hash
collides under test ordering. The same flake would surface from any change to
the default mock cwd. `acquireCwdLock` has a `removeStaleSock` retry path,
but it apparently doesn't catch this case (the socket may have a live
listener from a prior test's unref'd server that outlives the test).

## Fix direction (not attempted inline — out of rebrand scope)

- Stronger test isolation: the prior describe's `afterEach` should
  unlink `.sock` files for the cwds it used, or `_resetCwdLockForTest()`
  should also unlink stale sockets.
- OR: give the `#N suffix` test its own unique throwaway cwd
  (`/tmp/test-cwd-<random>`) instead of reusing the default mock cwd, so it
  can't collide with prior tests.

## Reproduction

```bash
cd pi-extension
COREPACK_HOME=… corepack pnpm test   # fails (1/832)
# vs
corepack pnpm test -- -t "a second same-name agent joins as"  # passes
```
