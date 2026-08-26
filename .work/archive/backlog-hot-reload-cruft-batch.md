---
id: backlog-hot-reload-cruft-batch
created: 2026-08-11
updated: 2026-08-26
tags: [pi-extension]
status: folded
folded_into: feature-cruft-consolidated-cleanup (groom 2026-08-26)
---

# Hot-reload cruft + expiry-test batch

## Origin
gate-cruft C1, gate-tests T5 (v0.4.0).

## Findings
- index.ts:2671-2673, 2683-2685 — _hotReloadEnabledPath() and _runtimeIdentityPath() have no call sites (paths are constructed inline). Remove both private helpers.
- index.ts:2842-2847 — armed-request 5-minute expiry is untested (the protection against crash residue unexpectedly restarting a later settled process). Use a fake clock with a valid nonce just below and just above the boundary; assert no claim, marker, quiescing, or SIGTERM when expired, and stale-file cleanup.
