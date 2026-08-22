---
id: story-e2e-chaos-clock-version-skew
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

# Clock skew + version-skew drills

Exploratory: libfaketime on relay/pi-host containers (auth TTL, heartbeat, watermark logic under skew); version-skew drill = run relay at previous tag vs current extension (paired-wire-cut class). Bounce-allowed if container constraints block faketime — land findings. Acceptance: at least one skew dimension exercised with invariants held or oddities parked; blockers documented.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
