---
id: feature-cross-component-e2e-pairing-suite
kind: feature
stage: drafting
tags: [testing, e2e-test]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-02
---

# Cross-component e2e suite for the pairing → session-hydrate lifecycle

## Brief

Remote Pi shipped `v0.6.0` green-on-paper and non-functional: the `/remote-pi pair`
flow was broken by three sequential integration/lifecycle bugs (QR not rendering,
cross-room `pair_request` dropped, post-pair frames rejected for missing `room`).
Every one of them passed the unit suite because the unit tests used unrealistic
mock envelope shapes and lifecycle contexts — `session_start` ctx carrying
`sendMessage`, outer envelopes with no `room` field, inbound rooms always matching
the recipient's. The relay's `integration.rs` tests the relay alone; there is no
test that starts the relay + the pi extension + an app client together and
asserts the chronological lifecycle actually completes end to end.

This feature introduces a cross-component e2e harness that models the real
chronological steps an operator/user performs — start the relay, start the pi
session, pair a device, hydrate the session — and asserts each state transition
actually occurs across the wire. The goal is that the three bugs fixed this
session would each have failed a case in this suite.

Narrow first: this feature targets the **pairing arc** (relay up → pi session up
→ app pair → `pair_ok` → session transcript hydrates). The broader cross-component
program (reconnect, session-replacement `/new`/`/fork`, cross-PC mesh forwarding,
mobile lifecycle background/resume) is the natural follow-up scope and is called
out below — it should be promoted into its own features once this arc's harness is
proven, rather than ballooning this feature.

## Why this is a feature, not a story

It spans multiple subprojects (relay container, pi-extension, app client), needs a
real design pass to decide what to spin up vs service-level-mock, where the suite
lives, how it runs in CI vs locally, and how it asserts without becoming a brittle
re-implementation of the production code. Routes to `/agile-workflow:e2e-test-design`
once at `stage: drafting` (which it is).

## Strategic decisions

These are framing questions that shape the whole design. `e2e-test-design` will
resolve feature-internal choices; these set what the feature even *is*.

- **Live components vs service-level mocks**: Does the harness spin up a real relay
  container (the `remote-pi-relay` Docker image), a real pi-extension process
  (`dist/index.js` against the live SDK), and a real app client (Flutter
  `integration_test`, or a headless `dart:io`/Node WS client standing in for the
  app)? Or does it service-level-mock the boundaries (mock relay, drive the real
  extension + real app protocol layer)? The `e2e-test-design` skill defaults to
  service-level mocks; this bug class argues for at least one tier that runs the
  real relay + real extension together, because the bugs were in the *interaction*
  of real components, not in any one component's logic. — *Rationale: every bug
  this session was a contract mismatch at a real component boundary (SDK ctx
  shape, relay envelope rewrite, relay-required `room` field); mocks that don't
  reproduce the real boundary shape cannot catch them.*

- **Where the harness lives**: a new top-level `e2e/` dir, or under an existing
  subproject? The harness spans all three runtimes, so it likely needs its own
  home + runner rather than living inside `pi-extension/test/` or `relay/tests/`.

- **Run target**: local operator-runnable (so it can serve as the manual UAT
  backstop — see `story-release-uat-gate`), CI-runnable, or both? Memory/CAD
  constraints on the dev VM (the app APK build already needs heap-capping) are a
  real constraint on whether a real Flutter client can run in CI here.

- **Scope ceiling**: confirm pairing-arc-only for this feature, with reconnect /
  session-replacement / cross-PC / mobile-lifecycle as explicit follow-up
  features (not absorbed here). — *Locked: narrow-first; see "Out of scope".*

## What it must catch (regression contract)

At minimum, the suite must include cases that would have failed for each of the
three v0.6.0 bugs, so the bugs cannot regress:

1. **QR renders** — `/remote-pi pair` produces a `display:true`
   `remote-pi:pair-code` message that the (real or mocked) Pi TUI actually
   renders, after a real `session_start` (ctx without `sendMessage`).
   Catches `bindSessionContext` nulling the projection's `messageApi`.
2. **Pair_request reaches the Pi across rooms** — app (authed in `main`) sends
   `pair_request` targeting the Pi's cwd-room; the Pi receives it (relay rewrite
   delivers `outer.room='main'`) and replies `pair_ok`. Catches the recipient-side
   room guard.
3. **Post-pair traffic reaches the app** — after `pair_ok`, the Pi's outbound
   frames (`session_history`, `agent_chunk`) carry `room` and are accepted by the
   relay (not rejected `missing field room`) and delivered to the app. Catches the
   `PlainPeerChannel` missing-`room` regression.

The `e2e-test-design` pass will also add golden-path completeness, failure-mode
(relay down mid-pair, auth signature mismatch, token expiry/consumed), and the
tautology check (suite must not just re-assert what unit tests already prove).

## Out of scope (follow-up features, not this one)

- Reconnect / liveness-watchdog recovery (relay drop → re-pair or rehydrate).
- Session replacement (`/new`, `/fork`, `/resume`) end to end.
- Cross-PC mesh forwarding (`pi_envelope` / `pi_envelope_in`, `to_room`).
- Mobile lifecycle (background/resume, silent disconnect recovery).
- Cockpit desktop client coverage.

These are the broader cross-component program. Promote each into its own
`[testing]` feature once this harness's infrastructure is proven, so the
infrastructure cost is paid once and reused.

## Context

- The three fixed bugs and their root-cause analysis live in
  `.work/active/stories/story-pair-code-qr-not-rendering.md`,
  `story-pair-request-cross-room-dropped.md`, and
  `story-peer-channel-room-required.md`, plus the debugging arc in
  `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`. These are the
  regression-contract source.
- Companion process item: `story-release-uat-gate` — the manual human backstop
  that would have caught the gap *today*; this feature is the durable
  automation that catches it going forward. No inter-dependency.

## Next

`/agile-workflow:e2e-test-design` picks this up at `stage: drafting`, resolves the
strategic decisions above into a concrete design (taxonomy, infrastructure,
journey coverage), writes the design into this body, and spawns child stories
with `depends_on` chains advancing `drafting → implementing`.
