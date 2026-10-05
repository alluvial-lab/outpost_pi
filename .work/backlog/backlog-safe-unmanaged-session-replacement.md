---
id: backlog-safe-unmanaged-session-replacement
created: 2026-10-05
updated: 2026-10-05
tags: [pi-extension, bug, lifecycle]
---

# Safe unmanaged session replacement

Unmanaged (/new against bare pi) session replacement should either complete through a fresh in-process command capability or reject before any destructive teardown — never fail-closed-exit as the silent UX. Carries the parked story-new-wedge-bare-pi-reopen residue: live rebind-branch gap investigation + settle-emit exception isolation. Folded from the parked story + gate-security finding.

Consolidated 2026-10-05 by operator-confirmed groom merge from: story-new-wedge-bare-pi-reopen, gate-security-unmanaged-session-new-process-exit.
Scope-promote via /agile-workflow:scope when wanted.
