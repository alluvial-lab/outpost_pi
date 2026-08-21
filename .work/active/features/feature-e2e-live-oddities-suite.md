---
id: feature-e2e-live-oddities-suite
kind: feature
stage: implementing
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

## Design decisions (2026-08-21, operator dials pinned in commissioning)

- **Full stack, all real**: relay (source-built image) + extension (existing
  `pi-host` HTTP-controlled adapter) + **app as real UI on the outpost34
  emulator** — the oddities are UI-lifecycle-shaped (cold open, backgrounding),
  which the existing Dart in-process lane cannot express. No new mocks.
- **Toxiproxy 2.12.0 (already in the compose stack)** is the network-fault
  primitive; adb connectivity toggles + `docker pause` + `/__restart` cover the
  rest. No Pumba needed — real component control exists.
- **QR is the relay-config vector**: the app learns relay host:port from the
  pair payload; the harness pairs the emulator app via `analyzeImage` on a QR
  built from pi-host `/pair-code` (scanner-boundary pattern). Verify in infra.
- **Device↔compose networking via `adb reverse`** (device localhost → host
  published port).
- **Known-open bugs land as `xfail`-linked tests** (integrity rule): the
  swallow/blank-chat scenarios assert the CORRECT behavior, marked
  skip/xfail citing the tracking id, flipped when the fix story lands.
- **Capture-first is a sibling story, not a prerequisite** of infra; chaos
  depends on it (soak asserts via the capture ring).
- **Fuzz: not applicable** — wire decoders are unit-covered with
  cross-language fixture triangulation; QR parsing unit-covered; no new
  parser surface in this scope.
- CI promotion of the device lane = follow-on (local-first; app-e2e lane
  extension once stable).

## Mock-boundary plan

| component | boundary | notes |
|---|---|---|
| relay | REAL (compose, source build) | existing |
| extension | REAL (pi-host adapter; /pair-code /command /turn-control /__restart) | existing |
| app | REAL UI on emulator (outpost34) | new device lane |
| network | Toxiproxy 2.12.0 (timeout/slicer/down) | existing |
| new custom containers | none | strongest boundary: the harness IS the product |

## Taxonomy plan

- **Golden (3)**: pair→send→seeded-reply→transcript persists; cold app start
  directly into session route renders history; mid-conversation reconnect
  recovers without user action.
- **Failure (5)**: send during post-reconnect identity window (*xfail →
  story-app-send-swallowed-session-identity-unavailable*); cold-open blank
  chat (*xfail → backlog-app-blank-chat-direct-open*); offline send →
  held→visible-fail→resend-on-reconnect; pair attempt with relay down;
  extension `/__restart` mid-conversation → recovery + no message loss.
- **Chaos (1 soak)**: randomized fault schedule (toxiproxy classes, relay
  pause, pi-host restart, app background/airplane), N-minute soak asserting
  the four invariants below from the capture ring + transcript DB.
- **Fuzz**: N/A (justified above).

## Invariants (plain English — every test maps to one)

1. A message the user sent is always visible (delivered, pending, or visibly
   failed) — never silently absent.
2. Opening the app into an existing session chat always renders that
   session's history (possibly after hydrate; never blank without a retry).
3. After any fault/reconnect sequence, `working` converges to the room's
   true state and room selection survives.
4. Reconnect churn is attributed (every connChannelLost has a cause in the
   capture ring).

## Implementation Order
1. story-e2e-oddities-capture-triage (no deps)
2. story-e2e-oddities-harness-infra (no deps)
3. story-e2e-oddities-golden (infra)
4. story-e2e-oddities-failure (infra)
5. story-e2e-oddities-chaos (golden + failure + capture-triage)

## Risks (pre-mortem)

- Emulator+compose on one VM: memory — cap Gradle, reuse outpost34, serial
  runs only (fleet idle required for soak).
- Swiftshader timing flakiness: assert on capture-ring/DB state, never
  wall-clock; retries at the driver level with bounded attempts.
- QR-as-config assumption could be wrong (app might discover relay another
  way) — infra story verifies first; fallback = settings-injectable URL.
- pi-host control gaps discovered mid-build → extend the adapter server
  (it is test support; additive endpoints are in-scope for infra).
