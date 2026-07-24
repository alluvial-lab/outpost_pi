---
id: story-e2e-session-replacement-case
kind: story
stage: done
tags: [app, pi-extension, e2e, session, lifecycle]
parent: null
depends_on: [feature-replacement-session-wake-confirmation]
release_binding: v0.3.0
gate_origin: null
created: 2026-07-23
updated: 2026-07-24
---

# E2E case: session replacement (`/new`) message round-trip

## Brief

Add a session-replacement case to the existing e2e pairing suite
(`app/test/e2e/`, driven by `e2e/run-pairing.sh`): pair, start a turn, issue
`/new` mid-conversation, then send a message and assert (a) the send
confirmation appears promptly — not stuck/false-timeout — and (b) exactly one
copy of the user message lands in the transcript after the turn.

This is the standing regression net for the bug class fixed in
`feature-replacement-session-wake-confirmation` (replacement-session
`sendUserMessage` full-turn `Promise` being unconditionally awaited —
stuck/false-failure + duplicate echo). The pairing e2e covers pairing,
auth-failure, QR lifecycle, and hydration, but nothing exercises session
replacement, which is where this defect lived.

## Simplification opportunity

Reuse the existing e2e pi-host adapter (`e2e/tsconfig.pi-host.json`) and
Docker/Toxiproxy harness — no new infrastructure, one new test file following
the `session_hydration_e2e_test.dart` pattern.

## Origin

Advisor review 2026-07-23, recommendation #4.

## Implementation notes

- Execution capability: inline host session — one new test file against the
  existing harness; no delegation value.
- Review weight: standard (default) — standalone story, bounded inline lane.
- Files changed: `app/test/e2e/session_replacement_e2e_test.dart` (new, 170
  lines). No harness, production, or script changes.
- Tests added: the story's single e2e case — baseline live-turn confirm →
  `session_new` via production `ActionsRepository` → post-replacement wipe
  convergence gate → first post-replacement message: prompt confirmation
  (15s bound) + exact-once transcript count after a 5s settle window.
- Verification: `flutter analyze` clean; isolated run against a retained
  stack green; full `e2e/run-pairing.sh` green (8/8 tests, redaction
  canaries pass).
- **Implementation discovery (harness limitation, verified live)**: the
  pi-host's stubbed `bindCommandContext.newSession` returns
  `{cancelled: false}` without rotating the SessionManager, so the harness
  cannot produce a new session identity — the original "replacement session
  identity" gate timed out (10s) in the first full-suite run while all 7
  pre-existing cases passed. Diagnosed via retained-stack rerun + pi-host
  logs; test redesigned to gate on the post-replacement *wipe* (empty
  `session_history` fan-out erases the confirmed baseline row) instead,
  which is the production-meaningful convergence signal. Also documented:
  instant stub turns make the buggy timing symptom unobservable in-harness —
  the net covers the wipe/confirm/exactly-once contract; the timing fix
  itself was verified on-device in `feature-replacement-session-wake-confirmation`.
- Discrepancies from design: story brief said "issue /new mid-conversation,
  then send" — implemented as baseline-send → /new → send (the baseline
  proves the harness live-turn path before the replacement, so failures
  attribute correctly).
- Adjacent issues parked: none (harness newSession-rotation improvement
  noted here; not worth a backlog item until a second case needs it).

## Review record (bounded inline, standalone-story lane)

- No independent/cross-model reviewer (per lane rules).
- Test integrity: exercises production paths end-to-end (WsTransport,
  performPairing, ConnectionManager, SyncService, ActionsRepository) against
  the real extension logic in the pi-host; no system-under-test mocking
  beyond the established pi-host SDK stub. Assertions are the fixed
  contract, not the bug's absence-by-timing. Harness limitations are
  documented in the test's doc comment, not hidden.
- Race check: the wipe gate orders the post-replacement send after the
  extension's empty session_history fan-out — no optimistic-row/wipe race.
- Verdict: approve → done.
