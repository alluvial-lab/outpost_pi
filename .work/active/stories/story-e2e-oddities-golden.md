---
id: story-e2e-oddities-golden
kind: story
stage: implementing
tags: [app, testing]
parent: feature-e2e-live-oddities-suite
depends_on: [story-e2e-oddities-harness-infra]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Golden-path device tests: pair → chat → persist → cold-open render

Invariants 2 (session always renders) and the delivery happy path, on the
real UI. Test-integrity rules apply: assert user-visible outcomes (widget
state, transcript DB, capture ring), never internal call traces.

## Units

### Unit 1: `app/integration_test/live_golden_test.dart` (e2e-tagged)
1. **Pair→chat→reply**: pair via QR bridge → send message → pi-host
   `/turn-control` staged reply → assert the assistant bubble renders and
   `working` converged false.
2. **Cold-open render**: restart the app process (adb), navigate directly
   into the existing session route → assert history renders after hydrate
   (bounded wait on projection content, not wall-clock).
3. **Mid-conversation reconnect**: `net_fault timeout 8000` → clear → assert
   chat continues without user action; room selection intact.

## Acceptance criteria
- [ ] 3 golden tests green via `e2e/run-live.sh` on the VM, twice
      consecutively (stability gate).
- [ ] Assertions reference rendered bubbles/DB rows/capture events only.
- [ ] `flutter analyze` clean; tests excluded from the default suite (e2e
      tag) per existing convention.
