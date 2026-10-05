---
id: backlog-soak-maintained-bubble-render-assert
created: 2026-10-05
updated: 2026-10-05
tags: [app, bug, testing]
---

# Soak maintained-bubble render assertion fails (pre-existing at v0.12.1)

The 600s seeded chaos soak fails at `_assertEveryMaintainedBubbleRenders`
(harness: scrollUntilVisible → `Bad state: No element` hunting a maintained
message bubble), late-stage (~8:50 into the run), reproducible 2/2 at HEAD
and — bisected — **identically at v0.12.1** (worktree, same seed, 16
checkpoints). NOT a v0.13.0 bundle regression: last full battery ran at
v0.12.0; v0.12.1 was a patch cut (pairing-lane-only battery) so the failure
window predates this release without being surfaced.

What PASSES on both trees (evidence in the soak reports): all chaos oracle
invariants (replay_dedup, transcript_projection, ordering, identity), zero
swallowed sends, zero blank-chat signatures; only the UI-visibility assert
fails. Suspect classes: chat-list virtualization/windowing under chaos
faults (bubble exists in model, not found in the widget tree while
scrolling), or an emulator-render timing drift since the v0.12.0 battery.

Diagnosis lane when picked up: rerun with the bubble's model-state asserted
alongside the widget hunt (separates "not rendered" from "not reachable by
scroll"); if model-present/widget-absent → windowing bug; if both absent →
harness finder/timing. Logs: /tmp/soak-v1310.log, /tmp/soak-v1310b.log,
/tmp/soak-v0121c.log.
