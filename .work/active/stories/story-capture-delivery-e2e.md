---
id: story-capture-delivery-e2e
kind: story
stage: implementing
tags: [app, pi-extension, e2e]
parent: feature-debug-capture-delivery
depends_on: ['story-capture-delivery-app-upload']
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Capture upload: live two-side e2e + triage compatibility

Live scenario (e2e-tagged + runner selector): harness-paired app triggers
"Send debug logs" with a synthetic ring planted on the device; assert the
file lands under the pi-host room cwd `debug/`, the ack path round-trips,
a delivered note is observable pi-side, and the pulled file parses clean
via `scripts/debug_capture_triage.py` (content-free). Requires the e2e
pi-host server to expose the room cwd (it already runs per-instance
E2E_PI_CWD). Device lane; hygiene protocol.
