---
id: story-new-wedge-bare-pi-reopen
created: 2026-08-29
updated: 2026-10-04
tags: [pi-extension, bug, lifecycle]
---

# Bare-pi /new reopened: live rebind-branch gap + settle-emit isolation

## Parked status (2026-10-04, hygiene pass)

Substantive fixes landed and live-verified 2026-09-07 (wrapper-path wedge
dead; background-work SIGTERM protection both halves). Residual scope when
revived for a fix lane — two investigation threads:

1. **Bare-pi rebind-branch gap** — live /new on a bare pi takes the
   fail-closed exit instead of the in-process rebind (Test B below):
   inspect live `session_new` entry conditions (which ctx binding exists
   when /new arrives through the delivery path on a settled bare session)
   vs the real-SDK harness test that exercises that branch.
2. **Settle-emit exception isolation** — does pi's runner abort remaining
   handlers when a third-party extension throws inside `agent_settled`,
   and should in-process /new recovery be exception-isolated so one
   extension cannot wedge the room re-serve? (herdr-side stale-ctx guards
   already fixed locally.)

## Post-release finding (2026-09-07, operator field report)

The v0.11.1 in-process /new path (agent-workspace incident): session
replacement INITIATED, but a third-party extension (herdr-agent-state.ts,
stale ctx after replacement) threw inside the agent_settled emit, and the
post-replacement recovery did not complete — the operator had to restart
the session manually at the workstation. Two layers:
1. herdr-agent-state.ts — FIXED locally (stale-ctx guards on both isIdle
   call sites; rebinds on next agent_start).
2. Open question for the extension's replacement path: resilience to a
   THROWING third-party extension during the settle emit — does pi's
   runner abort remaining handlers, and should the in-process /new
   recovery be exception-isolated so one extension cannot wedge the
   room re-serve? Park for the next fix lane; verify empirically: a
   /new against a pi with the patched extension should now complete
   cleanly (room re-serves, no manual restart needed).

## Sibling incident (2026-09-07): wrap-agents.sh killed background work

The fleet-wrap SIGTERM'd a pi whose turn had ended but whose background
subagents were still running — herdr's agent_status (turn-derived) read
"idle". pi-subagents are in-process: the work died with the pi.

Fix (both halves, landed):
1. outpost extension: BackgroundActivityTracker re-broadcasts transition
   edges on the pi event bus as `outpost-pi:background` {active}
   (content-free; parallel identity-deduped emission list — WeakSet
   guards subscribe idempotence but is not iterable).
2. herdr-agent-state.ts (local ~/.pi/agent/extensions/): subscribes;
   while background work runs (no active turn) it publishes state
   "working" + message "background work" — herdr UI + wrap-agents.sh
   defer instead of SIGTERM.
Verification: extension 1,121 tests + build green. Loaded by pis at
next process start.

## Verification results (2026-09-07, live)

- **Test A (wrapper path)**: PASS — /new from phone on skills (room
  k0H-7lFh371e): fence/drain (background field visibly drained), exit,
  wrapper relaunch in 2.3s, re-auth, room serving. The original wedge is
  dead in the standard configuration.
- **Test B (bare in-process path)**: CONTRACT-HELD, BRANCH-MISSED — bare
  pi (pi --continue, no wrapper) + mobile /new: the pi took the
  FAIL-CLOSED EXIT (clean, no wedge, no error surfaced) instead of the
  in-process rebind. The invariant held; the desired UX did not: bare
  pis still lose the session, politely. Follow-up: why did the live
  trigger lack a command-capable context when the real-SDK harness test
  exercises exactly that branch — inspect the live session_new entry
  conditions (which ctx binding exists when /new arrives through the
  delivery path on a settled bare session) vs the harness's.
