---
id: gate-tests-peer-recovery-and-barrier-hardening
created: 2026-11-20
updated: 2026-11-20
tags: [pi-extension, workflow]
---

# Add SessionPeer degraded-startup / NACK-probe coverage and replace fixed-sleep barriers

Parked from `v0.14.0` release-gate `tests` / `patterns` scan (medium/low, non-blocking).

## Evidence pointers

- `pi-extension/src/session/peer.ts:140-151, 263-273` (`start()` degraded fallback + `_scheduleRejoinRetry()` recovery and `leave()` timer cancellation) and `pi-extension/src/session/peer.ts:570, 745-754` (`_maybeProbeAfterNack()` coalescing & fast-path split heal on `unknown_peer`) lack direct unit tests.
- `pi-extension/src/session/broker_invalid_envelope.test.ts:114` uses `await delay(50)` instead of a bounded polling barrier (`until(...)`) before reading `audit.jsonl`.
- `pi-extension/src/session/generation_convergence.test.ts:194, 212, 237` uses fixed wall-clock sleeps (`wait(300/400/500)`) without asserting probe invocation counts.
- `pi-extension/src/session/broker.ts:665-671` cross-PC un-bridged `unknown_peer` exclusion is untested (`broker_generation.test.ts:72-83` only covers local `"ghost"`).
- Refresh 4 drifted line anchors in `.agents/skills/patterns/{subscription-unsubscribe-contract,content-free-diagnostic-categories,evidence-local-failure-classification,frame-byte-bounded-admission}.md`.
