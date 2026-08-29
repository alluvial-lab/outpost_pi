---
id: story-fix-new-wedge-bare-pi
kind: story
stage: implementing
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

The /new shutdown path has a branch for "no restart wrapper, no daemon"
that neither exits nor replaces the session in-process — it performs the
room teardown and stops. The exit-42 mechanism is gated on the wrapper
(`OUTPOST_PI_UNDER_RESTART_WRAPPER`) / daemon child; nothing backfills
the bare-launch case.

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
