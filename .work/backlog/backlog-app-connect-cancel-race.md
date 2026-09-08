---
id: backlog-app-connect-cancel-race
created: 2026-09-08
updated: 2026-09-08
tags: [app, bug, lifecycle]
---

# Connect-cancel race: retried connects cancelled client-side during recovery

Metronome-watch capture 2026-09-08: after a strike, 3 of 4 connect attempts
were cancelled before reaching the wire (`_CancelledError`, zero relay auth
attempts), extending a ~2s outage to 2.5 min. Static analysis bounded the
canceller to a re-entrant `_connect()` / supervisor invalidation with a
diverged target (leading candidate: post-strike `_markActiveRoomOffline`
retarget churn); precise attribution needs cancellation-site logging (see
story-fix-connection-metronome-death cancel-race addendum). Fix likely:
stabilize the retry target across the recovery window or make same-peer
re-entrant connects join the in-flight attempt instead of cancelling it.
