---
id: idea-soak-post-quiescence-working-stuck
created: 2026-08-24
updated: 2026-08-24
tags: [app, bug]
---

A 300-second live soak (`seed=2026082407`) completed its scheduled reconnect faults with zero outside-window churn clusters and clean replay/projection/identity oracles, but the harness timed out after 30 seconds waiting for `working=false` during post-soak quiescence. The failure followed the `multi_session_round_trip` state shape and a late airplane-mode window; the capture recorded 7 `workingConv` events and the final visible state did not converge idle.

Evidence is local-only under `.work/session-notes/live-soak-20260824T161455Z-2026082407/` (`report.md`, `findings.json`, and the debug JSONL capture). This was adjacent to the reconnect-hedge fix rather than part of its auth/cancellation scope.
