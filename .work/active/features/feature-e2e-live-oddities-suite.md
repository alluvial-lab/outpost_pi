---
id: feature-e2e-live-oddities-suite
kind: feature
stage: drafting
tags: [app, pi-extension, relay, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# E2E suite for live-use transient oddities (capture-first + chaos/soak)

Operator commissioning (2026-08-21): transient oddities during live app use
are hard to pin down "with a log every time." Seed fault model — three
operator-reported oddities, one already evidence-confirmed:

1. **Swallowed message** — CONFIRMED from capture `cad-11f1-b349`:
   `sendMessage` silently drops on missing session identity
   (`story-app-send-swallowed-session-identity-unavailable`). Post-reconnect
   window is the trigger.
2. **Blank chat on direct open into a session** —
   `backlog-app-blank-chat-direct-open` (hydrate→projection race family).
3. **Random disconnects/reconnects in-chat** —
   `backlog-app-reconnect-churn-timeout-lifecycle-failures` (89 timeouts /
   46 channel-lost in 4 days).

## Strategy (two layers)

- **Capture-first**: the debug-capture seam already exists and the operator
  already produces captures (`debug/*.bin` = plain NDJSON ring, 1MiB). Gap:
  decode tooling + a triage loop (capture → decoded sequence → parked
  finding). Every oddity becomes a replayable sequence instead of a vibe.
  Candidate additions: ring tags for send-queue state and route/hydrate
  sequencing; one-tap diagnostics export (already partially exists?).
- **Chaos/soak harness**: emulator app + local relay + extension with
  scripted fault injection (airplane-mode via adb, relay restarts, app
  backgrounding mid-turn, sends during the post-reconnect window) asserting
  the invariants the harvest arc hardened: working converges false, room
  selection survives reconnect, no silent message loss, chat never blank
  after hydrate. Builds on: docker-compose pairing e2e (e2e/run-pairing.sh),
  the new emulator loop (AVD outpost34 + emulator-scanner-smoke.sh pattern),
  and the CI app-e2e lane.

## Design gate

This feature is at drafting for `e2e-test-design`: design the coverage
(golden-path / failure-mode / chaos partition), then decompose into child
stories. The three seed oddities define the initial failure-mode classes;
each captured/confirmed defect adds a regression scenario to the suite.
