---
id: backlog-broker-audit-write-memory-ceiling
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, security]
---

# Broker audit-write serialization has no in-memory ceiling

## Origin
gate-security-regression SR2 (Medium, hardening-introduced), v0.4.0.

## Location
pi-extension/src/session/broker.ts:198, 278-280, 589-601.

## Issue
Each incoming UDS line dispatches without awaiting the prior handler, while _appendAudit chains every filesystem op onto auditWrite. No pending-write count or byte ceiling. A local mesh participant can submit records faster than the stat/rotation/append sequence completes, so promises and their captured audit lines accumulate without bound despite the disk cap.

## Work
Bound queued audit records/bytes and drop or coalesce diagnostics at capacity, or apply socket backpressure while preserving message routing. Test with blocked filesystem writes and sustained ingress.
