# Run notes — implement-orchestrator 2026-07-17/18 (COMPLETE)

## Outcome

All 6 implementing features advanced to `stage: done` through the full
implement-orchestrator lifecycle (implement → review → fix → done). 52 commits,
clean working tree, no push.

## Final feature states

| Feature | Subproject | Review outcome |
|---|---|---|
| `feature-retire-legacy-piext-composition-seams` | pi-extension | ready (no findings) |
| `feature-cockpit-typed-rpc-boundaries` | cockpit | ready (1 nit parked) |
| `feature-app-async-lifecycle-ownership` | app | needs fixes → 6 fixed → done |
| `feature-piext-lifecycle-delivery-promise-policy` | pi-extension | ready (no findings) |
| `feature-finish-generated-protocol-adoption` | pi-extension+relay+codegen | ready (no findings) |
| `feature-cockpit-async-action-ownership` | cockpit | needs fixes → 1 fixed → done |

## Topology (executed)

### Wave 1 (3 parallel — disjoint subprojects)
- W1 F1 retire-legacy-piext-composition-seams (sol/high) — 4 steps, owner-channel bridge
- W2 F5 cockpit-typed-rpc-boundaries (luna/high) — 2 steps, typed RPC value objects
- W3 F6 app-async-lifecycle-ownership (sol/xhigh) — 6 units, behavior-changing

### Wave 2 (3 parallel — after Wave 1 commits resolved write-set conflicts)
- W4 F2 piext-lifecycle-delivery-promise-policy (luna/high) — 3 steps, failure policy
- W5 F3 finish-generated-protocol-adoption (sol/high) — 5 steps, cross-stack codegen
- W6 F4 cockpit-async-action-ownership (sol/high) — 4 steps, ownAsync + close() contract

Feature reviews ran concurrently with Wave 2 implementation.

## Review weight

`standard` (default). One independent fresh-context review pass per feature
(gpt-5.6-sol), then adjudicate/fix/verify/close. No second pass after corrective
work. Two features needed corrective cycles (F6: 6 findings, F4: 1 blocker).

## Corrective cycles

### F6 (app) — 3 blockers + 3 material, all fixed
1. sendMessage stale-after-append (generation guards)
2. terminal idle reopened by older queued non-terminal projection (turn epoch)
3. mesh pull/rebase overwrites pending mutations (generation guards)
4. Sync stale-completion guards omit disposal/generation
5. router boot no production teardown + unguarded reset continuation
6. two timeout tests weakened (60ms→5s but waited 140ms) — restored to original deadline proofs

### F4 (cockpit) — 1 blocker, fixed
- Detached `_bootAgent` future not owned by `close()`: `createAgent()` did
  `unawaited(_bootAgent(...))`; closing a tab during startup I/O let boot resume
  and `notifyListeners()` on a disposed session. Fixed with close-aware `_closed`
  guards + memoized `close()` + boot guard after history I/O. Regression test
  proves closing during startup yields immediate removal + no post-close notify.

## Integration verification (final, all green)

- **pi-extension**: `tsc --noEmit` clean; 843/854 tests pass; 8 failures all =
  pre-existing read-only-`/tmp` env flakes (`cwd_lock.test.ts` mkdtemp EROFS +
  known `env-ext-test-cwd-lock-ordering-flake`). Not introduced by this work.
- **relay**: `cargo fmt --check` + `cargo clippy -- -D warnings` + `cargo test`
  all pass (183 tests).
- **cockpit**: `flutter analyze` clean; 250/250 tests pass.
- **app**: `flutter analyze lib test` clean; 739/739 tests pass (serial).
- **protocol codegen**: TS + Rust `--check` deterministic (no diff); 5 codegen
  unit tests pass.

## Epic eligibility

`epic-remote-session-resilience-refactor` (parent of F2 + F6) is NOT advanced —
4 of its 6 child features remain at `stage: drafting`. Correct per the
conservative lifecycle roll-up (epic advances only when ALL children terminal).

## Environment notes (for future sessions)

- `corepack pnpm` is broken on this VM (read-only COREPACK_HOME + deps-status
  RO-cache check). Use `./node_modules/.bin/tsc` / `vitest` directly.
- `/tmp` and `~/.pi/remote/locks/` are read-only → `cwd_lock.test.ts` (7 tests)
  + the extension.test.ts cwd-lock test fail. Pre-existing, documented in
  `.work/backlog/env-ext-test-cwd-lock-ordering-flake.md`. Not product bugs.
- `flutter analyze` shows ~228 pre-existing errors in
  `packages/outpost_pi_identity/test/` (sub-package dev-dep issue, NOT the app).
  Scope with `flutter analyze lib test`.
- App tests are scheduler-sensitive under the parallel runner; run
  `flutter test --concurrency=1` for reliable results.
- `flutter build macos` unavailable on Linux (no macOS toolchain).

## Retags

- `gate-cruft-empty-catch-formatter-reload` detached from F4 (behavior-changing:
  file_viewer.dart swallows _reloadFromDisk exceptions; logging/reporting
  changes the silent-fallback contract). Now `parent: null`, tags `[cockpit, bug]`,
  stage `drafting` — routes to feature/bug design.
- `room_meta_updated` outbound frame has no generated schema counterpart — left
  handwritten + documented in F3 as the one excluded schema gap. Schema
  definition + codegen adoption is a separate feature-design follow-up.

## Commits

52 commits (`8fe1a7e..HEAD`), unpushed. One commit per item transition + review
corrective commits. Working tree clean (one untracked session-note file).
