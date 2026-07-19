---
id: feature-cross-component-e2e-pairing-suite-qr-lifecycle
kind: story
stage: implementing
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: [feature-cross-component-e2e-pairing-suite-infra]
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-18
---

# Prove QR publication after a realistic session_start

## Checkpoint

Implement Unit 2's QR regression case in
`app/test/e2e/qr_lifecycle_e2e_test.dart`. Start a fresh SDK-backed Pi host,
invoke the registered `/outpost-pi pair` command, and observe the message
accepted by the Pi host's user-visible TUI action boundary.

**Invariant**: after a real Pi session starts, pairing displays a
`display:true` `outpost-pi:pair-code` message containing a production-parser-
accepted URI targeted at the Pi's non-`main` cwd-room.

## Acceptance evidence

- [ ] The Pi-host generation reports ready only after the real extension accepted `session_start`, whose context lacks `sendMessage`/`sendUserMessage`.
- [ ] The observed message has `customType == outpost-pi:pair-code`, `display == true`, and a URI accepted by `QrPairPayload.tryParse`.
- [ ] Parsed room equals the Pi-host room and is not `main`; token and public-key byte lengths satisfy the production parser.
- [ ] The case fails if `bindSessionContext` nulls the API armed by `bindApi`.
- [ ] Diagnostics include transition names only, never URI/token/key/transcript contents.

## Test integrity

If the case finds a production bug, park it and keep the honest failing test as
a linked skip with a one-line reason; do not weaken the invariant. Fix fixture
or harness drift in-session. Never replace the TUI boundary assertion with
`buildQRUri`, a mock invocation count, a snapshot-only assertion, or a
placeholder truth.
