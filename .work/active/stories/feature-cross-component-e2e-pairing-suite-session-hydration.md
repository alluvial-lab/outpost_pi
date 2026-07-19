---
id: feature-cross-component-e2e-pairing-suite-session-hydration
kind: story
stage: done
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: [feature-cross-component-e2e-pairing-suite-cross-room-pairing]
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-18
---

# Prove post-pair session transcript hydration

## Checkpoint

Implement Unit 4 in `app/test/e2e/session_hydration_e2e_test.dart`. Seed one
deterministic persisted SDK entry before Pi `session_start`, complete pairing,
adopt the live transport through production `PlainPeerChannel` and
`ConnectionManager`, bind `SyncService` to the canonical session, send
`SessionSync`, and inspect the real Hive projection.

**Invariant**: after `pair_ok`, the app learns session identity, receives the
room-addressed `session_history`, and materializes the seeded transcript in its
active canonical session.

## Acceptance evidence

- [ ] Session identity comes through production room metadata and is non-empty before `SessionSync` is sent.
- [ ] The extension builds `session_history` from SDK/session projection state; the harness never injects a server frame.
- [ ] The final assertion reads a non-pending `MessageRecord` with the seeded role/text from the active Hive session.
- [ ] The case fails if extension `PlainPeerChannel` omits destination `room`, if relay rejects it, or if app room/session gates drop it.
- [ ] `SyncService`, `ConnectionManager`, channel, socket, timers, Hive boxes, secure-storage fixture, and temp directories all tear down in owner order.

## Test integrity

If real hydration fails because production is broken, park the bug and keep the
failing case as a linked skip with a one-line reason. Fix harness/fixture drift
in-session. Seeing a `session_history` type alone is not success; do not replace
the materialized transcript invariant with a mock call, frame snapshot, or
placeholder assertion.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected).
- Review weight: `standard` (caller).
- Files changed: `app/test/e2e/session_hydration_e2e_test.dart`.
- Tests added: real adopted `PlainPeerChannel`/`ConnectionManager`/`SyncService`, relay room snapshot identity, production `SessionSync`, extension SDK-history projection, generated decode, canonical session gate, encrypted-test Hive event/projection materialization.
- Simplification: the final assertion reads the disposable projection only after canonical event replay; no wire-frame test seam or synthetic `session_history` exists.
- Discrepancies from design: the helper lets `SyncService.requestSync()` own construction of `SessionSync` rather than constructing that production DTO in the test.
- Adjacent issues parked: none.
- Verification: Flutter analyze of `test/e2e/`; `e2e/run-pairing.sh` passed hydration and both prerequisite cases.
