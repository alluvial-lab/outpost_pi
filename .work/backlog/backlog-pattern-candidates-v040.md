---
id: backlog-pattern-candidates-v040
created: 2026-08-11
updated: 2026-08-11
tags: [docs]
---

# Pattern candidates surfaced by v0.4.0 feature work

## Origin
gate-patterns (v0.4.0): 4 candidates. Meta; non-blocking.

## Candidates (author as pattern skills under .agents/skills/patterns/ if they meet the 3+ bar)
- PID-scoped marker-file handshake (index.ts:2711-2722/2744-2747/2853-2855/2875-2876, hot-reload.sh:118-129, pi-restart-loop.sh:57-72).
- Canonical timestamp capture and fan-out (index.ts:1350-1367/1375-1397, sync_service.dart:1108-1164/1171-1188/904-912, transcript_projection.dart:142-163).
- Turn-aware restart admission (index.ts:1511-1517/2847-2851, refresh-dist.sh:103-105, wrap-agents.sh:57-60, herdr-restart-agents.sh:103-105).
- Authoritative working-state convergence at lifecycle boundaries (composition_root.ts:112-120/140-149, index.ts:1947-1957).

## Note
P1 (marker handshake) and P2 (timestamp fan-out) overlap surfaces with in-flight/just-fixed work (restart-marker race, timestamp-ownership arc). Best documented after that work lands so the pattern reflects the corrected design.
