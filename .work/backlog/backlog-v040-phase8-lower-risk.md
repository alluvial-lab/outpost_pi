---
id: backlog-v040-phase8-lower-risk
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, lifecycle]
---

# v0.4.0 Phase 8 lower-risk findings (parked)

## Origin
Phase 8 completion review (v0.4.0), parked per standard-weight policy.

## Findings
- Marker delete-during-handoff race: startup sweeping (pi-extension/src/index.ts:2645-2666) removes .restart-marker-<PID> as soon as that PID is dead — exactly the interval in which its wrapper needs to consume it (scripts/pi-restart-loop.sh:90-100). Narrow multi-process race despite the "foreign markers untouched" contract. Exclude restart markers from the generic dead-PID sweep or add a safe expiry/ownership handshake.
- Oversized-log regression test relies on fixed 40 ms sleeps (pi-extension/src/session/e2e.test.ts:490-500); audit writes are detached, so the sleep doesn't deterministically establish setup or post-append completion under load — test can flake. Add an explicit audit-flush/barrier seam.
