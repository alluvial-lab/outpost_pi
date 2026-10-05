---
id: backlog-bounded-diagnostic-hashing
created: 2026-10-05
updated: 2026-10-05
tags: [pi-extension, relay, docs]
---

# Bounded, cross-endpoint-correct diagnostic hashing

Inbound frame-hash instrumentation must bound work before allocating/hashing full payloads, and the paired frame-hash comparison needs a shared known-answer oracle across endpoints so the safety change cannot silently weaken the comparison contract. Folded from one gate-security + one gate-tests finding that need each other.

Consolidated 2026-10-05 by operator-confirmed groom merge from: gate-tests-frame-hash-shared-known-answers, gate-security-bound-inbound-hash-work.
Scope-promote via /agile-workflow:scope when wanted.
