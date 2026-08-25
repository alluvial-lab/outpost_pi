---
status: groom-done
id: backlog-extension-hot-reload-restart-sweep-enoent-race
created: 2026-08-03
updated: 2026-08-03
tags: [pi-extension, testing]
---

# Extension suite exits nonzero on a pre-existing hot-reload restart-sweep ENOENT race

## Observation (2026-08-03)

The full `pi-extension` suite (`corepack pnpm test`) exits nonzero even though
all tests pass (`Test Files 55 passed; Tests 962 passed | 3 skipped; Errors 1`).
The single unhandled error is:

```
ENOENT { syscall: 'chmod', path: '/tmp/pi-ext-restart-sweep-XXXX/.pi/remote/locks/YYYY.sock' }
```

It originates from the hot-reload restart-sweep test path (the
`pi-ext-restart-sweep-` temp dir), attributed to
`src/extension.test.ts` / the `plan/32: session_before_compact` test vicinity.
The sweep test deletes its temporary directory before an asynchronous unix-socket
startup (`leader_election`/supervisor path) finishes, so a late `chmod` on the
removed socket path throws.

## Confirmed pre-existing (not a regression)

Reproduced identically on `HEAD` (with the unrelated
`feature-canonical-transcript-ordering` Unit 1 changes stashed): same ENOENT,
same nonzero exit, all tests passing. Surfaced while verifying Unit 1
(`story-canonical-transcript-ordering-extension-broadcast-tool-ts`); that item's
own scope (tool `ts` broadcast + schema + generated artifacts) is unaffected and
its focused tests + `check:protocol` + `typecheck` are green.

## Why parked, not fixed inline

Unrelated test-infrastructure lifecycle race, not a product defect or a
regression from any current work. Fixing it belongs in its own focused
test-isolation slice (quiesce the supervisor/leader-election socket startup
before the sweep's temp-dir teardown, or gate the `chmod` on path existence).

## Direction

Stabilize the restart-sweep test: ensure asynchronous socket lifecycle
startup completes (or is cancelled) before the test deletes its temp dir, so
no late `chmod`/`bind` touches a removed path. Likely a `beforeEach`/`afterEach`
quiesce or an existence guard in the supervisor lock setup. Run the full suite
under load (concurrency) to confirm the race is gone.
