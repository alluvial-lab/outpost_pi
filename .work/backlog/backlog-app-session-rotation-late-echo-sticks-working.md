---
id: backlog-app-session-rotation-late-echo-sticks-working
created: 2026-08-22
updated: 2026-08-22
tags: [app, bug]
---

Promoted to `story-fix-app-session-rotation-late-echo-sticks-working`.

# Late echo after session rotation makes a completed room look working again

The live state-shape lane reproduced a sticky working projection after an
A→B session rotation under bounded bandwidth. Session B completed and the
canonical room snapshot published `working=false`, but a later duplicate user
`msgEcho` caused the app's `mark_room_working` backstop to set the same room
true again. No later false event arrived, leaving the production chat on
`working…` until the 30-second assertion timed out.

Evidence is in the local capture bundle
`.work/session-notes/live-state-shapes-20260822/`: `report.md`,
`outpost_pi_debug-20260822T180310Z.jsonl`, and `triage.txt`. The decisive order
is roomSnapshot false at `18:02:38.642582Z`, msgEcho at
`18:02:38.703782Z`, then workingConv true (`mark_room_working`) at
`18:02:38.704382Z` with no following false convergence.

## Work

Make the app's active-room working backstop monotonic against authoritative
turn completion for the current session. A late/duplicate user echo must not
re-open working after a newer room snapshot or terminal turn event has closed
it. Keep the multi-session A→B→A live assertion unchanged and flip its linked
skip when fixed.
