---
id: story-e2e-chaos-mesh-lane
kind: story
stage: implementing
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: story-e2e-chaos-fault-vocabulary
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Mesh lane: second Pi, cross-Pi delivery

Compose: second pi-host instance (distinct identity/cwd); harness pairing to both. Scenarios: Pi→Pi mesh message delivery (device-visibility), mesh ingress during run (queueing fix device-level), one-Pi fault isolation. Acceptance: mesh scenarios green on device lane; adapter extensions test-support only.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
