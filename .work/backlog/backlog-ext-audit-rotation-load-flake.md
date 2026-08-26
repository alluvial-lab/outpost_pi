---
id: backlog-ext-audit-rotation-load-flake
created: 2026-08-16
updated: 2026-08-26
tags: [pi-extension, testing, bug]
---

# pi-extension audit-rotation timing tests flake under uncapped full-suite load

Two audit-rotation tests (rotation-without-`.1`-file class, in
`pi-extension/src/transport/peer_channel.test.ts` /
`pi-extension/src/session/e2e.test.ts`) fail intermittently when the full
Vitest suite runs uncapped under VM load; pass focused and pass on capped
full runs (`--maxWorkers=2`). Pre-existing; surfaced in three consecutive
verification runs during the harvest arc (robustness, mesh, and
review-closure workers each hit it once).

Folded in from `backlog-v040-phase8-lower-risk` (groom, 2026-08-26): the
oversized-log regression test relies on fixed 40 ms sleeps
(`pi-extension/src/session/e2e.test.ts:490-500`); audit writes are
detached, so the sleep doesn't deterministically establish setup or
post-append completion under load — same deterministic-rotation-control
treatment applies (explicit audit-flush/barrier seam).

## Work

Replace wall-clock/timing-sensitive rotation assertions with deterministic
control of the rotation trigger (fake timers or explicit tick injection),
per the repo's testing-integrity rule and the
`explicit-async-interleaving-tests` pattern. Goal: green uncapped, not a
permanent worker cap. Check for shared temp-dir/timestamp coupling between
the two tests while there.
