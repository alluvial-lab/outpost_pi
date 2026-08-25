---
id: gate-tests-soak-terminal-boundary-behavior
kind: story
stage: done
tags: [testing, app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Replace the soak terminal-boundary source check with behavioral evidence

## Priority
High

## Value evidence
Item: `story-fix-app-post-quiescence-working-stuck`. Its root cause is
conditional: a standalone `net_down` recovery prompt must arm a fake-SDK turn
only when no turn is already armed/pending, then await pending, resolve it, and
observe authoritative `working:false`; the seed's already-pending turn must not
be resolved early. The only routine regression test checks three substrings in
generated Dart (`e2e/test_live_soak.py:132-142`). It passes if those strings
move into dead code, lose their phase guard/order, or resolve the staged turn
unconditionally. That is materially weaker than the real false-positive claim;
the two 300-second seed runs are valuable confirmation but not a routine guard.

## Gap type
bug-regression / generated-harness behavioral seam

## Suggested test
```python
# Add a bounded service-level scenario around the generated recovery handler.
# Feed both host phases (idle and already pending), record defer/send/reconnect/
# resolve calls and working transitions, and assert exact order/cardinality:
# idle => defer once, await pending, resolve once, authoritative idle;
# pending => no defer and no early resolve. Keep one generated-Dart compile
# smoke so template drift cannot invalidate the behavioral fixture.
```

## Test location (suggested)
`e2e/test_live_soak.py` plus a service-level fake for the generated recovery handler

## Implementation

Replaced the three-substring assertion with an executable boundary fixture.
The generated soak now embeds one callback-driven
`_runNetDownRecoveryBoundary` helper and routes the real net-down handler
through it. The helper owns the conditional arm, reconnect/send overlap,
online wait, pending wait, resolve, and authoritative-idle wait in one ordered
operation.

The Python unit extracts that exact generated Dart helper, compiles and runs it
with a service-level fake, and asserts exact call order/cardinality for both
host phases:

- idle: `read → defer → reconnect → send → online → pending → resolve → idle`;
- already pending: `read → reconnect → send → online`, with no defer, pending
  wait, early resolve, or idle wait.

Because the executable helper is also asserted to be the helper embedded in the
full generated soak source, template drift cannot leave the behavioral fixture
testing a detached copy. No product defect was found.

Verification:

- `python3 -m unittest e2e.test_live_soak` (21 passed; includes generated Dart compile/run smoke)
