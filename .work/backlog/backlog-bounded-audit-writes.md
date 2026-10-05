---
id: backlog-bounded-audit-writes
created: 2026-10-05
updated: 2026-10-05
tags: [relay, pi-extension, docs]
---

# Bounded and deterministically testable audit writes

Audit writes need a shared write-completion boundary: count/byte ceiling with blocked-write/sustained-ingress tests, and an explicit audit-flush/barrier seam that removes sleep-based rotation assertions. Folded from the broker memory-ceiling and rotation-flake pair.

Consolidated 2026-10-05 by operator-confirmed groom merge from: backlog-broker-audit-write-memory-ceiling, backlog-ext-audit-rotation-load-flake.
Scope-promote via /agile-workflow:scope when wanted.
