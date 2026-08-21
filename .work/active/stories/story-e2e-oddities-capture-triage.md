---
id: story-e2e-oddities-capture-triage
kind: story
stage: done
tags: [app, testing]
parent: feature-e2e-live-oddities-suite
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Capture-first: decode/triage tooling for the debug-capture rings

The operator already produces the evidence (`debug/*.bin` NDJSON rings); this
story makes it actionable and extends the ring where the parked findings
need visibility. Test-integrity rules apply: park production bugs, never
weaken assertions; no gaming.

## Units

### Unit 1: `scripts/debug_capture_triage.py`
Decode + summarize a capture ring: tag counts, sessionTimeline view
(connStatus/channelLost/hydrate/workingConv interleaved), msgSend↔msgEcho
correlation (flags sends without echoes), lifecycleFailure attribution
grouping, anomaly heuristics (the swallow signature: `blocked:true` with no
subsequent row/echo; blank-chat signature: sessionGate open without
roomSnapshot content events). Python per repo script precedent
(generate-brand-assets.py). Deterministic output; exit code reflects
detected anomalies (CI-able).

### Unit 2: ring-tag additions (app)
- `sendQueue` events: held → visible-fail → resend outcomes per message id
  (today only the terminal msgSend is recorded; the held path's 20s timeout
  and reconnect resend are invisible).
- `route` events: session-route entry + projection ready/empty after hydrate
  (blank-chat signature becomes detectable).
- `reconnectAttribution`: ensure every connChannelLost carries a cause field
  (observability arc) — triage groups by it.

## Acceptance criteria
- [x] `debug_capture_triage.py debug/cad-11f1-b349-a5efddf14d8d.bin` reports
      the swallow (msgSend blocked, no echo) and the churn stats (89 timeouts)
      the manual analysis found — encoded as the tool's regression test.
- [x] New tags present in the debug contract enum + implementation + unit
      tests (ring stays content-free per the diagnostic-categories pattern).
- [x] `flutter analyze` + affected unit tests green.

## Implementation

- Unit 1: added `scripts/debug_capture_triage.py` with deterministic summary and
  interleaved timeline modes, send/echo correlation, blocked-send swallow and
  channel-loss churn heuristics, lifecycle attribution grouping, and CI exit
  status. Added the minimal checked-in regression slice at
  `scripts/fixtures/debug_capture_triage/cad-11f1-b349-a5efddf14d8d.bin`.
- Unit 2: added content-free `sendQueue` and `route` debug events, wired held,
  visible-fail, resend outcome, route entry, and hydrate projection capture;
  added closed `reconnectAttribution` causes to `connChannelLost`; expanded
  routing and JSON-shape tests.
- Unit 3: included `sendQueue` and `route` in the triage timeline and field
  rendering.
- Evidence: `flutter analyze` passed; `flutter test --exclude-tags e2e`
  passed (`882` tests); `python3 scripts/debug_capture_triage.py --selftest`
  passed with known swallow, `89 retryConnect/TimeoutException` failures, and
  churn-cluster checks.
