---
id: story-e2e-session-replacement-case
kind: story
stage: implementing
tags: [app, pi-extension, e2e, session, lifecycle]
parent: null
depends_on: [feature-replacement-session-wake-confirmation]
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
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
