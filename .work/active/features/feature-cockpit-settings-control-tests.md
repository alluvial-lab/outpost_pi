---
id: feature-cockpit-settings-control-tests
kind: feature
stage: drafting
tags: [cockpit, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-15
updated: 2026-07-16
---

# Cockpit: behavior coverage for the settings/control split

## Brief

Three test-quality gate findings describe coverage gaps in the Cockpit
settings/control surface — the tests sample one value, cover rename/cancel but
not the successful create flow, and assert only importability rather than
persistence/controller behavior. This feature adds behavior-level coverage:

- `gate-tests-app-preference-persistence` — app-preference panels only have importability coverage, not persistence/controller behavior
- `gate-tests-control-command-serialization` — control-command serialization test only samples one relay action
- `gate-tests-daemon-create-flow` — daemon tests cover rename/cancel but not the successful create flow

## Simplification opportunity

Strengthen existing tests to cover the behavior contracts (persistence,
full serialization matrix, successful create). No production-code change
required unless a test surfaces a real bug — in which case route that as a
separate story.

## Source

Promoted from backlog by `scope` (2026-07-15). 3 `gate-tests-*` findings from
the v0.6.0 release `gate-tests` pass.
