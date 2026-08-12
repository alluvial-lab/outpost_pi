# 2026-08-12 — pairing-e2e room-ID divergence fix (CI RED → GREEN)

Fresh-context entry point: this closed **Priority 1** from
`2026-08-12-resume-parked-work.md` (the red CI). Read together with
`backlog-pairing-e2e-room-id-divergence.md` (full characterization + hash proof).

## TL;DR
CI was red on every push since `56c5701`. Root cause: the e2e pi-host **status
harness re-derived** the App↔Pi room with a hardcoded name
(`roomIdFor(cwd, "e2e-agent")`), while the production extension derives its
actual registered room from the **mesh-assigned** name, which carries a broker
collision suffix (`e2e-agent` → `e2e-agent#2`). On any collision the status room
diverged from the QR/pair-code/peer room → every `*.roomId == status.roomId`
assertion failed (non-deterministic subset). Fix: expose the production
`_myRoomId` via a `roomId()` test accessor and have status report it. Verified
`bash e2e/run-pairing.sh` 16/16 green (collision reproduced in-run, still green).

## How the diagnosis was pinned (technique worth repeating)
The symptom (status room `wc3B14rFnkrH` ≠ QR room `KzJ3MohnQOvq`) was cryptic.
The decisive move was **hashing candidate derivations** against the observed
room IDs:

| derivation | hash | matches |
|---|---|---|
| `roomIdFor(cwd, "e2e-agent")` | `wc3B14rFnkrH` | status room ✓ |
| `roomIdFor(cwd, "e2e-agent#2")` | `KzJ3MohnQOvq` | QR room ✓ |
| `roomIdForCwd(cwd)` (legacy) | `A1a0RKUXF5K6` | neither |

That instantly localized the bug to the **name** axis (`e2e-agent` vs
`e2e-agent#2`) and identified the status harness's hardcoded re-derivation as
the sole wrong code path. The QR room was production-truth all along.

## The fix (3 files, +32/-2)
- `pi-extension/src/extension/testing.ts` — added `roomId(): string | null` to
  `OutpostPiTestHarness` with a self-defending doc comment.
- `pi-extension/src/index.ts` — added `getRoomIdForTest()` returning `_myRoomId`;
  wired `roomId: () => getRoomIdForTest()` into the harness singleton.
- `pi-extension/test/support/e2e_pi_host_runtime.ts` — `status()` reads
  `outpostPiTestHarness.roomId() ?? roomIdFor(cwd, "e2e-agent")` (the idle
  fallback is the no-mesh derivation, never the asserted state); inline
  `ProductionModule` type updated to match.

**Why this isn't test-gaming:** the status endpoint is a TEST HARNESS whose job
is to report the production extension's actual state. It was reporting a room
the extension never registered. Reading `_myRoomId` makes it report truth.

## Why the collision happens (and why we did NOT "fix" it)
The `#2` suffix arises because `restartForIsolation()` (`process.exit(0)` +
Docker `restart: unless-stopped`) can leave a stale `e2e-agent` mesh
registration that the next generation's broker disambiguates with `#N`. This is
**documented expected production behavior** (`mesh_node.ts`: "broker may add a
#N collision suffix") — the production room derivation is correct under it. The
harness was the only thing guessing. Making the harness report truth is the
complete fix; chasing the collision would be papering over a correct production
path.

## Verification
- `tsc --noEmit` clean; `tsc` build clean.
- `vitest run src/extension.test.ts …` → 226 passed (1 pre-existing unrelated
  teardown ENOENT race on a restart-sweep temp socket).
- `bash e2e/run-pairing.sh` (with prebuilt `outpost-pi-relay:0.4.0` to skip the
  Rust rebuild — relay is room-blind) → **16/16 e2e passed**, redaction canaries
  passed. Logs showed `room=KzJ3MohnQOvq` (= `e2e-agent#2`) — the collision
  occurred and the suite still passed.

## Lesson
The earlier "parallel-contamination flake" diagnosis was wrong; the
"divergence" diagnosis was right but stopped short of the mechanism. Hashing the
observed IDs against the `roomIdFor` formula turned a 1-day mystery into a
5-minute localization. **When two opaque IDs diverge, brute-force the derivation
inputs against the hash function.**
