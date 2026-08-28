---
id: release-v0.11.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# Release v0.11.0

Feature-lane minor cut (two-lane slicing). Per CONVENTIONS: six gates, FULL
e2e battery before publish (run-pairing.sh docker suite + live lanes +
600s seeded chaos soak), rc flow with operator UAT checkpoint, tag-based
mapping (local tag, operator pushes), retain-bodies.

## Bound items (12)

Direct (this batch):
- story-offline-state-liveness-ux
- story-pair-code-clipboard-copy
- feature-background-work-working-state
- story-background-work-ext-tracker
- story-background-work-app-surface
- story-fix-midstream-hydrate-reorder-flicker
- story-fix-stale-ime-watchdog-single-shot
- story-cleanup-ext-sdk084-compat-batch
- story-cleanup-app-flutter347-deprecations

Pre-session unbound stragglers (code shipped in v0.10.x APKs; substrate
first-bound here):
- story-fix-app-stale-ime-inset
- story-mobile-extension-command-invocation
- story-system-status-events-in-agent-turn-stream

## Gate runs
(populated as gates run)
