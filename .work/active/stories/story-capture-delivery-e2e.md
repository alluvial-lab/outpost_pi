---
id: story-capture-delivery-e2e
kind: story
stage: done
tags: [app, pi-extension, e2e]
parent: feature-debug-capture-delivery
depends_on: ['story-capture-delivery-app-upload']
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-25
---

# Capture upload: live two-side e2e + triage compatibility

Live scenario (e2e-tagged + runner selector): harness-paired app triggers
"Send debug logs" with a synthetic ring planted on the device; assert the
file lands under the pi-host room cwd `debug/`, the ack path round-trips,
a delivered note is observable pi-side, and the pulled file parses clean
via `scripts/debug_capture_triage.py` (content-free). Requires the e2e
pi-host server to expose the room cwd (it already runs per-instance
E2E_PI_CWD). Device lane; hygiene protocol.

## Implementation

- Added the `capture-delivery` live-runner selector and an e2e-tagged Android
  scenario that pairs through the production QR/secure-channel flow, plants a
  content-free device capture, taps the real `Send debug logs` row, and waits
  for delivered UI state.
- Added a bounded pi-host evidence endpoint for its latest committed capture;
  the scenario asserts the path is under the per-instance `E2E_PI_CWD/debug/`,
  validates the returned JSONL, and observes the
  `outpost-pi:debug-capture-delivered` TUI/session note.
- The runner pulls the committed bytes after the device test and runs
  `scripts/debug_capture_triage.py`; the capture parsed with 2 rows and zero
  anomalies.
- Verification: `e2e/run-live.sh capture-delivery` passed. Hygiene completed:
  `emulator-5554` down, `app/build` removed, 183 GiB free.
