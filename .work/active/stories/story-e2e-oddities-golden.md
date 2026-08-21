---
id: story-e2e-oddities-golden
kind: story
stage: done
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
- [x] 3 golden tests green via `e2e/run-live.sh` on the VM, twice
      consecutively (stability gate).
- [x] Assertions reference rendered bubbles/DB rows/capture events only.
- [x] `flutter analyze` clean; tests excluded from the default suite (e2e
      tag) per existing convention.

## Implementation

- Execution capability: `sol/high` — real-device lifecycle regressions across app, relay, and pi-host support.
- Review weight: standard (project default); review is not applicable to this child-story checkpoint.
- Added `app/integration_test/live_golden_test.dart` and a shared live-device harness that uses the production scanner, owner-channel transport, Hive transcript projection, chat widgets, and bounded observable probes.
- Invariant mapping: pair/chat asserts rendered user+assistant bubbles, an assistant DB row, and rendered working convergence; cold-open runs in a distinct Flutter instrumentation process separated by adb `force-stop` and asserts persisted bubbles plus a `route/projection-ready` capture; timeout recovery asserts the selected room survives and a post-reconnect turn renders.
- Extended pi-host turn control to stage a deterministic assistant message and bracket it with the production agent lifecycle, allowing device tests to observe true `working` convergence without a model mock.
- Extended `e2e/run-live.sh` with an `integration_test/*.dart` selector, generic allow-listed fault-marker driving, and `--no-uninstall` multi-process golden phases so app data survives the explicit adb process boundary. The no-argument smoke default remains unchanged.
- Files changed: `app/integration_test/live_golden_test.dart`, `app/integration_test/support/live_device_harness.dart`, `e2e/run-live.sh`, `pi-extension/test/support/e2e_pi_host_server.ts`, `pi-extension/test/support/e2e_pi_host_runtime.ts`, and this item.
- Tests added: three e2e-tagged real-device scenarios protecting delivery/rendering, cold-open hydration, and reconnect convergence.
- Simplification: one shared harness and one marker-driven runner replace per-scenario shell choreography; no production behavior or protocol changed.
- Discrepancies from design: none.
- Adjacent issues parked: none.

Verification (2026-08-21):

```text
# consecutive run 1 tail
OUTPOST_LIVE_FAULT_REQUEST net_clear
[live] applied net_clear
00:14 +1 ~2: All tests passed!
live device e2e passed: integration_test/live_golden_test.dart + capture

# consecutive run 2 tail
OUTPOST_LIVE_FAULT_REQUEST net_clear
[live] applied net_clear
00:14 +1 ~2: All tests passed!
live device e2e passed: integration_test/live_golden_test.dart + capture

flutter analyze
No issues found!
```
