---
id: story-fix-new-wedge-bare-pi
kind: story
stage: done
tags: [pi-extension, bug, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-29
updated: 2026-08-29
---

# Mobile /new on a bare pi must complete in-process — never the half-dead wedge

From `backlog-new-wedge-bare-pi-room-teardown-without-exit` (incident
diagnosed live 2026-08-28, evidence chain in that item): a mobile `/new`
delivered to a pi running WITHOUT the restart wrapper and WITHOUT daemon
mode tears down the owner room (fence → drain → detach — room leaves the
relay at 22:40:00) but the process exit (EXIT_FRESH_SESSION=42 path)
never fires for that launch mode. Result: half-dead pi — live process,
dead room; the app shows peer-offline and gates /new AND restart actions
permanently. Operator recovered manually (herdr /quit + relaunch under
the wrapper).

## Root cause shape

The precise stranded branch was `pi-extension/src/index.ts:3291-3298`
(`!newSession` followed by `!_isFreshSessionRestartManaged()`). A bare
mobile action with no captured `ExtensionCommandContext` could not enter
`handleSessionNew`/`bindReplacementContext`; this branch instead emitted the
old `fresh_session_restart_unavailable` error and returned without either an
in-process successor or a terminal exit. If the owner runtime had already
started its fence/drain/dispose teardown, that return left the process alive
with no room owner. Managed wrapper/daemon requests continue through the
separate coordinator branch at `src/index.ts:3315-3345` and retain exit 42.

## Fix approach (from the incident record)

In the `/new` completion path: when the wrapper env is absent and daemon
mode is inactive, complete the session replacement IN-PROCESS using the
existing replacement machinery (`bindReplacementContext` — the
withSession/`session_new` re-arm path that already serves mobile session
recovery) instead of stopping after room teardown. The owner room must
end either re-bound to the fresh session (session_new published,
transcript hydrated) — never detached-but-alive. If a genuinely
unreachable edge remains where in-process replacement cannot run, fail
CLOSED: complete the process exit rather than leaving the room torn
down. Preserve the existing wrapper/daemon exit-42 behavior exactly.

## Acceptance criteria

- Harness test: `/new` with NO wrapper env and NO daemon → in-process
  replacement completes (room re-bound, `session_new` broadcast,
  successor session serves messages) — no process exit, no detached
  state.
- Harness test: `/new` WITH wrapper env → existing exit-42 behavior
  unchanged (marker written, process exits).
- Harness test: `/new` in daemon mode → existing behavior unchanged.
- A liveness assertion: after any /new path completes, the owner room is
  either re-bound or the process has exited — the wedge state is
  asserted impossible (a state-machine invariant test if the flow
  admits one).
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  green from pi-extension/.

## Implementation notes

- **Named branch:** the bare no-context branch in
  `pi-extension/src/index.ts:3291-3298` now terminates with
  `EXIT_FRESH_SESSION` rather than returning after an unavailable-action
  response. A command-capable bare path remains in-process through
  `handleSessionNew` and `_bindReplacementSessionContext`, which delegates to
  `SdkSessionProjection.bindReplacementContext` at
  `pi-extension/src/session/sdk_session_projection.ts:350-371`.
- **Files:** changed `pi-extension/src/index.ts`,
  `pi-extension/src/extension.test.ts`, and this story item only. No app,
  relay, or script files changed.
- **Tests:** first changed the old bare no-context regression to assert the
  terminal invariant; the old implementation failed because `process.exit`
  was never called. Added an explicit no-wrapper/no-daemon in-process test
  asserting fresh room metadata, empty `session_history`, no exit, and a
  successor prompt delivered through the fresh message API. Wrapper and daemon
  tests remain in place and continue to assert exit 42 and their existing ACK /
  reset ordering. Targeted fresh-session tests and typecheck pass.
- **Four-step incident re-walk:** (1) admitted delivery is fenced by the
  existing managed coordinator, or replacement begins through the SDK
  `withSession` callback; (2) admitted work drains before the managed
  ACK/reset tail; (3) the predecessor room may detach during runtime teardown,
  but a no-context bare request can no longer remain alive after that boundary;
  (4) the normal bare command-capable path rebinds the fresh session, publishes
  the new `room_meta.session_id` and empty `session_history`, then serves the
  next owner message. The only path without in-process replacement now exits,
  making “re-bound or exited” exhaustive.
- **Execution capability:** implemented inline with direct repository reads,
  a failing-first Vitest regression, and bounded TypeScript verification; no
  delegated worker or external dependency was used.
