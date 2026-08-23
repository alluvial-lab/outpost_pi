---
id: idea-soak-compound-recovery-no-peer
created: 2026-08-23
updated: 2026-08-23
tags: [app, bug]
---

Seed `20260828` progressed past the repaired rendered-bubble oracle but timed out
recovering from the scheduled `net_compound slicer=6905 timeout=5622
bandwidth=243` window at 278s. `LiveDeviceHarness.waitOnlineAndLive` observed
`StatusNoPeer` with the selected/active room still present but `session=null`.
All completed checkpoints kept replay dedup, DB↔ViewModel projection, rendered
bubble traversal, canonical ordering, working-state observations, and owner/pair
identity clean; all churn was inside scheduled fault windows.

Evidence: `.work/session-notes/live-soak-20260823T231732Z-20260828/report.md` and
its `flutter-live-all.log` / debug capture. This is outside the backfill-anchor
fix lane and was not chased inline.
