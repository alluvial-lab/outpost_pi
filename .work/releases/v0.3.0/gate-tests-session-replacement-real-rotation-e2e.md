---
id: gate-tests-session-replacement-real-rotation-e2e
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# Session-replacement E2E does not create a replacement session or reproduce the deferred-turn condition

## Priority
High

## Value evidence
Item: `story-e2e-session-replacement-case`. Standing regression for the replacement-context full-turn Promise defect. The story's own record admits the harness does not rotate SessionManager and instant turns make the timing bug unobservable; the test uses a five-second sleep to look for duplicates (`app/test/e2e/session_replacement_e2e_test.dart:146-157`). The deterministic extension regression protects local ordering (`pi-extension/src/extension.test.ts:2291-2306`), but the promised app↔extension replacement seam is not exercised under production-like conditions.

## Gap type
e2e-seam

## Suggested test
```dart
test("real replacement confirms cli id before replacement turn settles", () async {
  // Make the Pi-host rotate to a distinct session ID and expose a deferred
  // replacement sendUserMessage settlement.
  // Send the first message after session_new.
  // Before resolving the turn, assert the app receives the original cli_ ID,
  // the pending timer is disarmed, and no sync_ echo or failure row appears.
  // Resolve the turn and assert exactly one transcript row without sleeping.
});
```

## Test location (suggested)
`app/test/e2e/session_replacement_e2e_test.dart`

## Implementation discovery

The expanded write scope supplied the missing harness boundary. The Pi host now rotates to a fresh SDK `SessionManager` on `session_new`, rebinds its runner/actions to that manager, emits `session_start` with the replacement identity, and supplies the extension's `withSession` callback a fresh command/message context. Content-free HTTP controls arm, observe, and resolve the next SDK `sendUserMessage` settlement; the harness emits the real `message_end` while that Promise remains deferred.

## Implementation notes

- Execution capability: inline flagship implementation; cross-language lifecycle timing and real Docker verification required one owner to retain context.
- Review weight: standard (caller requested stop at `stage: review`).
- Files changed: `pi-extension/test/support/e2e_pi_host_runtime.ts`, `pi-extension/test/support/e2e_pi_host_server.ts`, `app/test/e2e/support/pi_host_client.dart`, `app/test/e2e/session_replacement_e2e_test.dart` (plus the shared pair-code seam files needed to restore the lane).
- Tests changed: replaced the five-second observational sleep with a deterministic production-wire regression. It proves the host and app rotate from the original session id to one distinct replacement id; the deferred SDK turn is still pending when the original `cli_` row becomes confirmed; the pending timer count is zero; no `sync_` or failed row exists; explicit settlement leaves exactly one confirmed row.
- Simplification: removed the old same-session harness limitation and fixed sleep; no production compatibility paths added.
- Discrepancies from design: the narrow Pi host retains one `ExtensionRunner` while rotating the actual SDK `SessionManager`, using the extension's documented same-factory replacement compatibility path instead of rebuilding the entire host process.
- Adjacent issues parked: none.
- Real harness evidence (2026-07-24): `e2e/run-pairing.sh` ran 16/16 tagged tests green, including `real replacement confirms cli id before replacement turn settles`; suite distribution was owner channel 7, pairing failures 5, session replacement 1, cross-room 1, hydration 1, QR lifecycle 1. Redaction checked 20 sensitive canaries.
- Broader verification: extension typecheck passed; extension Vitest passed 930 tests with 3 skipped; `flutter analyze` passed. The required non-E2E Flutter command was run twice: the load-sensitive full suite reported 840 passed/2 timing failures and then 841 passed/1 timing failure in pre-existing `sync_service_test.dart`; all reported cases passed immediately when rerun individually. No full non-E2E green claim is made.

## Review

Bounded inline review (orchestrator, 2026-07-24): diffs inspected; tests are
deterministic and defect-targeted (no sleeps, real assertions). Harness
evidence independently reproduced by the orchestrator: `e2e/run-pairing.sh`
16/16 passed + 20 redaction canaries on a fresh run. The pair-code seam
(OUTPOST_PI_PAIR_CODE_FILE, 0600, never logged, never in model context)
heals the e2e-lane regression from the TUI-only security fix while
preserving its invariant. Approved -> done.
